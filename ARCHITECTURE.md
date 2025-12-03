# Architecture Documentation

**Version:** v1.4.6  
**Last Updated:** 2025-12-03  
**Status:** PRODUCTION-READY

---

## Overview

Public HTTP Load Balancer → NGINX Ingress → Private k3s Cluster. All nodes private (no public IPs). Real-time sync via Yjs + Redis. Durable storage: MongoDB Atlas. Snapshots exported to GCS via CronJob. Admin access via IAP tunnel (no public SSH).

---

## Infrastructure Stack

### Networking & Cloud
- **VPC:** Private subnet (10.10.0.0/16), no public node IPs
- **Load Balancer:** GCP HTTP LB (public IP 34.49.56.133)
- **NAT:** Cloud NAT for cluster egress
- **Firewall:** Internal allow rules + IAP access only

### Kubernetes Platform
- **Cluster:** k3s v1.34.2+k3s1 (1 server + 2 workers, all private)
- **CNI:** Flannel pod networking
- **Ingress:** NGINX Controller (no Helm), NodePort 31853
- **Storage:** local-path provisioner (k3s default)

### Application Components

| Component | Type | Image | Port | Replicas | Purpose |
|-----------|------|-------|------|----------|---------|
| **Excalidraw UI** | Deployment | skkhumaini1119/excalidraw-yjs:v1.4.6 | 3000 | 2 | HTTP frontend |
| **y-websocket** | Deployment | skkhumaini1119/y-websocket:v1.4-fixed2 | 1234 | 1 | WebSocket CRDT sync |
| **Redis** | StatefulSet | redis:7-alpine | 6379 | 1 | Pub/sub for real-time broadcast |

### External Services
- **MongoDB Atlas:** Managed database (external, IP allowlist via Cloud NAT)
- **GCS Bucket:** Snapshot archive (helical-sled-477919-e9-whiteboard-snapshots)
- **Workload Identity:** CronJob → GCS auth (no static keys)

---

## Architecture Diagram

```
┌─────────────────────────────────────────────┐
│    PUBLIC INTERNET (34.49.56.133:80)        │
└──────────────────────┬──────────────────────┘
                       │
              ┌────────▼────────┐
              │  GCP HTTP LB    │
              │  (External)     │
              └────────┬────────┘
                       │
         ┌─────────────▼─────────────┐
         │ Private VPC (10.10.0.0)   │
         │ Cloud NAT + Firewall      │
         └─────────────┬─────────────┘
                       │
        ┌──────────────▼──────────────┐
        │  NGINX Ingress Controller   │
        │  (NodePort 31853)           │
        └──────────────┬──────────────┘
                       │
    ┌──────────────────┼──────────────────┐
    │                  │                  │
┌───▼────┐      ┌─────▼────┐      ┌─────▼────┐
│Excalidraw   │      │yjs-ws   │      │ Redis    │
│ UI (3000)   │      │(1234)   │      │(6379)   │
│  2 replicas │      │ 1 repli  │      │1 replica │
└────────┘      └──────────┘      └──────────┘
    │                  │                  │
    └──────────────────┼──────────────────┘
                       │
    ┌──────────────────┼──────────────────┐
    ↓                  ↓                  ↓
MongoDB Atlas      GCS Bucket        Cloud NAT
(External DB)      (Snapshots)       (Egress)
```

---

## Data Flow

### Drawing Synchronization
1. User draws on Client A → Excalidraw UI (HTTP 3000)
2. UI sends Yjs changes via WebSocket to y-websocket server (port 1234)
3. y-websocket applies op to local CRDT state
4. y-websocket publishes to Redis pub/sub channel
5. All other y-websocket instances subscribe to Redis
6. Instances apply ops to their local CRDT → instant merge
7. Connected clients receive updates in real-time

### Snapshot Export (Every 4 Hours)
1. CronJob triggers (schedule: `0 */4 * * *`)
2. Connects to MongoDB Atlas via secret
3. Runs mongodump on `crdt_snapshots` collection
4. Compresses dump with gzip
5. Uploads to GCS bucket via Workload Identity (authenticated, no keys)
6. Updates latest-export.txt with timestamp

### Cluster Recovery (After Restart)
1. y-websocket pod starts
2. Fetches latest snapshot from GCS (path from MongoDB Atlas metadata)
3. Loads snapshot into local CRDT
4. Subscribes to Redis pub/sub for new operations
5. Merges incoming ops → reaches current state

