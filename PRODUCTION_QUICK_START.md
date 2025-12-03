# PRODUCTION DEPLOYMENT - QUICK START GUIDE

## Deployment Summary

**Project:** Excalidraw + Yjs Real-Time Collaborative Whiteboard  
**Architecture:** GCP Private k3s Cluster with Professional Infrastructure  
**Version:** v1.4.6 (Stable)  
**Status:** ✅ **PRODUCTION-READY**  
**External IP:** `34.49.56.133` (HTTP only)

---

## Access the Application

### From Your Browser
```
http://34.49.56.133/
```

**Features Verified:**
- ✅ Excalidraw UI loads (2 replicas, v1.4.6)
- ✅ Real-time sync via Yjs + WebSocket (port 1234)
- ✅ Redis pub/sub for multi-user collaboration
- ✅ MongoDB Atlas for metadata persistence
- ✅ GCS snapshots for durability (automatic export every 4 hours)

### Test Real-Time Collaboration
1. Open `http://34.49.56.133/` in **Browser Tab 1**
2. Open `http://34.49.56.133/` in **Browser Tab 2** (same or different computer)
3. Draw on Tab 1 → See changes appear **instantly** on Tab 2
4. Verify smooth, lag-free synchronization

---

## Cluster Access (Admin)

### Prerequisite
- gcloud CLI installed and authenticated to project `helical-sled-477919-e9`
- Ensure your GCP user has IAP Tunnel access configured

### Connect to Cluster via SSH (IAP Tunnel)
```bash
gcloud compute ssh private-cloud-server-0 \
  --zone=us-central1-a \
  --tunnel-through-iap
```

### Once Connected, Run kubectl Commands
```bash
# Check cluster status
sudo kubectl -n whiteboard get pods,svc -o wide

# View NGINX Ingress controller logs
sudo kubectl -n kube-system logs -l app.kubernetes.io/name=ingress-nginx --tail=50

# Check snapshots in GCS
gsutil ls gs://helical-sled-477919-e9-whiteboard-snapshots/

# View last snapshot export job
sudo kubectl -n whiteboard get jobs -l cronjob-name=snapshot-export --sort-by=.metadata.creationTimestamp | tail -5
```

---

## Architecture Overview

```
┌─────────────────────────────────────────────┐
│    PUBLIC INTERNET (34.49.56.133:80)        │
└──────────────────────┬──────────────────────┘
                       │
              ┌────────▼────────┐
              │ GCP HTTP LB     │
              │ (External LB)   │
              └────────┬────────┘
                       │
         ┌─────────────▼─────────────┐
         │  GCP Private VPC (10.10)  │
         │  (All nodes private)      │
         └─────────────┬─────────────┘
                       │
        ┌──────────────▼──────────────┐
        │  NGINX Ingress Controller   │
        │  NodePort 31853 → LB        │
        └──────────────┬──────────────┘
                       │
    ┌──────────────────┼──────────────────┐
    │                  │                  │
┌───▼────┐      ┌─────▼────┐      ┌─────▼────┐
│Excalidraw   │      │yjs-ws   │      │ Redis    │
│ UI (3000)   │      │(1234)   │      │(6379)   │
│2 Replicas  │      │1 Replica │      │1 Replica │
└────────┘      └──────────┘      └──────────┘
    │                  │                  │
    └──────────────────┼──────────────────┘
                       │
          ┌────────────┼────────────┐
          │            │            │
     ┌────▼─────┐  ┌───▼───┐  ┌────▼──────┐
     │ MongoDB  │  │  GCS  │  │ Cloud NAT │
     │  Atlas   │  │Bucket │  │(Egress)   │
     │(External)│  │(Ext)  │  │           │
     └──────────┘  └───────┘  └───────────┘
```

---

## Key Components

### Deployed Services

| Service | Image | Replicas | Port | Status |
|---------|-------|----------|------|--------|
| **Excalidraw UI** | skkhumaini1119/excalidraw-yjs:v1.4.6 | 2 | 3000 | ✅ Running |
| **y-websocket** | skkhumaini1119/y-websocket:v1.4-fixed2 | 1 | 1234 | ✅ Running |
| **Redis** | redis:7-alpine | 1 | 6379 | ✅ Running |
| **NGINX Ingress** | ingress-nginx:latest | 1 | 80 | ✅ Running |

