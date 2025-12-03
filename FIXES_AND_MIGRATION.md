# Fixes & Migration Guide: Traefik → NGINX

**Last Updated:** 2025-12-03  
**Scope:** Both master (Traefik) and nginx-migration (NGINX) branches

---

## Overview

This document tracks all issues encountered during initial Traefik setup (master branch) and subsequent migration to NGINX Ingress (nginx-migration branch), with fixes applied to each.

---

## Phase 1: Initial Traefik Setup (master branch)

### Issue 1: y-websocket Binding to localhost

**Discovery:** WebSocket connections failing, external clients couldn't reach the service.

**Root Cause:** y-websocket container was binding to `localhost:1234` (127.0.0.1) instead of `0.0.0.0:1234`, making it unreachable from other pods/nodes.

**Environment:** v1.4.0 release

**Fix Applied:**
- Rebuilt Docker image `skkhumaini1119/y-websocket:v1.4-fixed1`
- Modified entry point to bind to `0.0.0.0` instead of `localhost`
- Updated deployment to use new image tag

**Impact:** ✅ Resolved WebSocket connectivity for internal pod-to-pod communication

**Verification:**
```bash
kubectl exec <yjs-pod> -- netstat -tlnp | grep 1234
# Before: tcp 0 0 127.0.0.1:1234 ...
# After:  tcp 0 0 0.0.0.0:1234 ...
```

---

### Issue 2: GCP Load Balancer Health Check Failing

**Discovery:** Public IP 34.49.56.133 not responding; backend service showing "Unhealthy".

**Root Cause:** 
- GCP LB instance-group named-port was misconfigured
- Named-port `traefik-nodeport` pointing to wrong port
- Backend health checks timing out

**Environment:** v1.4.1 → v1.4.2 migration

**Fix Applied:**
```bash
# Update instance-group named-port mapping
gcloud compute instance-groups unset-named-ports private-cloud-nodes-ig \
  --named-ports=traefik-nodeport

gcloud compute instance-groups set-named-ports private-cloud-nodes-ig \
  --named-ports=traefik-nodeport:30080 \
  --zone=us-central1-a
```

**Verification:**
```bash
gcloud compute instance-groups describe private-cloud-nodes-ig \
  --zone=us-central1-a \
  --format="value(namedPorts[*])"
# Expected: traefik-nodeport:30080
```

**Impact:** ✅ LB backend became Healthy, public IP started responding (HTTP 200)

---

### Issue 3: Traefik Controller Readiness Probe Failure

**Discovery:** Traefik pod stuck in CrashLoopBackOff / NotReady state.

**Root Cause:** Readiness probe endpoint incorrect or misconfigured in Traefik manifest.

**Environment:** v1.4.2 release

**Fix Applied:**
- Patched Traefik readiness probe to use correct endpoint: `/ping` instead of `/health`
- Added startup probe for slower initialization
- Updated manifest: `k8s-manifests/09-traefik-ingress.yaml`

**Traefik Manifest Change:**
```yaml
readinessProbe:
  httpGet:
    path: /ping  # Changed from /health
    port: 8080
  initialDelaySeconds: 5
  periodSeconds: 5
```

**Impact:** ✅ Traefik pod now starts successfully and stays Ready

---

### Issue 4: Redis Pub/Sub Not Publishing (Intermittent)

**Discovery:** Real-time sync working for some users but not others; Redis channel subscriptions showing no activity.

**Root Cause:** Redis StatefulSet DNS resolution inconsistent; y-websocket connecting to `redis-0.redis-svc` sometimes failed.

**Environment:** v1.4.1 release

**Fix Applied:**
- Ensured Redis headless service name resolution
- Updated y-websocket deployment `REDIS_URL` environment variable:
  - From: `redis://redis:6379`
  - To: `redis://redis-0.redis-svc.whiteboard.svc.cluster.local:6379`
- Added liveness probe to y-websocket to detect disconnection

**Environment Variable:**
```yaml
env:
- name: REDIS_URL
  value: "redis://redis-0.redis-svc.whiteboard.svc.cluster.local:6379"
```

**Impact:** ✅ Reliable Redis connectivity; real-time sync consistent

---

### Issue 5: MongoDB Atlas Connection String Not Working

**Discovery:** Yjs server unable to connect to MongoDB Atlas; auth failures.

**Root Cause:** MongoDB connection string in secret was expired or missing credentials; Atlas IP allowlist didn't include Cloud NAT IP.

**Environment:** v1.4.1 release

**Fix Applied:**
1. Generated new MongoDB Atlas credentials
2. Obtained Cloud NAT IP:
   ```bash
   gcloud compute addresses describe private-cloud-nat-ip --region=us-central1 \
     --format="value(address)"
   # Returned: 35.xxx.xxx.xxx
   ```
