# k8sAtlas Makefile
# Production-ready GKE Platform automation

.PHONY: help bootstrap init plan apply destroy kubeconfig clean fmt validate check-tools install-platform test-ingress get-ingress-ip check-cert platform-status

# Default target
.DEFAULT_GOAL := help

# Variables
BASH := /c/Program Files/Git/usr/bin/bash.exe
PROJECT_ID ?= $(shell gcloud config get-value project)
REGION ?= europe-west4
CLUSTER_NAME ?= k8satlas-gke-dev
TF_DIR = terraform/environments/dev
SCRIPTS_DIR = scripts

# Colors for output
BLUE := \033[0;34m
GREEN := \033[0;32m
YELLOW := \033[0;33m
RED := \033[0;31m
NC := \033[0m # No Color

##@ General

help: ## Display this help message
	@echo "$(BLUE)k8sAtlas - Production-Ready GKE Platform$(NC)"
	@echo ""
	@echo "$(GREEN)Usage:$(NC)"
	@echo "  make $(BLUE)<target>$(NC)"
	@echo ""
	@awk 'BEGIN {FS = ":.*##"; printf "\n"} /^[a-zA-Z_-]+:.*?##/ { printf "  $(BLUE)%-20s$(NC) %s\n", $$1, $$2 } /^##@/ { printf "\n$(YELLOW)%s$(NC)\n", substr($$0, 5) } ' $(MAKEFILE_LIST)

check-tools: ## Check if required tools are installed
	@echo "$(BLUE)Checking required tools.$(NC)"
	@command -v gcloud >/dev/null 2>&1 || { echo "$(RED)ERROR: gcloud is not installed$(NC)"; exit 1; }
	@command -v terraform >/dev/null 2>&1 || { echo "$(RED)ERROR: terraform is not installed$(NC)"; exit 1; }
	@command -v kubectl >/dev/null 2>&1 || { echo "$(RED)ERROR: kubectl is not installed$(NC)"; exit 1; }
	@command -v helm >/dev/null 2>&1 || { echo "$(RED)ERROR: helm is not installed$(NC)"; exit 1; }
	@echo "$(GREEN) All required tools are installed$(NC)"

##@ Phase 0 - Bootstrap

bootstrap: check-tools ## Run GCP bootstrap script (creates state bucket, enables APIs)
	@echo "$(BLUE)Running GCP bootstrap.$(NC)"
	@if [ ! -f "$(SCRIPTS_DIR)/bootstrap.sh" ]; then \
		echo "$(RED)ERROR: bootstrap.sh not found. Create it first.$(NC)"; \
		exit 1; \
	fi
	@bash $(SCRIPTS_DIR)/bootstrap.sh
	@echo "$(GREEN) Bootstrap complete$(NC)"

##@ Phase 1 - Infrastructure

init: check-tools ## Initialize Terraform (run after bootstrap)
	@echo "$(BLUE)Initializing Terraform..$(NC)"
	@cd $(TF_DIR) && terraform init
	@echo "$(GREEN) Terraform initialized$(NC)"

plan: ## Run Terraform plan
	@echo "$(BLUE)Running Terraform plan.$(NC)"
	@cd $(TF_DIR) && terraform plan -out=tfplan
	@echo "$(GREEN) Plan created: $(TF_DIR)/tfplan$(NC)"

apply: ## Apply Terraform changes
	@echo "$(YELLOW) WARNING: This will create/modify GCP resources and incur costs$(NC)"
	@echo "Press Ctrl+C to cancel, or Enter to continue."
	@read confirm
	@echo "$(BLUE)Applying Terraform.$(NC)"
	@cd $(TF_DIR) && terraform apply tfplan
	@rm -f $(TF_DIR)/tfplan
	@echo "$(GREEN) Infrastructure deployed$(NC)"
	@echo "$(BLUE)Run 'make kubeconfig' to configure kubectl access$(NC)"

destroy: ## Destroy all Terraform-managed resources
	@echo "$(RED) WARNING: This will DESTROY all resources!$(NC)"
	@echo "Type 'yes' to confirm destruction:"
	@read confirm && [ "$$confirm" = "yes" ] || (echo "$(YELLOW)Destruction cancelled$(NC)" && exit 1)
	@echo "$(BLUE)Destroying infrastructure.$(NC)"
	@cd $(TF_DIR) && terraform destroy
	@echo "$(GREEN) Infrastructure destroyed$(NC)"

fmt: ## Format Terraform code
	@echo "$(BLUE)Formatting Terraform code.$(NC)"
	@terraform fmt -recursive terraform/
	@echo "$(GREEN) Code formatted$(NC)"

validate: init ## Validate Terraform configuration
	@echo "$(BLUE)Validating Terraform.$(NC)"
	@cd $(TF_DIR) && terraform validate
	@echo "$(GREEN) Configuration valid$(NC)"

##@ Phase 2 - Platform Services

install-platform: ## Install all platform services (NGINX, Cert-Manager)
	@echo "$(BLUE)Installing Phase 2 platform services.$(NC)"
	@bash $(SCRIPTS_DIR)/install-platform-services.sh

test-ingress: ## Test ingress and TLS with dummy service
	@echo "$(BLUE)Testing ingress and TLS.$(NC)"
	@bash $(SCRIPTS_DIR)/test-ingress.sh

get-ingress-ip: ## Get LoadBalancer IP for DNS configuration
	@echo "$(BLUE)LoadBalancer IP:$(NC)"
	@kubectl get svc ingress-nginx-controller -n platform \
		-o jsonpath='{.status.loadBalancer.ingress[0].ip}'
	@echo ""
	@echo ""
	@echo "$(BLUE)Configure this IP in Cloudflare:$(NC)"
	@echo "  Type: A"
	@echo "  Name: *.k8s"
	@echo "  Content: $$(kubectl get svc ingress-nginx-controller -n platform -o jsonpath='{.status.loadBalancer.ingress[0].ip}')"
	@echo "  Proxy: ☁ Proxied"

check-cert: ## Check certificate status
	@echo "$(BLUE)ClusterIssuers:$(NC)"
	@kubectl get clusterissuers
	@echo ""
	@echo "$(BLUE)Certificates (all namespaces):$(NC)"
	@kubectl get certificates --all-namespaces

platform-status: ## Show platform services status
	@echo "$(BLUE)Platform Services Status:$(NC)"
	@echo ""
	@echo "$(YELLOW)NGINX Ingress Controller:$(NC)"
	@kubectl get pods -n platform
	@echo ""
	@echo "$(YELLOW)Cert-Manager:$(NC)"
	@kubectl get pods -n cert-manager
	@echo ""
	@echo "$(YELLOW)LoadBalancer:$(NC)"
	@kubectl get svc ingress-nginx-controller -n platform

##@ Kubernetes Operations

kubeconfig: ## Get GKE cluster credentials
	@echo "$(BLUE)Fetching GKE cluster credentials.$(NC)"
	@gcloud container clusters get-credentials $(CLUSTER_NAME) \
		--region=$(REGION) \
		--project=$(PROJECT_ID)
	@echo "$(GREEN) Kubeconfig updated$(NC)"
	@kubectl cluster-info

verify: ## Verify cluster health and connectivity
	@echo "$(BLUE)Verifying cluster.$(NC)"
	@bash $(SCRIPTS_DIR)/verify-cluster.sh

k8s-namespaces: ## Create Kubernetes namespaces
	@echo "$(BLUE)Creating namespaces.$(NC)"
	@kubectl create namespace platform --dry-run=client -o yaml | kubectl apply -f -
	@kubectl create namespace monitoring --dry-run=client -o yaml | kubectl apply -f -
	@kubectl create namespace production --dry-run=client -o yaml | kubectl apply -f -
	@kubectl create namespace staging --dry-run=client -o yaml | kubectl apply -f -
	@echo "$(GREEN) Namespaces created$(NC)"

##@ Application Operations

build-app: ## Build application Docker image
	@echo "$(BLUE)Building application.$(NC)"
	@cd app && docker build -t $(CLUSTER_NAME)-app:latest .
	@echo "$(GREEN) Application built$(NC)"

push-app: ## Push application to Artifact Registry
	@echo "$(BLUE)Pushing to Artifact Registry.$(NC)"
	@echo "$(RED)TODO: Implement after Artifact Registry is created$(NC)"

deploy-app: ## Deploy application to Kubernetes
	@echo "$(BLUE)Deploying application.$(NC)"
	@kubectl apply -k k8s/apps/api/
	@echo "$(GREEN) Application deployed$(NC)"

##@ Monitoring & Observability

port-forward-grafana: ## Port-forward to Grafana
	@echo "$(BLUE)Port-forwarding to Grafana on http://localhost:3000$(NC)"
	@kubectl port-forward -n monitoring svc/kube-prometheus-stack-grafana 3000:80

port-forward-prometheus: ## Port-forward to Prometheus
	@echo "$(BLUE)Port-forwarding to Prometheus on http://localhost:9090$(NC)"
	@kubectl port-forward -n monitoring svc/kube-prometheus-stack-prometheus 9090:9090

logs-app: ## Tail application logs
	@echo "$(BLUE)Tailing application logs.$(NC)"
	@kubectl logs -f -n production -l app=api --tail=100

##@ Utilities

clean: ## Clean up temporary files
	@echo "$(BLUE)Cleaning temporary files.$(NC)"
	@find . -type f -name "*.tfplan" -delete
	@find . -type f -name "crash.log" -delete
	@echo "$(GREEN) Cleanup complete$(NC)"

status: ## Show cluster and deployment status
	@echo "$(BLUE)Cluster Status:$(NC)"
	@kubectl get nodes
	@echo ""
	@echo "$(BLUE)Deployments:$(NC)"
	@kubectl get deployments --all-namespaces
	@echo ""
	@echo "$(BLUE)Services:$(NC)"
	@kubectl get services --all-namespaces

cost-estimate: ## Estimate infrastructure costs (requires infracost)
	@echo "$(BLUE)Estimating costs.$(NC)"
	@command -v infracost >/dev/null 2>&1 || { echo "$(RED)ERROR: infracost not installed$(NC)"; exit 1; }
	@cd $(TF_DIR) && infracost breakdown --path .

##@ Development

dev-setup: check-tools bootstrap init ## Complete development setup (bootstrap + init)
	@echo "$(GREEN) Development environment ready$(NC)"
	@echo "$(BLUE)Next steps:$(NC)"
	@echo "  1. Configure terraform.tfvars in $(TF_DIR)/"
	@echo "  2. Run 'make plan' to preview infrastructure"
	@echo "  3. Run 'make apply' to create resources"

local-app: ## Run application locally
	@echo "$(BLUE)Starting application locally.$(NC)"
	@cd app && docker-compose up

test: ## Run tests
	@echo "$(BLUE)Running tests.$(NC)"
	@cd app && go test -v ./...

##@ Information

project-info: ## Display current project configuration
	@echo "$(BLUE)Project Configuration:$(NC)"
	@echo "  GCP Project:     $(PROJECT_ID)"
	@echo "  Region:          $(REGION)"
	@echo "  Cluster Name:    $(CLUSTER_NAME)"
	@echo "  Terraform Dir:   $(TF_DIR)"

phases: ## Display project phases
	@echo "$(BLUE)k8sAtlas Implementation phases:$(NC)"
	@echo ""
	@echo "$(GREEN)Phase 0:$(NC) Bootstrap & Foundation"
	@echo "  make bootstrap, make init"
	@echo ""
	@echo "$(GREEN)Phase 1:$(NC) Core Infrastructure (VPC, GKE, NAT, IAM)"
	@echo "  make plan, make apply, make kubeconfig"
	@echo ""
	@echo "$(GREEN)Phase 2:$(NC) Platform Services (Ingress, Cert-Manager, DNS)"
	@echo "  make install-platform, make test-ingress"
	@echo ""
	@echo "$(GREEN)Phase 3:$(NC) Application Development & Deployment"
	@echo "$(GREEN)Phase 4:$(NC) Observability (Prometheus, Grafana, Loki)"
	@echo "$(GREEN)Phase 5:$(NC) Security Hardening"
	@echo "$(GREEN)Phase 6:$(NC) CI/CD Pipeline"
	@echo ""
	@echo "See PROJECT_PLAN.md for complete details"
