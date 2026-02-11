# k8sAtlas - System Requirements

This document lists all prerequisites and system requirements needed to deploy and manage the k8sAtlas GKE platform.

## Required Tools

### 1. Google Cloud SDK (gcloud CLI)

**Version:** Latest stable release (≥ 550.0.0)

**Installation:**

<details>
<summary>Linux / WSL2</summary>

```bash
# download and install
curl -O https://dl.google.com/dl/cloudsdk/channels/rapid/downloads/google-cloud-cli-linux-x86_64.tar.gz
tar -xf google-cloud-cli-linux-x86_64.tar.gz
./google-cloud-sdk/install.sh

# initialize
gcloud init
```
</details>

<details>
<summary>macOS</summary>

```bash
# using Homebrew
brew install --cask google-cloud-sdk

# or download from Google Cloud
# https://cloud.google.com/sdk/docs/install#mac
```
</details>

<details>
<summary>Windows</summary>

Download and run the installer:
https://cloud.google.com/sdk/docs/install#windows
</details>

**Verify:**
```bash
gcloud version
```

**Authentication:**
```bash
# authenticate with your Google account
gcloud auth login

# set up application default credentials (required for Terraform)
gcloud auth application-default login

# set your GCP project
gcloud config set project YOUR_PROJECT_ID
```

---

### 2. Terraform

**Version:** ≥ 1.5.0 (tested with 1.14.4)

**Installation:**

<details>
<summary>Linux / WSL2</summary>

```bash
# using package manager (Ubuntu/Debian)
wget -O- https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list
sudo apt update && sudo apt install terraform

# or using tfenv (version manager)
git clone https://github.com/tfutils/tfenv.git ~/.tfenv
echo 'export PATH="$HOME/.tfenv/bin:$PATH"' >> ~/.bashrc
tfenv install 1.14.4
tfenv use 1.14.4
```
</details>

<details>
<summary>macOS</summary>

```bash
# using Homebrew
brew tap hashicorp/tap
brew install hashicorp/tap/terraform

# verify
terraform version
```
</details>

<details>
<summary>Windows</summary>

```powershell
# using Chocolatey
choco install terraform

# or download from HashiCorp
# https://www.terraform.io/downloads
```
</details>

**Verify:**
```bash
terraform version
# should show: Terraform v1.5.0 or higher
```

---

### 3. kubectl

**Version:** ≥ 1.33.0 (must be within ±1 minor version of cluster)

**Installation:**

<details>
<summary>Linux / WSL2</summary>

```bash
# via gcloud (recommended)
gcloud components install kubectl

# or via package manager
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
```
</details>

<details>
<summary>macOS</summary>

```bash
# using Homebrew
brew install kubectl

# verify
kubectl version --client
```
</details>

<details>
<summary>Windows</summary>

```powershell
# using Chocolatey
choco install kubernetes-cli

# or via gcloud
gcloud components install kubectl
```
</details>

**Verify:**
```bash
kubectl version --client
```

---

### 4. GKE Auth Plugin

**Required for:** GKE cluster authentication (kubectl access)

**Installation:**

```bash
# all platforms (via gcloud)
gcloud components install gke-gcloud-auth-plugin

# verify
gke-gcloud-auth-plugin --version
```

---

### 5. Helm (optional, but recommended)

**Version:** ≥ 3.12.0

**Installation:**

<details>
<summary>Linux / WSL2</summary>

```bash
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
```
</details>

<details>
<summary>macOS</summary>

```bash
brew install helm
```
</details>

<details>
<summary>Windows</summary>

```powershell
choco install kubernetes-helm
```
</details>

**Verify:**
```bash
helm version
```

---

### 6. Git

**Version:** Any recent version (≥ 2.30)

**Installation:**
- Linux: `sudo apt-get install git` or `sudo yum install git`
- macOS: `brew install git` or included with Xcode
- Windows: Download from https://git-scm.com/download/win

**Verify:**
```bash
git --version
```

---

### 7. Make (optional, for convenience)

**Version:** Any recent version

**Purpose:** Run automation targets defined in `Makefile`

**Installation:**

<details>
<summary>Linux / WSL2</summary>

```bash
# Ubuntu/Debian
sudo apt-get update
sudo apt-get install -y build-essential

# verify
make --version
```
</details>

<details>
<summary>macOS</summary>

```bash
# usually included with Xcode Command Line Tools
xcode-select --install

# or via Homebrew
brew install make

# verify
make --version
```
</details>

<details>
<summary>Windows</summary>

```powershell
# using Chocolatey
choco install make

# or use WSL2 (recommended)
```
</details>

**Verify:**
```bash
make --version
# should show: GNU Make 4.x or higher
```