3. Added Cloud NAT IP to MongoDB Atlas IP allowlist
4. Updated secret with new URI:
   ```bash
   kubectl -n whiteboard create secret generic mongo-uri \
     --from-literal=MONGO_URI="mongodb+srv://user:password@cluster.mongodb.net/whiteboard-metadata-db" \
     --dry-run=client -o yaml | kubectl apply -f -
   ```

**Verification:**
```bash
kubectl -n whiteboard exec <yjs-pod> -- mongosh "mongodb+srv://..." --eval "db.adminCommand('ping')"
# Expected: { ok: 1 }
```

**Impact:** ✅ MongoDB connectivity verified; metadata persistence working

---

### Issue 6: GCS Bucket Access Denied (Workload Identity IAM Incomplete)

**Discovery:** Snapshot CronJob failing with `AccessDeniedException: 403`

**Root Cause:** Service account `snapshot-sa` bound to Workload Identity annotation but lacked GCS permissions.

**Environment:** v1.4.5 release

**Fix Applied:**
```bash
# Grant storage.objectAdmin role to snapshot SA
gcloud projects add-iam-policy-binding helical-sled-477919-e9 \
  --member="serviceAccount:snapshot-sa@helical-sled-477919-e9.iam.gserviceaccount.com" \
  --role="roles/storage.objectAdmin"
```

**Verification:**
```bash
gcloud projects get-iam-policy helical-sled-477919-e9 \
  --flatten="bindings[].members" \
  --filter="bindings.role:roles/storage.objectAdmin" \
  --format="table(bindings.members)" | grep snapshot-sa
```

**Impact:** ✅ Snapshot CronJob now has full GCS access

---

## Phase 2: Traefik → NGINX Migration (nginx-migration branch)

### Issue 1: NGINX Controller Deployment Fails

**Discovery:** Attempted to deploy NGINX Ingress Controller; pod stuck in Pending.

**Root Cause:** Resource requests in NGINX manifest exceeded available node capacity.

**Environment:** nginx-migration branch, v1.4.6

**Fix Applied:**
- Reduced NGINX controller resource requests in `k8s-manifests/11-nginx-ingress.yaml`:
  ```yaml
  resources:
    requests:
      cpu: 100m        # Reduced from 200m
      memory: 128Mi    # Reduced from 256Mi
    limits:
      cpu: 200m        # Reduced from 500m
      memory: 256Mi    # Reduced from 512Mi
  ```

**Verification:**
```bash
kubectl -n kube-system get pods -l app.kubernetes.io/name=ingress-nginx
# Expected: Running (after 30 seconds)
```

**Impact:** ✅ NGINX controller pod now starts successfully

---

### Issue 2: NGINX Ingress Routes Not Working (404 errors)

**Discovery:** Accessing http://34.49.56.133/ returned 404; paths not routing to backends.

**Root Cause:** 
- Ingress resource using old ingressClassName `traefik` (should be `nginx`)
- Backend service names mismatched between Ingress rules and actual services

**Environment:** nginx-migration branch, v1.4.6

**Fix Applied:**
- Updated `k8s-manifests/08-ingress-tls.yaml`:
  ```yaml
  apiVersion: networking.k8s.io/v1
  kind: Ingress
  metadata:
    name: excalidraw-ingress
    namespace: whiteboard
  spec:
    ingressClassName: nginx  # Changed from: traefik
    rules:
    - http:
        paths:
        - path: /
          pathType: Prefix
          backend:
            service:
              name: excalidraw-ui-svc   # Verified this service exists
              port:
                number: 3000
        - path: /ws
          pathType: Prefix
          backend:
            service:
              name: yjs-server-svc      # Verified this service exists
              port:
                number: 1234
  ```

**Verification:**
```bash
# Check NGINX controller sees the ingress
kubectl -n kube-system logs -l app.kubernetes.io/name=ingress-nginx | grep "ingress.*created\|ingress.*updated"

# Test routes
curl -I http://34.49.56.133/
# Expected: HTTP 200 (Excalidraw UI)

# Test WebSocket path
curl -i -N -H "Connection: Upgrade" -H "Upgrade: websocket" http://34.49.56.133/ws
# Expected: HTTP 101 Switching Protocols (or 400 if no WebSocket client)
```

**Impact:** ✅ All ingress routes now functioning

---

### Issue 3: GCP LB Backend Named-Port Changed (Traefik → NGINX)

**Discovery:** After deploying NGINX, LB still routing to old Traefik NodePort; traffic not reaching NGINX.

**Root Cause:** GCP instance-group named-port still mapped to old Traefik port (30080); NGINX uses port 31853.

**Environment:** nginx-migration branch, v1.4.6

