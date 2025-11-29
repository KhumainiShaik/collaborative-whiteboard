## Architecture Summary

**Flow**: Public HTTP Load Balancer → NGINX Ingress → k3s cluster (no public node IPs)

**Inside cluster**:
- Excalidraw UI (HTTP 3000)
- y-websocket (WSS over HTTP, port 1234)
- Redis StatefulSet (pub/sub, port 6379, PVCs)

**External state**:
- MongoDB Atlas (managed DB, external connection)
- GCS bucket (snapshot export via CronJob, Workload Identity)

**Network**:
- Private VPC (10.10.0.0/16), private subnet (10.10.1.0/24)
- Cloud NAT for egress (Docker pulls, updates)
- IAP for admin SSH (no public SSH)
- HTTP LB public IP → Ingress (port 80)

---

## Deployment Steps

### 1. Terraform Apply
```bash
cd terraform/
terraform init
terraform plan
terraform apply
# Wait 5-10 min for k3s cluster to bootstrap
```

**Outputs**: `http_url`, `iap_ssh_command`, `gcs_bucket`, `snapshot_sa_email`

### 2. Get Kubeconfig (via IAP)
```bash
export ZONE=<terraform-output-zone>
export SERVER_NAME=<terraform-output-k3s-server-name>
gcloud compute ssh $SERVER_NAME --zone=$ZONE --tunnel-through-iap \
  --command "cat /root/.kube/config" > ~/.kube/config
```

### 3. Deploy Kubernetes Manifests
```bash
kubectl apply -f k8s-manifests/
```

**Order** (applied automatically):
1. `00-namespace.yaml` (whiteboard NS)
2. `01-mongodb-secret.yaml` (Atlas URI)
3. `03-redis-statefulset.yaml` (Redis pub/sub)
4. `04-mongodb-statefulset.yaml` (local Mongo if needed; else skip)
5. `05-yjs-deployment.yaml` (y-websocket, 2→10 replicas)
6. `06-excalidraw-deployment.yaml` (UI)
7. `07-network-policy.yaml` (zero-trust rules)
8. `08-ingress-tls.yaml` (HTTP routing)
9. `10-snapshot-cronjob.yaml` (CronJob → GCS)

### 4. Verify
```bash
kubectl get pods -n whiteboard
kubectl get svc -n whiteboard
kubectl get ingress -n whiteboard
```

### 5. Access
```bash
echo "Public IP:" $(terraform output http_load_balancer_ip)
# Open http://<PUBLIC_IP>/
```

---

## Components

| Component | Type | Config |
|-----------|------|--------|
| **VPC** | Private | 10.10.0.0/16, no public IPs on nodes |
| **Cloud NAT** | Egress | AUTO_ONLY external IPs, logged |
| **HTTP LB** | Public | Port 80 → Ingress (backend: all nodes) |
| **k3s server** | VM | Private, IAP only, no external IP |
| **k3s workers** | VM ×2 | Private, no external IPs |
| **NGINX Ingress** | K8s | Routes / → Excalidraw (3000), /ws → y-websocket (1234) |
| **Redis** | StatefulSet | 10GB PVC, port 6379 (internal) |
| **MongoDB** | Atlas (external) | Managed, M0 tier, IP whitelist to NAT |
| **GCS** | Bucket | Snapshots exported by CronJob (Workload Identity) |
| **CronJob** | K8s | Every 4h, mongodump → GCS, uses Workload Identity |
| **Firewall** | GCP | SSH (IAP only), K3s (internal), HTTP (public), metadata, DNS, NTP |

---

## Key Features

✓ **Private cloud** - No public node IPs, all access via IAP or LB  
✓ **HA ready** - Stateless apps (Excalidraw, y-websocket), HPA configured  
✓ **Durable** - MongoDB Atlas (CP), Redis (AP), GCS snapshots  
✓ **Observable** - Workload Identity for GCS, no service account keys  
✓ **Scalable** - y-websocket 2→10 replicas, Redis StatefulSet ready for 3+ replicas

---

## File Structure

```
terraform/
├── k3s-compute.tf          # k3s VMs, service accounts, IAP
├── network.tf              # VPC, subnet, 9 firewall rules (SSH/K3s/DNS/NTP)
├── load-balancer.tf        # Public HTTP LB → Ingress
├── gcs.tf                  # GCS bucket, snapshot SA, Workload Identity
├── mongodb.tf              # MongoDB Atlas cluster
├── provider.tf, variables.tf, outputs.tf, terraform.tfvars.example
└── scripts/
    ├── k3s-server-init.sh  # Control plane bootstrap
    └── k3s-worker-init.sh  # Worker bootstrap

k8s-manifests/
├── 00-namespace.yaml       # whiteboard NS
├── 01-mongodb-secret.yaml  # Atlas URI secret
├── 03-redis-statefulset.yaml
├── 04-mongodb-statefulset.yaml
├── 05-yjs-deployment.yaml  # y-websocket (2-10 replicas, HPA)
├── 06-excalidraw-deployment.yaml
├── 07-network-policy.yaml  # 5 explicit rules (zero-trust)
├── 08-ingress-tls.yaml     # HTTP routing (no TLS for demo)
└── 10-snapshot-cronjob.yaml # CronJob → GCS with Workload Identity
```
