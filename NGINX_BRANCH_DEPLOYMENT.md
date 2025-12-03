# nginx-migration Branch: Deployment Guide

**Branch:** `nginx-migration`  
**Architecture:** NGINX Ingress (no-Helm), GCP HTTP LB, private k3s cluster  
**Status:** PRODUCTION-READY ✅

---

## What Changed (v1.4.5 → v1.4.6)

| Change | Old | New | Impact |
|--------|-----|-----|--------|
| **Ingress Controller** | Traefik | NGINX | Major refactor |
| **y-websocket Binding** | localhost | 0.0.0.0 | Connectivity fix |
| **GCP LB Backend** | Traefik NodePort | NGINX NodePort (31853) | Config update |
| **GCS IAM** | Incomplete | roles/storage.objectAdmin | Snapshot fix |

---

## Deployment Files

### Key Manifests
- `k8s-manifests/11-nginx-ingress.yaml` — NGINX controller (SA, RBAC, Deployment, NodePort)
- `k8s-manifests/08-ingress-tls.yaml` — Ingress rules (/ and /ws routes, ingressClassName: nginx)
- `k8s-manifests/10-snapshot-cronjob.yaml` — CronJob (Python-based export, Workload Identity)
- `k8s-manifests/06-excalidraw-deployment.yaml` — Excalidraw UI (2 replicas)
- `k8s-manifests/05-yjs-deployment.yaml` — y-websocket (1 replica, 0.0.0.0 binding)

### Infrastructure Files
- `k8s-manifests/03-kcc-gcs.yaml` — GCS bucket config
- `k8s-manifests/02-kcc-pubsub.yaml` — GCP Pub/Sub (if used)
- `k8s-manifests/04-k8s-serviceaccount.yaml` — Workload Identity SA

---

## Quick Deployment (Fresh Cluster)

### 1. SSH to Server
```bash
gcloud compute ssh private-cloud-server-0 --zone=us-central1-a --tunnel-through-iap
```

### 2. Apply All Manifests (In Order)
```bash
cd /path/to/k8s-manifests

# Namespace & secrets
sudo kubectl apply -f 00-namespace.yaml
sudo kubectl apply -f 01-mongodb-secret.yaml

# External services
sudo kubectl apply -f 02-kcc-pubsub.yaml
sudo kubectl apply -f 03-kcc-gcs.yaml

# Workload Identity & RBAC
sudo kubectl apply -f 04-k8s-serviceaccount.yaml

# Application stack
sudo kubectl apply -f 05-yjs-deployment.yaml
sudo kubectl apply -f 06-excalidraw-deployment.yaml

# State (Redis)
# Apply Redis manifests (if separate file, e.g., 09-redis-statefulset.yaml)

# Network policies (optional)
sudo kubectl apply -f 07-network-policy.yaml

# NGINX Ingress Controller
sudo kubectl apply -f 11-nginx-ingress.yaml

# Ingress rules
sudo kubectl apply -f 08-ingress-tls.yaml

# Snapshot CronJob
sudo kubectl apply -f 10-snapshot-cronjob.yaml
```

### 3. Verify Deployment
```bash
sudo kubectl -n whiteboard get pods,svc -o wide
# All pods should be Running/Ready ✅

sudo kubectl -n kube-system get pods -l app.kubernetes.io/name=ingress-nginx
# NGINX controller pod should be Running ✅
```

---

## Troubleshooting

### Issue: NGINX Ingress pod stuck in Pending
```bash
# Check resources
sudo kubectl -n kube-system describe pod <nginx-pod-name>
# Usually caused by resource limits; verify node capacity
sudo kubectl top nodes
```

**Fix:**
- Add more worker nodes or increase node resources
- Or reduce resource requests in nginx-ingress.yaml

### Issue: Ingress routes not working (404 errors)
```bash
# Verify ingress exists
sudo kubectl -n whiteboard get ingress

# Check ingress status
sudo kubectl -n whiteboard describe ingress excalidraw-ingress

# Check NGINX controller logs
sudo kubectl -n kube-system logs -l app.kubernetes.io/name=ingress-nginx --tail=50

# Verify backend services are accessible
sudo kubectl -n whiteboard get svc
sudo kubectl -n whiteboard get endpoints
```

**Fix:**
- Ensure service names match ingress rules exactly
- Verify services have active endpoints (ready pods)
- Check ingressClassName matches controller name (should be "nginx")