**Fix Applied:**
```bash
# Update instance-group named-port to NGINX NodePort
gcloud compute instance-groups unset-named-ports private-cloud-nodes-ig \
  --named-ports=traefik-nodeport \
  --zone=us-central1-a

gcloud compute instance-groups set-named-ports private-cloud-nodes-ig \
  --named-ports=traefik-nodeport:31853 \
  --zone=us-central1-a
```

**Alternative (recommended for clarity):**
```bash
# Or rename to reflect NGINX:
gcloud compute instance-groups unset-named-ports private-cloud-nodes-ig \
  --named-ports=traefik-nodeport \
  --zone=us-central1-a

gcloud compute instance-groups set-named-ports private-cloud-nodes-ig \
  --named-ports=nginx-nodeport:31853 \
  --zone=us-central1-a

# Update backend-service to use new named-port
gcloud compute backend-services update private-cloud-http-backend \
  --global \
  --instance-group=private-cloud-nodes-ig \
  --instance-group-zone=us-central1-a \
  --port-name=nginx-nodeport
```

**Verification:**
```bash
gcloud compute backend-services get-health private-cloud-http-backend --global
# Expected: All backends showing HEALTHY

curl -I http://34.49.56.133/
# Expected: HTTP 200
```

**Impact:** ✅ LB now routes traffic to NGINX controller on correct port

---

### Issue 4: CronJob Script Compatibility (Shell → Python)

**Discovery:** Snapshot CronJob running but pod crashing with `exec /bin/bash: exec format error`.

**Root Cause:** Inline bash script in CronJob had newline escape issues in container runtime; alpine/minimal images had shell compatibility problems.

**Environment:** nginx-migration branch, v1.4.6

**Fix Applied:**
- Rewrote CronJob script from shell to Python for better portability
- Changed image from `google/cloud-sdk:alpine` to `google/cloud-sdk:latest` (more reliable)
- Updated `k8s-manifests/10-snapshot-cronjob.yaml`:

**Before (Shell Script):**
```yaml
command:
- /bin/bash
- -c
- |
  #!/bin/bash
  set -e
  TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  ...
  mongodump --uri="$MONGO_URI" ...
  gsutil cp ... gs://...
```

**After (Python Script):**
```yaml
command:
- python3
- -c
- |
  import os, subprocess, sys
  from datetime import datetime
  
  mongo_uri = os.environ.get('MONGO_URI')
  gcs_bucket = os.environ.get('GCS_BUCKET')
  timestamp = datetime.utcnow().isoformat() + 'Z'
  
  # mongodump subprocess
  result = subprocess.run(['mongodump', f'--uri={mongo_uri}', ...])
  # gsutil subprocess
  result = subprocess.run(['gsutil', 'cp', ...])
```

**Verification:**
```bash
# Manually trigger CronJob
kubectl -n whiteboard create job snapshot-manual-$(date +%s) --from=cronjob/snapshot-export

# Watch pod
kubectl -n whiteboard get pods -w -l job-name=snapshot-manual-*

# Check logs
kubectl -n whiteboard logs -l job-name=snapshot-manual-* -f
# Expected: "Exporting CRDT snapshots..." → "Uploading to gs://..." → "Snapshot export completed"
```

**Impact:** ✅ CronJob now executes successfully

---

### Issue 5: CronJob GCS Bucket Environment Variable Placeholder

**Discovery:** Snapshot exports failing with `NoSuchBucket: 404 PROJECT_ID-whiteboard-snapshots does not exist`.

**Root Cause:** GCS bucket environment variable used placeholder `PROJECT_ID-whiteboard-snapshots` instead of actual bucket name.

**Environment:** nginx-migration branch, v1.4.6

**Fix Applied:**
- Updated `k8s-manifests/10-snapshot-cronjob.yaml`:
  ```yaml
  env:
  - name: GCS_BUCKET
    value: "helical-sled-477919-e9-whiteboard-snapshots"  # Was: PROJECT_ID-whiteboard-snapshots
  ```

- Also updated Workload Identity annotation:
  ```yaml
  annotations:
    iam.gke.io/gcp-service-account: snapshot-sa@helical-sled-477919-e9.iam.gserviceaccount.com  # Was: PROJECT_ID
  ```

**Verification:**
```bash
# Check CronJob environment
kubectl -n whiteboard get cronjob snapshot-export -o jsonpath='{.spec.jobTemplate.spec.template.spec.containers[0].env[1].value}'
# Expected: helical-sled-477919-e9-whiteboard-snapshots

# Verify bucket exists
gsutil ls gs://helical-sled-477919-e9-whiteboard-snapshots/
# Expected: (empty or list of existing snapshots)
```

**Impact:** ✅ CronJob now exports to correct GCS bucket

---

### Issue 6: y-websocket Image Tag Update (Traefik → NGINX)

**Discovery:** During migration, using old image tag that bound to localhost; networking fails.

