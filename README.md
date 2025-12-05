# Excalidraw + Yjs on Kubernetes - Complete Documentation

**Status:** ✅ Production Ready | **Updated:** December 2025 | **Cluster:** k3s (3 nodes, GCP)

## 📖 Documentation Index

**START HERE** → Choose based on your need:

| Document | Purpose | Read Time |
|----------|---------|-----------|
| **[README_MONITORING.md](./README_MONITORING.md)** ⭐ | Navigation hub for all docs | 2 min |
| **[FRESH_SETUP.md](./FRESH_SETUP.md)** | Deploy from scratch + debugging fixes | 15 min |
| **[OBSERVABILITY.md](./OBSERVABILITY.md)** | Monitoring architecture & metrics | 10 min |
| **[TASK4_DEMO.md](./TASK4_DEMO.md)** | Live demo walkthrough (HPA, Yjs, monitoring) | 12 min |
| **[FINAL_ARCHITECTURE.md](./FINAL_ARCHITECTURE.md)** | Complete system design & verification | 10 min |

---

## 🚀 Quick Access

### Application
- **Main App:** http://34.49.56.133
- **Grafana:** http://34.49.56.133/grafana (admin/admin)

### Cluster Commands
```bash
# Via GCP IAP tunnel
gcloud compute ssh private-cloud-server-0 --zone=us-central1-a --tunnel-through-iap

# View pods
sudo kubectl get pods -n whiteboard
sudo kubectl get pods -n monitoring

# View system resources
sudo kubectl top nodes
sudo kubectl top pods -n whiteboard
```

---

## 📚 Documentation (Clean & Consolidated)

| Document | Purpose | Read Time |
|----------|---------|-----------|
| **[README_START_HERE.md](./README_START_HERE.md)** | Documentation index & quick reference | 3 min |
| **[FINAL_ARCHITECTURE.md](./FINAL_ARCHITECTURE.md)** | Complete system design & verification | 10 min |
| **[DEPLOYMENT_GUIDE.md](./DEPLOYMENT_GUIDE.md)** | Manifest reference & deployment procedures | 15 min |
| **[MONITORING_DASHBOARD.md](./MONITORING_DASHBOARD.md)** | Grafana/Prometheus setup & access | 8 min |
| **[VIDEO_DEMO_COMMANDS.md](./VIDEO_DEMO_COMMANDS.md)** | Task 4 demonstration commands | 20 min |
| **[TROUBLESHOOTING.md](./TROUBLESHOOTING.md)** | Common issues & solutions | Reference |

---

## ✅ Task Requirements Status

### Task 3: Multi-Instance Deployment
✅ **COMPLETE** - 7 containers (3 Excalidraw + 3 y-websocket + 1 Redis) across 2 worker nodes

**Verification:**
```bash
kubectl get pods -n whiteboard -o wide
# Shows pods distributed across private-cloud-worker-0 and private-cloud-worker-1
```

### Task 4 Gap 1: Monitoring & Observability
✅ **COMPLETE** - Prometheus metrics collection + Grafana visualization

**Access:** http://34.49.56.133:31519 (admin/admin)

**Verification:**
```bash
kubectl get pods -n monitoring
# Shows: prometheus-* and grafana-* both Running
```

### Task 4 Gap 2: Horizontal Scaling
✅ **COMPLETE** - HPA configured (Excalidraw 2-8, y-websocket 1-4 replicas)

**Verification:**
```bash
kubectl get hpa -n whiteboard  # Shows HPA configuration
kubectl get deployment -n whiteboard -o custom-columns=NAME:.metadata.name,DESIRED:.spec.replicas,READY:.status.readyReplicas
```

### Task 4 Gap 4: Resource Visibility
✅ **COMPLETE** - Metrics Server + kubectl top + Prometheus/Grafana

**Verification:**
```bash
kubectl top nodes        # Node CPU/memory
kubectl top pods -n whiteboard  # Pod CPU/memory
```

---

## 🏗️ Architecture Overview

```
┌─────────────────────────────────────┐
│  GCP HTTP Load Balancer (External)  │
│  34.49.56.133:80 → NGINX Ingress    │
└─────────────────────────────────────┘
                 ↓
┌─────────────────────────────────────┐
│  k3s Kubernetes Cluster (3 nodes)   │
│                                     │
│  whiteboard namespace:              │
│  • Excalidraw UI (3 replicas)       │
│  • y-websocket (3 replicas)         │
│  • Redis (1 replica)                │
│                                     │
│  monitoring namespace:              │
│  • Prometheus (metrics)             │
│  • Grafana (dashboards)             │
│                                     │
│  kube-system namespace:             │
│  • Metrics Server (resource API)    │
│  • CoreDNS, nginx-ingress           │
└─────────────────────────────────────┘
```

**Nodes:**
- `private-cloud-server-0` (4 CPU, 8 GB, Control Plane)
- `private-cloud-worker-0` (4 CPU, 8 GB, App pods)
- `private-cloud-worker-1` (4 CPU, 8 GB, App pods)

