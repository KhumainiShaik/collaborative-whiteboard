# Documentation Index

**Last Updated:** 2025-12-03  
**Branch:** nginx-migration (PRIMARY) | master (REFERENCE)

---

## Start Here

**Public Access:**
```bash
http://34.49.56.133/
```

**Admin SSH (IAP Tunnel):**
```bash
gcloud compute ssh private-cloud-server-0 --zone=us-central1-a --tunnel-through-iap
sudo kubectl -n whiteboard get pods
```

---

## Documentation Files

| File | Purpose | Audience |
|------|---------|----------|
| **ARCHITECTURE.md** | System design, components, data flow | Everyone |
| **FIXES_AND_MIGRATION.md** | All fixes from Traefik → NGINX migration | DevOps / Technical |
| **NGINX_BRANCH_DEPLOYMENT.md** | Deploy guide for nginx-migration branch | DevOps / SRE |
| **MASTER_BRANCH_REFERENCE.md** | How master (Traefik) differs from nginx-migration | DevOps / Reviewers |
| **TROUBLESHOOTING.md** | Fix common issues (both branches) | DevOps / Support |
| **START_HERE_PRODUCTION.md** | Quick overview and quick-start | Evaluators |
| **PRODUCTION_QUICK_START.md** | How to test real-time sync | Students / Evaluators |
| **FIXES_APPLIED_SUMMARY.md** | What was fixed (GCS IAM, CronJob) | Technical Reviewers |
| **VERSION_AND_ARCHITECTURE_DRIFT.md** | v1.4.5 → v1.4.6 changes in detail | Auditors |

---

## Recommended Reading Order

### For Academic Evaluation (5 min read)
1. **ARCHITECTURE.md** — Understand the design
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
