# k8sAtlas GKE infrastructure - main configuration
#
# this configuration creates a production-ready private GKE cluster using
# official Google Cloud terraform modules
#
# architecture:
# - private VPC with custom subnets
# - private GKE cluster (no public endpoint)
# - Cloud NAT for egress traffic
# - Workload Identity for secure GCP service access
# - multiple node pools with autoscaling

# local variables for resource naming and configuration
locals {
  cluster_name_full = "${var.cluster_name}-${var.environment}"
  network_name_full = "${var.network_name}-${var.environment}"

  # Service account for GKE nodes
  gke_service_account = "${var.cluster_name}-${var.environment}-sa"
}

#############################################
# VPC network
#############################################

module "vpc" {
  source  = "terraform-google-modules/network/google"
  version = "~> 9.0"

  project_id   = var.project_id
  network_name = local.network_name_full
  routing_mode = "REGIONAL"

  subnets = [
    {
      subnet_name           = "${local.network_name_full}-subnet"
      subnet_ip             = var.subnet_ip_range
      subnet_region         = var.region
      subnet_private_access = true # Enable Private Google Access
      description           = "Subnet for GKE nodes in ${var.environment}"
    }
  ]

  secondary_ranges = {
    "${local.network_name_full}-subnet" = [
      {
        range_name    = "pods"
        ip_cidr_range = var.pods_ip_range
      },
      {
        range_name    = "services"
        ip_cidr_range = var.services_ip_range
      }
    ]
  }

  # Firewall rules
  firewall_rules = []
}

#############################################
# Cloud NAT
# required for private GKE nodes to access the internet
#############################################

module "cloud_nat" {
  source  = "terraform-google-modules/cloud-nat/google"
  version = "~> 5.0"

  project_id    = var.project_id
  region        = var.region
  router        = "${local.network_name_full}-router"
  name          = "${local.network_name_full}-nat"
  network       = module.vpc.network_id
  create_router = true

  # Cost optimization: use manual IP allocation
  source_subnetwork_ip_ranges_to_nat = "LIST_OF_SUBNETWORKS"

  subnetworks = [
    {
      name                     = module.vpc.subnets["${var.region}/${local.network_name_full}-subnet"].id
      source_ip_ranges_to_nat  = ["ALL_IP_RANGES"]
      secondary_ip_range_names = []
    }
  ]
}

#############################################
# GKE service account
# separate service account for GKE nodes (least privilege)
#############################################

resource "google_service_account" "gke_nodes" {
  project      = var.project_id
  account_id   = local.gke_service_account
  display_name = "GKE Node Service Account for ${var.environment}"
  description  = "Service account for GKE nodes in ${var.environment} environment"
}

# minimal IAM permissions for GKE nodes
resource "google_project_iam_member" "gke_nodes_log_writer" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.gke_nodes.email}"
}

resource "google_project_iam_member" "gke_nodes_metric_writer" {
  project = var.project_id
  role    = "roles/monitoring.metricWriter"
  member  = "serviceAccount:${google_service_account.gke_nodes.email}"
}

resource "google_project_iam_member" "gke_nodes_monitoring_viewer" {
  project = var.project_id
  role    = "roles/monitoring.viewer"
  member  = "serviceAccount:${google_service_account.gke_nodes.email}"
}

resource "google_project_iam_member" "gke_nodes_resource_metadata_writer" {
  project = var.project_id
  role    = "roles/stackdriver.resourceMetadata.writer"
  member  = "serviceAccount:${google_service_account.gke_nodes.email}"
}

# for Artifact Registry access (pulling images)
resource "google_project_iam_member" "gke_nodes_artifact_registry_reader" {
  project = var.project_id
  role    = "roles/artifactregistry.reader"
  member  = "serviceAccount:${google_service_account.gke_nodes.email}"
}

#############################################
# private GKE cluster
#############################################

module "gke" {
  source  = "terraform-google-modules/kubernetes-engine/google//modules/private-cluster"
  version = "~> 33.0"

  # Project and Location
  project_id        = var.project_id
  name              = local.cluster_name_full
  region            = var.region
  zones             = var.zones
  regional          = true # Multi-zonal for HA

  # Network Configuration
  network                 = module.vpc.network_name
  subnetwork              = module.vpc.subnets["${var.region}/${local.network_name_full}-subnet"].name
  ip_range_pods           = "pods"
  ip_range_services       = "services"

  # Private Cluster Configuration
  enable_private_endpoint = var.enable_private_endpoint
  enable_private_nodes    = var.enable_private_nodes
  master_ipv4_cidr_block  = var.master_ipv4_cidr_block

