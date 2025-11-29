# Automated Setup: Using Scripts

## Prerequisites
- `gcloud` CLI installed and authenticated
- `kubectl` installed
- `terraform` installed
- Git cloned repo
- Bash shell available

## Quick Setup (Single Command)
```bash
# From repo root
./deploy.sh --auto
```

## Step-by-Step with Scripts

### Step 1: Deploy Infrastructure
```bash
./scripts/terraform-deploy.sh apply
```

Output file: `terraform-outputs.json`

### Step 2: Configure Kubeconfig
```bash
./scripts/setup-kubeconfig.sh
```

Verifies cluster access automatically.

### Step 3: Deploy Kubernetes (Automated Secrets)
```bash
# Option A: Interactive (prompts for credentials)
./scripts/deploy-k8s.sh interactive

# Option B: From environment variables
export MONGO_URI='mongodb+srv://user:pass@cluster.mongodb.net/db'
export REDIS_PASSWORD='your-redis-password-here'
./scripts/deploy-k8s.sh
```

### Step 4: Verify and Show Access URL
```bash
./scripts/verify-deployment.sh
```

Outputs: Pod status, service endpoints, and HTTP URL to access application.

## Script Details

### `terraform-deploy.sh`
- Initializes, plans, and applies Terraform
- Saves outputs to `terraform-outputs.json`
- Usage: `terraform-deploy.sh [apply|destroy|plan]`

### `setup-kubeconfig.sh`
- Extracts kubeconfig from k3s server via IAP
- Sets appropriate permissions
- Tests kubectl connectivity

### `deploy-k8s.sh`
- Creates namespace
- Manages secrets (MongoDB, Redis)
- Applies all manifests in correct order
- Modes: `interactive` or environment variable based

### `verify-deployment.sh`
- Checks pod readiness (waits up to 5 min)
- Shows service endpoints
- Displays application URL
- Provides logs if deployment fails

## Complete Automated Flow
```bash
# Single script that runs everything
./scripts/full-deploy.sh
```

This runs:
1. Terraform apply
2. Kubeconfig setup
3. K8s deployment with interactive credential prompts
4. Verification and status report

## Cleanup
```bash
./scripts/cleanup.sh
# Or manually:
./scripts/terraform-deploy.sh destroy
```

---

**Time to deploy**: ~15-20 minutes (automated with confirmation prompts)

## Available Scripts Reference

| Script | Purpose |
|--------|---------|
| `terraform-deploy.sh` | Infrastructure provisioning |
| `setup-kubeconfig.sh` | Configure kubectl |
| `deploy-k8s.sh` | Deploy Kubernetes resources |
| `verify-deployment.sh` | Check deployment status |
| `full-deploy.sh` | Complete end-to-end deployment |
| `cleanup.sh` | Remove all resources |
