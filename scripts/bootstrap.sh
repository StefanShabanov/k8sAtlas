#!/usr/bin/env bash
#
# k8sAtlas GCP Bootstrap Script
#
# This script sets up the initial GCP environment for the k8sAtlas project:
# - Enables required APIs
# - Creates GCS bucket for Terraform state
# - Sets up billing alerts
# - Creates service accounts for Terraform
#
# Usage: ./scripts/bootstrap.sh
#

set -e  # Exit on error
set -u  # Exit on undefined variable

# Colors
BLUE='\033[0;34m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Configuration
PROJECT_NAME="k8satlas"  # Project branding/naming prefix. THIS IS NOT THE NAME OF THE GCP PROJECT!
PROJECT_ID=$(gcloud config get-value project)  # GCP project ID
REGION=${REGION:-europe-west4}

# Resource naming (using PROJECT_NAME for consistency)
TF_STATE_BUCKET="${PROJECT_NAME}-tfstate"
TF_SA_NAME="${PROJECT_NAME}-terraform"
TF_SA_DISPLAY_NAME="k8sAtlas Terraform Service Account"
TF_SA_EMAIL="${TF_SA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"

# Billing alert thresholds (in USD)
BILLING_ALERT_50=50
BILLING_ALERT_100=100
BILLING_ALERT_150=150

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}k8sAtlas GCP Bootstrap${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""
echo -e "${GREEN}Project ID:${NC} $PROJECT_ID"
echo -e "${GREEN}Region:${NC}     $REGION"
echo ""

# Confirm project
echo -e "${YELLOW} This script will modify your GCP project: ${PROJECT_ID}${NC}"
read -p "Continue? (y/n): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo -e "${RED}Aborted.${NC}"
    exit 1
fi

echo ""
echo -e "${BLUE}Step 1/5: Enabling required GCP APIs.${NC}"

# List of required APIs
APIS=(
    "compute.googleapis.com"              # Compute Engine (for VMs, networking)
    "container.googleapis.com"            # Google Kubernetes Engine
    "servicenetworking.googleapis.com"    # Service Networking (for VPC peering)
    "cloudresourcemanager.googleapis.com" # Cloud Resource Manager
    "iam.googleapis.com"                  # Identity and Access Management
    "storage-api.googleapis.com"          # Cloud Storage
    "storage-component.googleapis.com"    # Cloud Storage components
    "dns.googleapis.com"                  # Cloud DNS
    "artifactregistry.googleapis.com"     # Artifact Registry
    "secretmanager.googleapis.com"        # Secret Manager
    "logging.googleapis.com"              # Cloud Logging
    "monitoring.googleapis.com"           # Cloud Monitoring
    "cloudkms.googleapis.com"             # Cloud KMS (for encryption)
    "sqladmin.googleapis.com"             # Cloud SQL Admin (optional, for Phase 7)
    "servicenetworking.googleapis.com"    # Service Networking (for Cloud SQL)
)

for api in "${APIS[@]}"; do
    echo -e "  Enabling ${api}."
    gcloud services enable "$api" --project="$PROJECT_ID" 2>/dev/null || true
done

echo -e "${GREEN}APIs enabled${NC}"
echo ""

echo -e "${BLUE}Step 2/5: Creating GCS bucket for Terraform state.${NC}"

# Check if bucket exists
if gsutil ls -b "gs://${TF_STATE_BUCKET}" 2>/dev/null; then
    echo -e "${YELLOW}  Bucket gs://${TF_STATE_BUCKET} already exists${NC}"
else
    echo -e "  Creating bucket: gs://${TF_STATE_BUCKET}"

    # Create bucket with versioning and uniform bucket-level access
    gsutil mb \
        -p "$PROJECT_ID" \
        -c STANDARD \
        -l "$REGION" \
        -b on \
        "gs://${TF_STATE_BUCKET}"

    # Enable versioning (for state file recovery)
    gsutil versioning set on "gs://${TF_STATE_BUCKET}"

    # Set lifecycle policy to keep only recent versions
    cat > /tmp/lifecycle.json <<EOF
{
  "lifecycle": {
    "rule": [
      {
        "action": {"type": "Delete"},
        "condition": {
          "numNewerVersions": 5
        }
      }
    ]
  }
}
EOF
    gsutil lifecycle set /tmp/lifecycle.json "gs://${TF_STATE_BUCKET}"
    rm /tmp/lifecycle.json

    echo -e "${GREEN}Bucket created: gs://${TF_STATE_BUCKET}${NC}"
fi

echo ""

echo -e "${BLUE}Step 3/5: Creating Terraform service account.${NC}"

# Check if service account exists
if gcloud iam service-accounts describe "${TF_SA_EMAIL}" --project="$PROJECT_ID" >/dev/null 2>&1; then
    echo -e "${YELLOW}  Service account ${TF_SA_EMAIL} already exists${NC}"
else
    echo -e "  Creating service account: ${TF_SA_NAME}"

    gcloud iam service-accounts create "$TF_SA_NAME" \
        --display-name="$TF_SA_DISPLAY_NAME" \
        --project="$PROJECT_ID"

    echo -e "${GREEN}Service account created${NC}"
fi

# Grant necessary roles to the service account
echo -e "  Granting IAM roles."

ROLES=(
    "roles/editor"                      # Broad permissions for managing resources
    "roles/iam.serviceAccountUser"      # Required for creating resources with service accounts
    "roles/iam.serviceAccountAdmin"     # Required for managing service accounts
    "roles/storage.admin"               # Full access to Cloud Storage
    "roles/compute.networkAdmin"        # Network administration
    "roles/container.admin"             # GKE administration
)

for role in "${ROLES[@]}"; do
    gcloud projects add-iam-policy-binding "$PROJECT_ID" \
        --member="serviceAccount:${TF_SA_EMAIL}" \
        --role="$role" \
        --condition=None \
        --quiet >/dev/null 2>&1 || true
done

echo -e "${GREEN} IAM roles granted${NC}"
echo ""

echo -e "${BLUE}Step 4/5: Setting up billing alerts.${NC}"

# Note: Budget alerts require manual setup in GCP Console
# Skipping automated check as it can hang on some configurations
echo -e "${YELLOW}   Budget alerts should be configured manually in GCP Console:${NC}"
echo -e "${YELLOW}    https://console.cloud.google.com/billing${NC}"
echo -e "${YELLOW}    Recommended thresholds: \$${BILLING_ALERT_50}, \$${BILLING_ALERT_100}, \$${BILLING_ALERT_150}${NC}"

echo ""

echo -e "${BLUE}Step 5/5: Creating Terraform backend configuration.${NC}"

# Create backend.tf file
mkdir -p terraform/environments/dev

cat > terraform/environments/dev/backend.tf <<EOF
# Terraform Backend Configuration
#
# This configures Terraform to store state in Google Cloud Storage.
# The state file is versioned and encrypted at rest.
#
# Generated by: scripts/bootstrap.sh
# Bucket: gs://${TF_STATE_BUCKET}

terraform {
  backend "gcs" {
    bucket = "${TF_STATE_BUCKET}"
    prefix = "terraform/state/dev"
  }
}
EOF

echo -e "${GREEN}Backend configuration created: terraform/environments/dev/backend.tf${NC}"

# Also create for prod environment
mkdir -p terraform/environments/prod

cat > terraform/environments/prod/backend.tf <<EOF
# Terraform Backend Configuration
#
# This configures Terraform to store state in Google Cloud Storage.
# The state file is versioned and encrypted at rest.
#
# Generated by: scripts/bootstrap.sh
# Bucket: gs://${TF_STATE_BUCKET}

terraform {
  backend "gcs" {
    bucket = "${TF_STATE_BUCKET}"
    prefix = "terraform/state/prod"
  }
}
EOF

echo -e "${GREEN}Backend configuration created: terraform/environments/prod/backend.tf${NC}"

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Bootstrap Complete! ${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo -e "${BLUE}Summary:${NC}"
echo -e "   GCP APIs enabled"
echo -e "   Terraform state bucket: gs://${TF_STATE_BUCKET}"
echo -e "   Service account: ${TF_SA_EMAIL}"
echo -e "   Terraform backend configuration created"
echo ""
echo -e "${BLUE}Next Steps:${NC}"
echo -e "  1. Review the backend configuration:"
echo -e "     ${YELLOW}cat terraform/environments/dev/backend.tf${NC}"
echo -e ""
echo -e "  2. Initialize Terraform:"
echo -e "     ${YELLOW}make init${NC}"
echo -e ""
echo -e "  3. Create terraform.tfvars:"
echo -e "     ${YELLOW}terraform/environments/dev/terraform.tfvars${NC}"
echo -e ""
echo -e "  4. Start building infrastructure (Phase 1):"
echo -e "     ${YELLOW}See PROJECT_PLAN.md for details${NC}"
echo ""
echo -e "${YELLOW} Important:${NC}"
echo -e "  - Set up billing alerts manually: https://console.cloud.google.com/billing"
echo -e "  - Keep your service account key secure (never commit to Git)"
echo -e "  - Review GCP quotas: https://console.cloud.google.com/iam-admin/quotas"
echo ""