  # Master Authorized Networks (allow access from specific IPs)
  master_authorized_networks = var.master_authorized_networks

  # Kubernetes Version
  kubernetes_version = var.kubernetes_version
  release_channel    = var.release_channel

  # Node Configuration
  remove_default_node_pool = true # We create custom node pools below
  initial_node_count       = 1    # Temporary, removed after custom pools

  # Cluster Features
  horizontal_pod_autoscaling = true
  http_load_balancing        = true # For Ingress
  network_policy             = var.enable_network_policy
  datapath_provider          = "ADVANCED_DATAPATH" # Uses eBPF for better performance

  # Security
  enable_shielded_nodes      = var.enable_shielded_nodes
  enable_binary_authorization = var.enable_binary_authorization

  # Workload Identity
  identity_namespace = var.enable_workload_identity ? "${var.project_id}.svc.id.goog" : null

  # Logging and Monitoring
  logging_service    = "logging.googleapis.com/kubernetes"
  monitoring_service = "monitoring.googleapis.com/kubernetes"

  cluster_resource_labels = var.cluster_labels

  # Maintenance Window
  maintenance_start_time = var.maintenance_start_time
  maintenance_recurrence = var.maintenance_recurrence

  # Cost Optimization
  enable_cost_allocation = true

  # Node Pools (defined below)
  node_pools = [
    {
      name               = "system-pool"
      machine_type       = var.system_node_pool_machine_type
      node_locations     = join(",", var.zones)
      min_count          = var.system_node_pool_min_count
      max_count          = var.system_node_pool_max_count
      local_ssd_count    = 0
      spot               = false
      disk_size_gb       = var.node_disk_size_gb
      disk_type          = var.node_disk_type
      image_type         = "COS_CONTAINERD"
      enable_gcfs        = false
      enable_gvnic       = true # Google Virtual NIC for better performance
      auto_repair        = true
      auto_upgrade       = true
      service_account    = google_service_account.gke_nodes.email
      preemptible        = false
      initial_node_count = var.system_node_pool_min_count
    },
    {
      name               = "workload-pool"
      machine_type       = var.workload_node_pool_machine_type
      node_locations     = join(",", var.zones)
      min_count          = var.workload_node_pool_min_count
      max_count          = var.workload_node_pool_max_count
      local_ssd_count    = 0
      spot               = var.enable_preemptible_nodes  # use spot VMs for cost savings
      disk_size_gb       = var.node_disk_size_gb
      disk_type          = var.node_disk_type
      image_type         = "COS_CONTAINERD"
      enable_gcfs        = false
      enable_gvnic       = true
      auto_repair        = true
      auto_upgrade       = true
      service_account    = google_service_account.gke_nodes.email
      preemptible        = false  #using spot instead
      initial_node_count = var.workload_node_pool_min_count
    }
  ]

  node_pools_oauth_scopes = {
    all = [
      "https://www.googleapis.com/auth/cloud-platform"
    ]
  }

  node_pools_labels = {
    all = var.node_labels

    system-pool = {
      pool_type = "system"
      workload  = "platform"
    }

    workload-pool = {
      pool_type = "workload"
      workload  = "application"
    }
  }

  node_pools_metadata = {
    all = {
      disable-legacy-endpoints = "true"
    }
  }

  node_pools_tags = {
    all = var.node_tags
  }

  node_pools_taints = {
    system-pool = [
      {
        key    = "CriticalAddonsOnly"
        value  = "true"
        effect = "NO_SCHEDULE"
      }
    ]
  }

  depends_on = [
    module.vpc,
    module.cloud_nat,
    google_service_account.gke_nodes
  ]
}

#############################################
# firewall rules
# allow necessary traffic for GKE operation
#############################################

# allow health checks from GCP load balancers
resource "google_compute_firewall" "allow_health_checks" {
  name    = "${local.network_name_full}-allow-health-checks"
  network = module.vpc.network_name
  project = var.project_id

  allow {
    protocol = "tcp"
  }

  source_ranges = [
    "35.191.0.0/16",  # GCP Health Checks
    "130.211.0.0/22", # GCP Health Checks
  ]

  target_tags = var.node_tags
}

# allow master to access nodes (for kubectl, logs, etc.)
resource "google_compute_firewall" "allow_master_to_nodes" {
  name    = "${local.network_name_full}-allow-master-to-nodes"
  network = module.vpc.network_name
  project = var.project_id

  allow {
    protocol = "tcp"
    ports    = ["443", "10250"]
  }

  source_ranges = [var.master_ipv4_cidr_block]
  target_tags   = var.node_tags
}