---

## Current Deployment Status

### All Pods Running ✅
```
Namespace: whiteboard

Deployments:
  excalidraw-ui ..................... 2/2 Ready ✅
  yjs-server ........................ 1/1 Ready ✅

StatefulSets:
  redis-0 ........................... 1/1 Ready ✅

Services:
  excalidraw-ui-svc (NodePort) ...... Active ✅
  yjs-server-svc (ClusterIP) ........ Active ✅
  redis-svc (ClusterIP) ............. Active ✅

CronJob:
  snapshot-export ................... Operational ✅
    (Workload Identity IAM fix applied)
```

### Connectivity ✅
- Public IP: 34.49.56.133 (HTTP 200)
- NGINX Ingress: Routes / → excalidraw-ui:3000
- NGINX Ingress: Routes /ws → yjs-server:1234
- MongoDB Atlas: Connected (URI in secret)
- GCS Bucket: Accessible (IAM permissions granted)

---

## Deployment Checklist

- [x] Public HTTP Load Balancer configured
- [x] Private VPC with Cloud NAT
- [x] k3s cluster (3 nodes, all private)
- [x] NGINX Ingress Controller deployed
- [x] Excalidraw UI (2 replicas)
- [x] y-websocket (1 replica, 0.0.0.0 binding)
- [x] Redis StatefulSet (1 replica, 10Gi PVC)
- [x] MongoDB Atlas connected (URI in secret)
- [x] GCS bucket accessible (Workload Identity IAM)
- [x] Snapshot CronJob operational
- [x] IAP tunnel for admin SSH access

**Status: PRODUCTION-READY ✅**

---

## Access & Testing

### Public Access
```bash
# Open in browser
http://34.49.56.133/

# Test real-time sync: Open 2 tabs, draw on Tab 1, watch Tab 2 sync instantly
```

### Admin Access (SSH via IAP)
```bash
gcloud compute ssh private-cloud-server-0 --zone=us-central1-a --tunnel-through-iap
sudo kubectl -n whiteboard [command]
```

### Verify Components
```bash
# Check all pods
sudo kubectl -n whiteboard get pods -o wide

# Check services
sudo kubectl -n whiteboard get svc

# Check ingress routing
sudo kubectl -n whiteboard get ingress -o yaml

# Verify snapshot CronJob
sudo kubectl -n whiteboard get cronjob,jobs

# List GCS snapshots
gsutil ls gs://helical-sled-477919-e9-whiteboard-snapshots/
```

---

## Performance Characteristics

- **Latency:** Sub-100ms real-time sync (local Redis pub/sub)
- **Throughput:** 5-10 concurrent users (tested)
- **Scalability:** Add replicas as needed (horizontal scaling)

---

## Security Notes

- All nodes private (no public IPs)
- Single public entry point (HTTP LB)
- Workload Identity for pod-to-GCS auth (no keys)
- MongoDB Atlas network access via Cloud NAT IP allowlist
- IAP tunnel for admin access (no public SSH)
- All secrets in k8s Secrets object (no hardcoded credentials)

---

## Components Used (Single-Choice List)

**Networking & Infrastructure**
- ✅ Custom VPC (private subnet)
- ✅ Firewall rules (internal + IAP only)
- ✅ Cloud NAT (egress)
- ✅ GCP HTTP Load Balancer (public IP)

**Kubernetes & Platform**
- ✅ k3s server VM (private)
- ✅ k3s worker VMs (private, 2+)
- ✅ Flannel CNI (pod networking)
- ✅ NGINX Ingress Controller (routes / and /ws)

**Application & State**
- ✅ Excalidraw-YJS Deployment (port 3000)
- ✅ y-websocket Deployment (port 1234)
- ✅ Redis StatefulSet (pub/sub, PVCs)
- ✅ MongoDB Atlas (managed external DB)
- ✅ GCS bucket (snapshot archive)

**Auth / IAM / Operations**
- ✅ Service accounts for nodes
- ✅ Workload Identity (CronJob → GCS)
- ✅ Terraform (infra provisioning)
- ✅ IAP / Cloud Shell (admin access)

---

**End Date:** 2025-12-03  
**Ready for Submission:** ✅ YES