**Root Cause:** Deployment still referencing `v1.4` image tag; needed `v1.4-fixed2` which binds to 0.0.0.0.

**Environment:** nginx-migration branch, v1.4.6

**Fix Applied:**
- Updated `k8s-manifests/05-yjs-deployment.yaml`:
  ```yaml
  containers:
  - name: yjs
    image: skkhumaini1119/y-websocket:v1.4-fixed2  # Was: v1.4
  ```

**Verification:**
```bash
kubectl -n whiteboard get deploy yjs-server -o jsonpath='{.spec.template.spec.containers[0].image}'
# Expected: skkhumaini1119/y-websocket:v1.4-fixed2

# Verify binding
kubectl -n whiteboard exec <yjs-pod> -- netstat -tlnp | grep 1234
# Expected: tcp 0 0 0.0.0.0:1234 ...
```

**Impact:** ✅ y-websocket now accepts external connections

---

## Summary: Fixes by Category

### Connectivity Fixes
| Issue | Fix | Impact |
|-------|-----|--------|
| y-websocket binding to localhost | Rebuilt image (v1.4-fixed1/2) | WebSocket works |
| GCP LB health check failing | Updated instance-group named-port | Public IP responds |
| Redis DNS resolution inconsistent | Full FQDN for Redis URL | Real-time sync reliable |

### Configuration Fixes
| Issue | Fix | Impact |
|-------|-----|--------|
| MongoDB credentials expired | Regenerated Atlas credentials + added NAT IP | DB connectivity works |
| GCS bucket placeholder | Substituted actual bucket name | Snapshots export correctly |
| Ingress routing 404 errors | Updated ingressClassName + service names | Routes work |

### IAM & Permissions Fixes
| Issue | Fix | Impact |
|-------|-----|--------|
| GCS access denied (403) | Granted storage.objectAdmin role | Snapshots work |
| Workload Identity incomplete | Added annotation to ServiceAccount | Pod authentication works |

### Migration Fixes (Traefik → NGINX)
| Issue | Fix | Impact |
|-------|-----|--------|
| NGINX pod Pending | Reduced resource requests | Controller deploys |
| LB routing to old Traefik port | Updated named-port to 31853 | Traffic reaches NGINX |
| CronJob script errors | Rewrote in Python | Jobs execute successfully |

---

## Verification Checklist (Post-Migration)

```bash
# 1. All pods running
kubectl -n whiteboard get pods
# ✓ All should be Running/Ready

# 2. NGINX controller active
kubectl -n kube-system get pods -l app.kubernetes.io/name=ingress-nginx
# ✓ Should show Running controller pod

# 3. Ingress routes configured
kubectl -n whiteboard get ingress -o yaml | grep -E "path:|backend"
# ✓ Should show / and /ws routes

# 4. Public IP responds
curl -I http://34.49.56.133/
# ✓ HTTP 200 (not 502, 503, or timeout)

# 5. Services have endpoints
kubectl -n whiteboard get endpoints
# ✓ All services should have active endpoints

# 6. MongoDB connected
kubectl -n whiteboard exec <yjs-pod> -- env | grep MONGO_URI
# ✓ Should show valid connection string

# 7. GCS accessible
gcloud projects get-iam-policy helical-sled-477919-e9 \
  --flatten="bindings[].members" \
  --filter="bindings.role:roles/storage.objectAdmin" | grep snapshot-sa
# ✓ snapshot-sa should be listed

# 8. Redis syncing
kubectl -n whiteboard exec <yjs-pod> -- redis-cli PING
# ✓ PONG

# 9. Real-time sync working
# Open 2 browser tabs at http://34.49.56.133/
# Draw on Tab 1 → See instant sync on Tab 2
# ✓ Should see <100ms latency
```

---

## When to Use Each Branch

### master (Traefik)
- **Use for:** Historical reference, understanding original design
- **Do not use for:** New deployments
- **Issues:** More complex, Helm dependency, less documented
- **Traefik-specific issues:** Refer to `MASTER_BRANCH_REFERENCE.md`

### nginx-migration (NGINX)
- **Use for:** All new deployments
- **Advantages:** Simpler, no Helm, all fixes applied
- **All issues fixed:** ✅ Connectivity, Configuration, IAM, Migration
- **Deployment guide:** Refer to `NGINX_BRANCH_DEPLOYMENT.md`

---

## Quick Reference: If Something Breaks

1. **Connectivity issue?** → See Connectivity Fixes section
2. **Pod not starting?** → See TROUBLESHOOTING.md
3. **Routes returning 404?** → See Ingress routing fix
4. **Real-time sync broken?** → See Redis / Connectivity fixes
5. **Snapshots failing?** → See GCS / CronJob fixes
6. **Migrating from master?** → See Phase 2 Migration section

---

**All issues documented. All fixes applied. Ready for production.** ✅
