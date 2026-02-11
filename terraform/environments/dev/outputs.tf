# terraform outputs
#
# these outputs expose important information about the infrastructure
# for use in other terraform configurations or automation scripts

#############################################
# network outputs
#############################################

output "network_name" {
  description = "name of the VPC network"
  value       = module.vpc.network_name
}

output "network_id" {
  description = "ID of the VPC network"
  value       = module.vpc.network_id
}

output "subnet_name" {
  description = "name of the GKE subnet"
  value       = module.vpc.subnets["${var.region}/${local.network_name_full}-subnet"].name
}

output "subnet_id" {
  description = "ID of the GKE subnet"
  value       = module.vpc.subnets["${var.region}/${local.network_name_full}-subnet"].id
}

output "pods_ip_range" {
  description = "IP range for Kubernetes pods"
  value       = var.pods_ip_range
}

output "services_ip_range" {
  description = "IP range for Kubernetes services"
  value       = var.services_ip_range
}

#############################################
# GKE cluster outputs
#############################################

output "cluster_name" {
  description = "name of the GKE cluster"
  value       = module.gke.name
}

output "cluster_id" {
  description = "ID of the GKE cluster"
  value       = module.gke.cluster_id
}

output "cluster_endpoint" {
  description = "endpoint for the GKE cluster API server"
  value       = module.gke.endpoint
  sensitive   = true
}

output "cluster_ca_certificate" {
  description = "CA certificate for the GKE cluster"
  value       = module.gke.ca_certificate
  sensitive   = true
}

output "cluster_location" {
  description = "location (region) of the GKE cluster"
  value       = module.gke.location
}

output "cluster_region" {
  description = "region of the GKE cluster"
  value       = module.gke.region
}

output "cluster_zones" {
  description = "zones where GKE nodes are deployed"
  value       = module.gke.zones
}

output "kubernetes_version" {
  description = "Kubernetes version of the cluster"
  value       = module.gke.master_version
}

#############################################
# service account outputs
#############################################

output "gke_service_account_email" {
  description = "email address of the GKE node service account"
  value       = google_service_account.gke_nodes.email
}

output "gke_service_account_name" {
  description = "name of the GKE node service account"
  value       = google_service_account.gke_nodes.name
}

#############################################
# workload identity outputs
#############################################

output "workload_identity_namespace" {
  description = "Workload Identity namespace for the cluster"
  value       = var.enable_workload_identity ? "${var.project_id}.svc.id.goog" : null
}

#############################################
# Cloud NAT outputs
#############################################

output "nat_router_name" {
  description = "name of the Cloud Router for NAT"
  value       = module.cloud_nat.router_name
}

output "nat_name" {
  description = "name of the Cloud NAT gateway"
  value       = module.cloud_nat.name
}

#############################################
# connection instructions
#############################################

output "kubectl_connection_command" {
  description = "command to configure kubectl to connect to this cluster"
  value       = "gcloud container clusters get-credentials ${module.gke.name} --region ${var.region} --project ${var.project_id}"
}

output "cluster_dashboard_url" {
  description = "URL to view the cluster in GCP Console"
  value       = "https://console.cloud.google.com/kubernetes/clusters/details/${var.region}/${module.gke.name}/details?project=${var.project_id}"
}

#############################################
# summary output
#############################################

output "deployment_summary" {
  description = "summary of the deployed infrastructure"
  value = {
    project_id              = var.project_id
    environment             = var.environment
    region                  = var.region
    cluster_name            = module.gke.name
    cluster_type            = "Private GKE"
    network_name            = module.vpc.network_name
    node_pools              = ["system-pool", "workload-pool"]
    workload_identity       = var.enable_workload_identity
    network_policy_enabled  = var.enable_network_policy
  }
}