**Note:** While optional, Make significantly simplifies running common commands. All `make` commands can be run manually if preferred.

---

## GCP Prerequisites

### 1. Google Cloud Project

- **Active GCP project** with billing enabled
- **Project ID** (e.g., `my-project-id`)
- **Sufficient permissions** (see below)

Create a project:
```bash
gcloud projects create YOUR_PROJECT_ID --name="k8sAtlas"
gcloud config set project YOUR_PROJECT_ID
```

Enable billing:
```bash
# link billing account (find ID in GCP Console)
gcloud billing projects link YOUR_PROJECT_ID --billing-account=BILLING_ACCOUNT_ID
```

### 2. Required GCP APIs

The bootstrap script (`scripts/bootstrap.sh`) will enable these automatically:

- `compute.googleapis.com` - Compute Engine
- `container.googleapis.com` - Kubernetes Engine
- `servicenetworking.googleapis.com` - Service Networking
- `cloudresourcemanager.googleapis.com` - Resource Manager
- `iam.googleapis.com` - Identity and Access Management
- `cloudapis.googleapis.com` - Cloud APIs
- `dns.googleapis.com` - Cloud DNS
- `logging.googleapis.com` - Cloud Logging
- `monitoring.googleapis.com` - Cloud Monitoring

Or enable manually:
```bash
gcloud services enable compute.googleapis.com container.googleapis.com
```

### 3. IAM Permissions

Your user account needs these roles:

- **Editor** or **Owner** (for initial setup)
- **Terraform Service Account** (created by bootstrap script):
  - `roles/editor`
  - `roles/iam.serviceAccountAdmin`
  - `roles/resourcemanager.projectIamAdmin`
  - `roles/storage.admin`

Check your permissions:
```bash
gcloud projects get-iam-policy YOUR_PROJECT_ID \
  --flatten="bindings[].members" \
  --format="table(bindings.role)" \
  --filter="bindings.members:user:$(gcloud config get-value account)"
```

### 4. Resource quotas

Ensure your project has sufficient quotas for:

- **CPUs:** Minimum 8 vCPUs (for dev environment)
- **IP addresses:** Minimum 3 static IPs
- **Networks:** Minimum 1 VPC network
- **GKE clusters:** Minimum 1

Check quotas:
```bash
gcloud compute project-info describe --project=YOUR_PROJECT_ID
```

Request quota increases if needed:
https://console.cloud.google.com/iam-admin/quotas

---

## Cost considerations

### Development environment (Current demo configuration)

**Monthly estimate:** ~$128 USD

- **GKE cluster management:** ~$73/month (one zonal cluster)
- **Compute (6 nodes):**
  - System pool: 3x e2-small (2 vCPU, 2GB RAM) = ~$30/month
  - Workload pool: 3x e2-small Spot VMs = ~$6/month (80% discount)
- **Network egress:** ~$10-20/month (varies by usage)
- **Cloud NAT:** ~$5/month

**Cost optimization tips:**
- Use Spot VMs for non-critical workloads (enabled)
- Delete cluster when not in use: `make destroy`
- Monitor costs: https://console.cloud.google.com/billing

### Free Tier

Google Cloud offers a **$300 free trial** for 90 days for new accounts:
https://cloud.google.com/free

---

## Development environment recommendations

### Operating System

- **Linux** (Ubuntu 22.04+ recommended)
- **macOS** (12.0+)
- **Windows** with **WSL2** (Ubuntu 22.04)

**Note:** This project is primarily tested on Linux/WSL2. Windows native support is limited.

### Network Requirements

- Unrestricted access to:
  - `googleapis.com` (GCP APIs)
  - `gcr.io` (Google Container Registry)
  - `registry.terraform.io` (Terraform Registry)
  - `github.com` (for modules and updates)

## Next steps

Once all requirements are met:

1. **Clone the repository:**
   ```bash
   git clone <repository-url>
   cd k8sAtlas
   ```

2. **Run bootstrap:**
   ```bash
   make bootstrap
   ```

3. **Initialize Terraform:**
   ```bash
   make init
   ```

4. **Configure your environment:**
   ```bash
   cd terraform/environments/dev
   # create terraform.tfvars with your project_id
   ```

5. **Deploy infrastructure:**
   ```bash
   make plan
   make apply
   ```

6. **Connect to cluster:**
   ```bash
   make kubeconfig
   kubectl get nodes
   ```


## Support

- **GCP Documentation:** https://cloud.google.com/docs
- **Terraform GCP Provider:** https://registry.terraform.io/providers/hashicorp/google/latest/docs
- **GKE Documentation:** https://cloud.google.com/kubernetes-engine/docs