---

## 🔍 Key Metrics (Baseline)

| Component | CPU | Memory | Status |
|-----------|-----|--------|--------|
| Each Node | 1-2% | 7-11% | ✅ Low utilization |
| Excalidraw UI (per pod) | 2-3m | 18-21 Mi | ✅ Stable |
| y-websocket (per pod) | 1-2m | 12-14 Mi | ✅ Stable |
| Redis | 1m | 11 Mi | ✅ Stable |

---

## 📦 Kubernetes Manifests

All manifests in `k8s-manifests/` directory (32 total resources):

| File | Type | Count | Status |
|------|------|-------|--------|
| 00-namespace.yaml | Namespace | 1 | ✅ |
| 01-mongodb-secret.yaml | Secret | 1 | ✅ |
| 03-redis-statefulset.yaml | StatefulSet | 1 | ✅ |
| 05-yjs-deployment.yaml | Deployment + Service | 2 | ✅ |
| 06-excalidraw-deployment.yaml | Deployment + Service | 2 | ✅ |
| 07-network-policy.yaml | NetworkPolicy | 1 | ✅ |
| 08-ingress-tls.yaml | Ingress | 1 | ✅ |
| 09-excalidraw-nginx-config.yaml | ConfigMap | 1 | ✅ |
| 10-snapshot-cronjob.yaml | CronJob | 1 | ✅ |
| 11-nginx-ingress.yaml | Ingress | 1 | ✅ |
| 12-prometheus.yaml | Monitoring (6 resources) | 6 | ✅ |
| 13-grafana.yaml | Monitoring (3 resources) | 3 | ✅ |
| 14-hpa.yaml | HPA (2 autoscalers) | 2 | ✅ |
| 15-metrics-server.yaml | System (7 resources) | 7 | ✅ |

---

## 🎯 For Video Demonstration

**See:** [VIDEO_DEMO_COMMANDS.md](./VIDEO_DEMO_COMMANDS.md)

**Segments (14 min total):**
1. Architecture & Task Requirements (2 min)
2. Task 3 - Multi-Instance Verification (1 min)
3. Gap 1 - Monitoring Dashboard (3 min)
4. Gap 4 - Resource Visibility (2 min)
5. Gap 2 - Scaling Configuration (4 min)
6. Final System Health Check (1 min)

**Pre-Demo Checklist:**
```bash
# Run 5 minutes before recording
kubectl get pods -n whiteboard
kubectl get pods -n monitoring
kubectl get hpa -n whiteboard
kubectl top nodes
```

---

## 🛠️ Commands Reference

### System Status
```bash
kubectl get ns | grep -E 'whiteboard|monitoring'
kubectl get pods -A --no-headers | wc -l
kubectl get nodes -o wide
```

### Application
```bash
kubectl get deployment -n whiteboard -o custom-columns=NAME:.metadata.name,REPLICAS:.spec.replicas,READY:.status.readyReplicas
kubectl top pods -n whiteboard
```

### Monitoring
```bash
kubectl get pods -n monitoring
kubectl get svc -n monitoring
# Grafana: http://34.49.56.133:31519 (admin/admin)
```

### Scaling
```bash
kubectl get hpa -n whiteboard
kubectl describe hpa excalidraw-ui-hpa -n whiteboard
```

### Load Test
```bash
cd /path/to/scripts
python load-test.py  # Generates 5 concurrent users
# Watch scaling: kubectl get hpa -w
```

---

## 📖 Documentation Files

For **Deployment:** See [DEPLOYMENT_GUIDE.md](./DEPLOYMENT_GUIDE.md)  
For **Monitoring Setup:** See [MONITORING_DASHBOARD.md](./MONITORING_DASHBOARD.md)  
For **Architecture Details:** See [FINAL_ARCHITECTURE.md](./FINAL_ARCHITECTURE.md)  
For **Issues:** See [TROUBLESHOOTING.md](./TROUBLESHOOTING.md)

---

## 🌐 Access Points

| Service | URL | Credentials | Purpose |
|---------|-----|-------------|---------|
| Excalidraw App | http://34.49.56.133 | None | Main application |
| Grafana | http://34.49.56.133:31519 | admin/admin | Monitoring dashboard |
| Prometheus | See MONITORING_DASHBOARD.md | None | Metrics query |
| Kubernetes API | Via IAP tunnel | kubeconfig | Admin access |

---

## For Academic Evaluation

1. **System Design:** [FINAL_ARCHITECTURE.md](./FINAL_ARCHITECTURE.md) - Section "Architecture Overview"
2. **Task Verification:** [README_START_HERE.md](./README_START_HERE.md) - Section "Task Requirements Verification"
3. **Deployment:** [DEPLOYMENT_GUIDE.md](./DEPLOYMENT_GUIDE.md) - Full deployment process documented
4. **Monitoring:** [MONITORING_DASHBOARD.md](./MONITORING_DASHBOARD.md) - All metrics and observability
5. **Testing:** [VIDEO_DEMO_COMMANDS.md](./VIDEO_DEMO_COMMANDS.md) - Reproducible test commands