### Issue: Snapshot CronJob not running
```bash
# Check CronJob status
sudo kubectl -n whiteboard get cronjob snapshot-export -o yaml

# Check recent jobs
sudo kubectl -n whiteboard get jobs -l cronjob-name=snapshot-export

# View job logs
sudo kubectl -n whiteboard logs -l job-name=<job-name> --tail=50
```

**Fix:**
- Verify CronJob schedule is correct (format: `0 */4 * * *`)
- Check Workload Identity annotation on snapshot-sa
- Verify GCS IAM permissions: `gcloud projects get-iam-policy helical-sled-477919-e9 --flatten="bindings[].members" | grep snapshot-sa`

### Issue: GCS snapshots failing (403 error)
```bash
# Verify service account has permissions
gcloud projects get-iam-policy helical-sled-477919-e9 \
  --flatten="bindings[].members" \
  --filter="bindings.role:roles/storage.objectAdmin" \
  --format="table(bindings.members)"
```

**Fix:**
```bash
# Grant permission if missing
gcloud projects add-iam-policy-binding helical-sled-477919-e9 \
  --member="serviceAccount:snapshot-sa@helical-sled-477919-e9.iam.gserviceaccount.com" \
  --role="roles/storage.objectAdmin"
```

---

## Monitoring Commands

### Check Cluster Health
```bash
# All pods
sudo kubectl -n whiteboard get pods

# Services
sudo kubectl -n whiteboard get svc

# Ingress
sudo kubectl -n whiteboard get ingress -o wide

# Load Balancer health
gcloud compute backend-services get-health private-cloud-http-backend --global

# Nodes
sudo kubectl get nodes -o wide

# Top consumers
sudo kubectl top pods -n whiteboard
sudo kubectl top nodes
```

### View Logs
```bash
# NGINX controller
sudo kubectl -n kube-system logs -l app.kubernetes.io/name=ingress-nginx -f

# Excalidraw UI
sudo kubectl -n whiteboard logs -l app=excalidraw-ui -f

# y-websocket
sudo kubectl -n whiteboard logs -l app=yjs-server -f

# Redis
sudo kubectl -n whiteboard logs -l app=redis -f
```

---

## Scaling

### Increase Replicas
```bash
# Scale Excalidraw UI
sudo kubectl -n whiteboard scale deploy excalidraw-ui --replicas=5

# Scale y-websocket
sudo kubectl -n whiteboard scale deploy yjs-server --replicas=3

# (Redis stays at 1 replica — it's StatefulSet with local PVC)
```

### Decrease Replicas
```bash
sudo kubectl -n whiteboard scale deploy excalidraw-ui --replicas=1
sudo kubectl -n whiteboard scale deploy yjs-server --replicas=1
```

---

## Cleanup (Destroy Deployment)

### Remove All k8s Resources
```bash
# Delete namespace (cascades all resources)
sudo kubectl delete namespace whiteboard

# Verify namespace is gone
sudo kubectl get namespaces | grep whiteboard
```

### Destroy Infrastructure (GCP)
```bash
# Via Terraform (if used)
terraform destroy -auto-approve

# Or manual deletion:
gcloud compute backend-services delete private-cloud-http-backend --global
gcloud compute instance-groups unset-named-ports private-cloud-nodes-ig --named-ports=traefik-nodeport
gcloud compute instances delete private-cloud-server-0 private-cloud-worker-0 private-cloud-worker-1 --zone=us-central1-a
gcloud compute networks delete private-cloud-network
```

---

## Notes for Future Maintenance

- **NGINX Ingress:** Minimal, no Helm dependency. Manifests are self-contained.
- **CronJob:** Python-based script is more portable than shell. Monitor execution regularly.
- **Workload Identity:** Must be active in cluster. Verify with: `gcloud iam service-accounts get-iam-policy snapshot-sa@PROJECT.iam.gserviceaccount.com`
- **GCS Bucket:** Ensure bucket exists and Workload Identity SA has storage.* roles.
- **MongoDB Atlas:** Keep IP allowlist updated with Cloud NAT IP range.

---

**Last Updated:** 2025-12-03  
**Deployment Method:** kubectl apply  
**Estimated Setup Time:** 10 minutes  
**Status:** PRODUCTION-READY ✅