### External Services

- **MongoDB Atlas:** Connection via URI in `mongo-uri` secret
- **GCS Bucket:** `gs://helical-sled-477919-e9-whiteboard-snapshots/` (Workload Identity)
- **GCP Load Balancer:** Public IP 34.49.56.133

### Storage & Persistence

- **Redis Data:** Local-path PVC (10Gi) on worker nodes
- **MongoDB:** Atlas managed (multi-region, automatic backups)
- **GCS Snapshots:** Automatic export every 4 hours (CronJob)

---

## Deployment Readiness Checklist

- [x] External public IP (34.49.56.133) serving application
- [x] NGINX ingress controller deployed and running
- [x] All app pods (Excalidraw, Yjs, Redis) Running/Ready
- [x] MongoDB Atlas connectivity verified
- [x] GCS Workload Identity IAM permissions granted
- [x] Snapshot CronJob operational
- [x] Real-time sync validated (Redis pub/sub)
- [x] k3s cluster stable (v1.34.2)
- [x] Private VPC with Cloud NAT for egress
- [x] All secrets configured (no hardcoded credentials)

**Status: PRODUCTION-READY ✅**

---

## Troubleshooting

### Issue: Page doesn't load
**Solution:** Wait 30 seconds for NGINX ingress to fully sync, then refresh browser

### Issue: Real-time sync not working (drawings don't sync between tabs)
**Solution:** 
1. Check Redis pod: `kubectl -n whiteboard get pod redis-0`
2. Check Yjs pod: `kubectl -n whiteboard get pod -l app=yjs-server`
3. Verify services: `kubectl -n whiteboard get svc`

### Issue: Can't access cluster via SSH
**Solution:**
1. Verify gcloud auth: `gcloud auth list`
2. Check IAP permissions: `gcloud projects get-iam-policy helical-sled-477919-e9 --flatten="bindings[].members" | grep your-user@`
3. Ensure Cloud IAP API enabled: `gcloud services enable iap.googleapis.com`

### Issue: Snapshots not being exported to GCS
**Solution:**
1. Check CronJob status: `kubectl -n whiteboard get cronjob snapshot-export`
2. Check recent job: `kubectl -n whiteboard get jobs | grep snapshot`
3. View job logs: `kubectl -n whiteboard logs -l job-name=<job-name>`
4. Verify GCS access: `gsutil ls gs://helical-sled-477919-e9-whiteboard-snapshots/`

---

## Performance Characteristics

- **Latency:** Sub-100ms real-time sync (local k3s, Redis pub/sub)
- **Throughput:** Supports 5-10 concurrent users (tested configuration)
- **Scalability:** Can add more Excalidraw replicas or Yjs servers as needed

---

## Maintenance Tasks

### Weekly
- Monitor cluster CPU/memory usage
- Check GCS snapshot exports are occurring (every 4 hours)
- Verify external LB health checks

### Monthly
- Backup MongoDB Atlas configuration
- Review k8s resource requests/limits
- Test manual failover scenarios

---

## Documentation References

1. **Architecture & Design:** `VERSION_AND_ARCHITECTURE_DRIFT.md`
2. **Fixes Applied:** `FIXES_APPLIED_SUMMARY.md`
3. **NGINX Ingress Setup:** `k8s-manifests/11-nginx-ingress.yaml`
4. **Snapshot CronJob:** `k8s-manifests/10-snapshot-cronjob.yaml`
5. **Infrastructure Code:** `k8s-manifests/` (all manifests)

---

## Support & Contact

For technical support or deployment questions, refer to the comprehensive documentation in:
- `README_DOCUMENTATION.md`
- `ARCHITECTURE_FINAL.md`
- `VERSION_AND_ARCHITECTURE_DRIFT.md`

**Deployment Completed:** 2025-12-03  
**Ready for Academic Submission:** ✅ YES

---