---

## Quick Problem Solving

**Pod not starting?**
```bash
kubectl describe pod <pod-name> -n whiteboard
kubectl logs <pod-name> -n whiteboard
```

**Metrics not showing?**
```bash
kubectl get pods -n kube-system -l k8s-app=metrics-server
kubectl logs -n kube-system -l k8s-app=metrics-server
```

**Grafana dashboard blank?**
```bash
kubectl port-forward -n monitoring svc/prometheus 9090:9090
# Check http://localhost:9090/graph for metrics
```

See [TROUBLESHOOTING.md](./TROUBLESHOOTING.md) for more solutions.

---

## 📋 System Status

- **Namespaces:** whiteboard, monitoring, kube-system ✅
- **Pods Running:** 13 (7 application + 2 monitoring + 4 system) ✅
- **Nodes:** 3 (all ready) ✅
- **Services:** 2 (Excalidraw UI + yjs websocket, Grafana dashboard) ✅
- **Monitoring:** Prometheus + Grafana ✅
- **Metrics:** kubectl top working ✅
- **Ingress:** NGINX ingress controller ✅

**System is fully operational and ready for production use.**
2. **START_HERE_PRODUCTION.md** — See what's deployed
3. **PRODUCTION_QUICK_START.md** — Test the live app

### For DevOps Setup (15 min read)
1. **ARCHITECTURE.md** — System design
2. **NGINX_BRANCH_DEPLOYMENT.md** — How to deploy
3. **TROUBLESHOOTING.md** — How to fix issues

### For Technical Review (20 min read)
1. **ARCHITECTURE.md** — Components
2. **FIXES_AND_MIGRATION.md** — All fixes from Traefik → NGINX (6 issues per phase)
3. **NGINX_BRANCH_DEPLOYMENT.md** — Deployment flow
4. **FIXES_APPLIED_SUMMARY.md** — Current GCS IAM fix details
5. **TROUBLESHOOTING.md** — How to maintain

---

## Quick Commands

### Check Deployment Status
```bash
gcloud compute ssh private-cloud-server-0 --zone=us-central1-a --tunnel-through-iap
sudo kubectl -n whiteboard get pods,svc -o wide
```

### View Application Logs
```bash
sudo kubectl -n whiteboard logs -l app=excalidraw-ui --tail=50
sudo kubectl -n whiteboard logs -l app=yjs-server --tail=50
```

### Verify Real-Time Sync
```bash
# Open 2 browser tabs:
# Tab 1: http://34.49.56.133/
# Tab 2: http://34.49.56.133/
# Draw on Tab 1 → See instant sync on Tab 2
```

### Check Snapshot Export
```bash
sudo kubectl -n whiteboard get cronjob,jobs
gsutil ls gs://helical-sled-477919-e9-whiteboard-snapshots/
```

---

## Architecture at a Glance

```
Public IP (34.49.56.133)
         ↓
GCP HTTP Load Balancer
         ↓
Private VPC (Cloud NAT, Firewall)
         ↓
NGINX Ingress (NodePort 31853)
         ↓
    ┌────┼────┐
    ↓    ↓    ↓
Excalidraw  yjs-ws  Redis
  (2x)     (1x)    (1x)
    ↓    ↓    ↓
    └────┼────┘
         ↓
   MongoDB Atlas ← Metadata
   GCS Bucket ← Snapshots
```

---

## Deployment Status

| Component | Status |
|-----------|--------|
| Excalidraw UI (2 replicas) | ✅ Running |
| y-websocket (1 replica) | ✅ Running |
| Redis (1 replica) | ✅ Running |
| NGINX Ingress Controller | ✅ Running |
| GCP Load Balancer | ✅ Healthy |
| MongoDB Atlas | ✅ Connected |
| GCS Snapshots | ✅ Operational |

**Overall:** PRODUCTION-READY ✅

---

## Branches

### nginx-migration (CURRENT)
- NGINX Ingress (no Helm)
- Fixed y-websocket binding (0.0.0.0)
- GCS IAM fixed (roles/storage.objectAdmin)
- All components operational
- **6 fixes applied during migration (see FIXES_AND_MIGRATION.md)**
- **Use this branch for new deployments**

### master (REFERENCE)
- Earlier iteration with Traefik
- Useful for understanding evolution
- Compare with nginx-migration to see improvements
- **6 issues fixed during initial Traefik setup (documented in FIXES_AND_MIGRATION.md)**
- **Do not use for new deployments**

---

## Support

**For deployment issues:** See NGINX_BRANCH_DEPLOYMENT.md → Troubleshooting section

**For general troubleshooting:** See TROUBLESHOOTING.md

**For architecture questions:** See ARCHITECTURE.md

---

**Ready for Submission:** ✅ YES

All manifests in `k8s-manifests/`, documentation complete, deployment operational.
