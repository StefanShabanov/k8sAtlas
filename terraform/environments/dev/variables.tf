# variables for k8sAtlas GKE infrastructure
#
# this file defines all input variables for the infrastructure
# actual values should be provided in terraform.tfvars (not committed to Git)

# project configuration
variable "project_id" {
  description = "The GCP project ID"
  type        = string
}

variable "region" {
  description = "The GCP region for resources"
  type        = string
  default     = "europe-west4"
}

variable "zones" {
  description = "The GCP zones within the region for multi-zonal resources"
  type        = list(string)
  default     = ["europe-west4-a", "europe-west4-b", "europe-west4-c"]
}

# naming
variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  default     = "dev"
}

variable "cluster_name" {
  description = "Name of the GKE cluster"
  type        = string
  default     = "k8satlas-gke"
}

# network configuration
variable "network_name" {
  description = "Name of the VPC network"
  type        = string
  default     = "k8satlas-vpc"
}

variable "subnet_ip_range" {
  description = "IP CIDR range for the subnet (primary range for nodes)"
  type        = string
  default     = "10.0.0.0/20" # 10.0.0.0 - 10.0.15.255 (4096 IPs)
}

variable "pods_ip_range" {
  description = "IP CIDR range for Kubernetes pods (secondary range)"
  type        = string
  default     = "10.4.0.0/14" # 10.4.0.0 - 10.7.255.255 (262k IPs)
}

variable "services_ip_range" {
  description = "IP CIDR range for Kubernetes services (secondary range)"
  type        = string
  default     = "10.8.0.0/20" # 10.8.0.0 - 10.8.15.255 (4096 IPs)
}

variable "master_ipv4_cidr_block" {
  description = "IP CIDR range for the GKE master (private endpoint)"
  type        = string
  default     = "172.16.0.0/28" # 172.16.0.0 - 172.16.0.15 (16 IPs)
}

# GKE cluster configuration
variable "kubernetes_version" {
  description = "Kubernetes version for the cluster (use 'latest' for most recent stable)"
  type        = string
  default     = "latest"
}

variable "release_channel" {
  description = "Release channel for GKE (RAPID, REGULAR, STABLE)"
  type        = string
  default     = "REGULAR"
}

variable "enable_private_endpoint" {
  description = "Enable private GKE endpoint (no public access to control plane)"
  type        = bool
  default     = true
}

variable "enable_private_nodes" {
  description = "Enable private nodes (nodes have no public IPs)"
  type        = bool
  default     = true
}

variable "master_authorized_networks" {
  description = "List of CIDR blocks that can access the GKE master endpoint"
  type = list(object({
    cidr_block   = string
    display_name = string
  }))
  default = []
}

# node pool configuration
variable "system_node_pool_machine_type" {
  description = "Machine type for system node pool"
  type        = string
  default     = "e2-small" # 2 vCPU, 2 GB RAM
}

variable "system_node_pool_min_count" {
  description = "Minimum number of nodes in system pool"
  type        = number
  default     = 1
}

variable "system_node_pool_max_count" {
  description = "Maximum number of nodes in system pool"
  type        = number
  default     = 3
}

variable "workload_node_pool_machine_type" {
  description = "Machine type for workload node pool"
  type        = string
  default     = "e2-medium" # 2 vCPU, 4 GB RAM
}

variable "workload_node_pool_min_count" {
  description = "Minimum number of nodes in workload pool"
  type        = number
  default     = 1
}

variable "workload_node_pool_max_count" {
  description = "Maximum number of nodes in workload pool"
  type        = number
  default     = 5
}

variable "node_disk_size_gb" {
  description = "Disk size in GB for cluster nodes"
  type        = number
  default     = 50
}

variable "node_disk_type" {
  description = "Disk type for cluster nodes (pd-standard, pd-balanced, pd-ssd)"
  type        = string
  default     = "pd-balanced"
}

# security & features
variable "enable_workload_identity" {
  description = "Enable Workload Identity for secure pod-to-GCP service authentication"
  type        = bool
  default     = true
}

variable "enable_network_policy" {
  description = "Enable network policy enforcement (Calico)"
  type        = bool
  default     = true
}

variable "enable_binary_authorization" {
  description = "Enable Binary Authorization for image security"
  type        = bool
  default     = false
}

variable "enable_shielded_nodes" {
  description = "Enable Shielded GKE Nodes for enhanced security"
  type        = bool
  default     = true
}

variable "enable_intranode_visibility" {
  description = "Enable intranode visibility for better network monitoring"
  type        = bool
  default     = true
}

# logging & monitoring
variable "logging_components" {
  description = "GKE components to enable logging for"
  type        = list(string)
  default     = ["SYSTEM_COMPONENTS", "WORKLOADS"]
}

variable "monitoring_components" {
  description = "GKE components to enable monitoring for"
  type        = list(string)
  default     = ["SYSTEM_COMPONENTS"]
}

variable "enable_managed_prometheus" {
  description = "Enable Google Cloud Managed Service for Prometheus"
  type        = bool
  default     = false # We'll use our own Prometheus in Phase 4
}

# maintenance
variable "maintenance_start_time" {
  description = "Start time for maintenance window (HH:MM in UTC)"
  type        = string
  default     = "03:00" # 3 AM UTC
}

variable "maintenance_recurrence" {
  description = "Recurrence for maintenance window (RFC 5545 RRULE)"
  type        = string
  default     = "FREQ=WEEKLY;BYDAY=SU" # Every Sunday
}

# cost optimization
variable "enable_autopilot" {
  description = "Enable GKE Autopilot mode (fully managed, costs based on pod resources)"
  type        = bool
  default     = false # Using Standard mode for more control
}

variable "enable_preemptible_nodes" {
  description = "Use Spot VMs for workload node pool (up to 80% cost savings, can be terminated)"
  type        = bool
  default     = false # Can enable for non-critical dev workloads
}

# tags & labels
variable "cluster_labels" {
  description = "Labels to apply to the GKE cluster"
  type        = map(string)
  default = {
    managed_by  = "terraform"
    project     = "k8satlas"
    environment = "dev"
  }
}

variable "node_labels" {
  description = "Labels to apply to all nodes"
  type        = map(string)
  default = {
    managed_by = "terraform"
  }
}

variable "node_tags" {
  description = "Network tags to apply to all nodes"
  type        = list(string)
  default     = ["gke-node", "k8satlas"]
}
