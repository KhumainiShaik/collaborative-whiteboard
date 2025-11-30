# Complete Execution Steps

## 1. Configure Terraform Variables

**File to update**: `terraform/terraform.tfvars`

```bash
# Copy the example file
cp terraform/terraform.tfvars.example terraform/terraform.tfvars

# Edit with your values
nano terraform/terraform.tfvars
```

**Update these values**:
```hcl
gcp_project_id         = "YOUR-GCP-PROJECT-ID"  # Your actual GCP project
gcp_region             = "us-central1"            # Or your preferred region
k3s_node_count         = 3                        # Keep as is for 1 server + 2 workers
k3s_server_machine_type = "e2-standard-2"         # Adjust if needed for your quota
k3s_worker_machine_type = "e2-standard-2"         # Adjust if needed for your quota
boot_disk_size_gb      = 50                       # Adjust for your needs (min 30)
enable_cloud_nat       = true                     # Keep enabled for private cluster
enable_monitoring      = true                     # Optional, disable to save costs
environment            = "private-cloud"          # Keep as is
tags                   = ["k3s", "whiteboard"]    # Optional identifiers
```

---

## 2. Update MongoDB Connection String

**File to update**: `k8s-manifests/01-mongodb-secret.yaml`

Replace the placeholder with your MongoDB Atlas URI:

```bash
nano k8s-manifests/01-mongodb-secret.yaml
```

**Current content**:
```yaml
stringData:
  MONGO_URI: "mongodb+srv://snapshot-aggregator:PASSWORD@whiteboard-cluster.mongodb.net/whiteboard?retryWrites=true&w=majority"
```

**Update to your connection string** (get from MongoDB Atlas):
```yaml
stringData:
  MONGO_URI: "mongodb+srv://YOUR_USERNAME:YOUR_PASSWORD@YOUR_CLUSTER.mongodb.net/whiteboard?retryWrites=true&w=majority"
```

**Where to find your MongoDB URI**:
1. Go to MongoDB Atlas Dashboard
2. Click "Database" → Select your cluster
3. Click "Connect" button
4. Choose "Connect your application"
5. Select "Python 3.6 or later" driver
6. Copy the connection string
7. Replace `<password>` with your actual password
8. Replace `<cluster-name>` with your cluster name

---

## 3. (Optional) Update Redis Password

**File to update**: `k8s-manifests/03-redis-statefulset.yaml`

The default password is `redis-whiteboard-demo-password`. Change for production:

```bash
nano k8s-manifests/03-redis-statefulset.yaml
```

**Find this section** (around line 10):
```yaml
stringData:
  REDIS_PASSWORD: "redis-whiteboard-demo-password"  # Change this in production!
```

**Update to a strong password**:
```yaml
stringData:
  REDIS_PASSWORD: "your-strong-redis-password-here"
```

**Generate a strong password**:
```bash
openssl rand -base64 32
```

---

## 4. Authenticate with GCP

```bash
gcloud auth login
gcloud config set project YOUR-GCP-PROJECT-ID
```

---

## 5. Deploy Infrastructure (Terraform)

```bash
cd terraform/
terraform init
terraform plan
terraform apply -auto-approve
```

**Save the outputs** (you'll need these):
```bash
terraform output -json > ../terraform-outputs.json
```

**Wait 5-10 minutes** for k3s cluster to bootstrap.

---

## 6. Configure kubectl Access

```bash
# Get values from Terraform outputs
export ZONE=$(terraform output -raw zone)
export SERVER_NAME=$(terraform output -raw k3s_server_name)

# Get kubeconfig via IAP tunnel
gcloud compute ssh $SERVER_NAME \
  --zone=$ZONE \
  --tunnel-through-iap \
  --command "cat /root/.kube/config" > ~/.kube/config

chmod 600 ~/.kube/config

# Verify connection
kubectl get nodes
```

---

## 7. Deploy Kubernetes Resources

```bash
cd ../k8s-manifests/

# Create namespace
kubectl apply -f 00-namespace.yaml

# Deploy all manifests in order
kubectl apply -f 01-mongodb-secret.yaml
kubectl apply -f 03-redis-statefulset.yaml
kubectl apply -f 05-yjs-deployment.yaml
kubectl apply -f 06-excalidraw-deployment.yaml
kubectl apply -f 07-network-policy.yaml
kubectl apply -f 08-ingress-tls.yaml
kubectl apply -f 10-snapshot-cronjob.yaml
```

---

## 8. Verify Deployment

```bash
# Check all pods running (wait 2-3 minutes)
kubectl get pods -n whiteboard

# Check services
kubectl get svc -n whiteboard

# Check ingress and get URL
kubectl get ingress -n whiteboard

# View logs to verify no errors
kubectl logs -n whiteboard -l app=yjs-server --tail=50
kubectl logs -n whiteboard -l app=excalidraw-ui --tail=50
```

Expected output:
- 2x `yjs-server` pods (Running)
- 2x `excalidraw-ui` pods (Running)
- 1x `redis` pod (Running)
- Ingress with external IP/hostname

---

## 9. Access Your Application

Get the external IP:
```bash
kubectl get ingress -n whiteboard -o wide
```

**Open in browser**: `http://<EXTERNAL-IP>`

Or save as variable:
```bash
export APP_URL=$(kubectl get ingress -n whiteboard \
  -o jsonpath='{.items[0].status.loadBalancer.ingress[0].ip}')
echo "Access application at: http://$APP_URL"
```

---

## Summary of File Changes

| File | What to Change | Example |
|------|---|---|
| `terraform/terraform.tfvars` | GCP project ID, region | `gcp_project_id = "my-project-123"` |
| `k8s-manifests/01-mongodb-secret.yaml` | MongoDB Atlas URI | `mongodb+srv://user:pass@cluster.mongodb.net/db` |
| `k8s-manifests/03-redis-statefulset.yaml` | Redis password (optional) | `REDIS_PASSWORD: "strong-password"` |

---

## Quick Command Reference

```bash
# Full setup from scratch
gcloud auth login
gcloud config set project YOUR-PROJECT-ID
cd terraform && terraform init && terraform apply -auto-approve
export ZONE=$(terraform output -raw zone)
export SERVER_NAME=$(terraform output -raw k3s_server_name)
gcloud compute ssh $SERVER_NAME --zone=$ZONE --tunnel-through-iap --command "cat /root/.kube/config" > ~/.kube/config
kubectl apply -f ../k8s-manifests/
kubectl get pods -n whiteboard
```

---

## Cleanup

```bash
# Delete Kubernetes resources
kubectl delete namespace whiteboard

# Destroy infrastructure
cd terraform/
terraform destroy -auto-approve
```

---

**Total setup time**: ~20-30 minutes
