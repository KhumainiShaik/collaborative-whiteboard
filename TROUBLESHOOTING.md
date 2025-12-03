# Troubleshooting Guide

**Last Updated:** 2025-12-03  
**Applies to:** nginx-migration & master branches  
**Status:** Comprehensive quick-reference

---

## Connectivity Issues

### Symptom: Public IP not responding (http://34.49.56.133/)

**Step 1: Check Load Balancer**
```bash
# Is LB in service?
gcloud compute backend-services get-health private-cloud-http-backend --global

# Check status column — should show HEALTHY
```

**Step 2: Check Backend Services**
```bash
# Are nodes accepting traffic on NodePort 31853?
gcloud compute instance-groups describe private-cloud-nodes-ig

# Verify named-port mapping
gcloud compute instance-groups describe private-cloud-nodes-ig --format="value(namedPorts[*])"
```

**Step 3: Check NGINX Ingress on Cluster**
```bash
sudo kubectl -n kube-system get pods -l app.kubernetes.io/name=ingress-nginx
# Pod should be Running

sudo kubectl -n kube-system describe pod <nginx-pod> | grep -A 5 "Conditions"
```

**Step 4: Check Ingress Routes**
```bash
sudo kubectl -n whiteboard get ingress -o yaml
# Verify:
# - ingressClassName: nginx
# - rules for / and /ws paths
# - backend services exist
```

**Fix Summary:**
1. If LB unhealthy: Check firewall rules allow ingress from LB to nodes
2. If backend unhealthy: Check if NGINX pod is running and healthy
3. If ingress not synced: Restart NGINX pod: `kubectl delete pod -l app.kubernetes.io/name=ingress-nginx -n kube-system`

---

### Symptom: WebSocket endpoint not working (ws://34.49.56.133/ws)

**Step 1: Verify Service Routing**
```bash
# Is yjs-server service accessible?
sudo kubectl -n whiteboard get svc yjs-server-svc
# Should show CLUSTER-IP and port 1234

# Are there endpoints (ready pods)?
sudo kubectl -n whiteboard get endpoints yjs-server-svc
# Should show IP:1234 in ENDPOINTS column
```

**Step 2: Check Ingress Rule**
```bash
sudo kubectl -n whiteboard get ingress -o yaml | grep -A 10 'path: /ws'
# Should show:
# - path: /ws
#   backend:
#     service:
#       name: yjs-server-svc
#       port:
#         number: 1234
```

**Step 3: Check y-websocket Pod**
```bash
sudo kubectl -n whiteboard get pods -l app=yjs-server -o wide
# Pod must be Running

# Is it listening on 1234?
sudo kubectl -n whiteboard exec <yjs-pod> -- netstat -tlnp | grep 1234
# Or: ss -tlnp | grep 1234
```

**Step 4: Test Locally**
```bash
# Port-forward to test
sudo kubectl -n whiteboard port-forward svc/yjs-server-svc 1234:1234 &

# Try WebSocket connection
wscat -c ws://localhost:1234
# Should connect successfully
```

**Fix Summary:**
1. If service has no endpoints: yjs-server pod not running — restart deployment
2. If ingress rule wrong: Reapply ingress manifest
3. If connection times out: Check firewall allows 1234 from nodes to pods

---

## Pod Issues

### Symptom: Pod stuck in CrashLoopBackOff

**Step 1: Identify the Pod**
```bash
sudo kubectl -n whiteboard get pods
# Find any with STATUS != Running
```

**Step 2: Get Pod Logs**
```bash
sudo kubectl -n whiteboard logs <pod-name>
# Or previous logs if pod crashed:
sudo kubectl -n whiteboard logs <pod-name> --previous
```

**Step 3: Describe Pod**
```bash
sudo kubectl -n whiteboard describe pod <pod-name> | tail -30
# Look for:
# - Events (last action taken)
# - Reason (CrashLoopBackOff, ImagePullBackOff, etc.)
```

**Fix by Symptom:**

| Reason | Cause | Fix |
|--------|-------|-----|
| **ImagePullBackOff** | Image not found or private registry auth fails | Check image name, registry credentials |
| **CrashLoopBackOff** | Application crashing | Check logs for error message |
| **Pending** | Resource request too high | `kubectl describe node` to see available resources |
| **OOMKilled** | Out of memory | Increase memory limit or reduce replicas |

**Example: Excalidraw stuck in CrashLoopBackOff**
```bash
# Get logs
sudo kubectl -n whiteboard logs <excalidraw-pod> --previous

# Look for common errors:
# - "Cannot find module" → missing dependency
# - "Port already in use" → port conflict
# - "Connection refused" → Redis/MongoDB not accessible

# Fix: Usually requires redeploying with corrected image or environment
sudo kubectl -n whiteboard delete pod <excalidraw-pod>
# New pod will start
```

---

### Symptom: Pod pending (won't start)

**Step 1: Check Resources**
```bash
# Pod resource requests vs node capacity
sudo kubectl -n whiteboard describe pod <pod-name> | grep -A 5 "Requests"

# Node available resources
sudo kubectl describe nodes
# Look for "Allocatable" and "Allocated resources"
```

**Step 2: Check Events**
```bash
sudo kubectl -n whiteboard describe pod <pod-name> | tail -10
# Look for messages like:
# - "Insufficient memory"
# - "Insufficient cpu"
# - "No matching labels"
```

**Fix:**
- If resource limit too high: Edit deployment and reduce requests
- If node capacity low: Add more nodes or scale down other pods

```bash
# Scale down other deployments
sudo kubectl -n whiteboard scale deploy <other-deploy> --replicas=0

# Then retry the pending pod
sudo kubectl -n whiteboard rollout restart deploy <deployment>
```

---

## Real-Time Sync Issues

### Symptom: Changes not syncing between tabs/clients

**Step 1: Verify y-websocket Pod**
```bash
# Is it running?
sudo kubectl -n whiteboard get pods -l app=yjs-server

# Check logs
sudo kubectl -n whiteboard logs -l app=yjs-server --tail=50
# Look for subscription messages (clients connecting/disconnecting)
```

**Step 2: Check Redis Pub/Sub**
```bash
# Is Redis pod running?
sudo kubectl -n whiteboard get pods -l app=redis

# Connect to Redis
sudo kubectl -n whiteboard exec -it redis-0 -- redis-cli

# Inside redis-cli:
PING
# Should return PONG

# Check pub/sub channels
PUBSUB CHANNELS
# Should show active channels

# Exit
EXIT
```

**Step 3: Check Network Policy**
```bash
sudo kubectl -n whiteboard get networkpolicy
# If any policies exist, ensure they allow:
# - yjs-server → redis:6379
# - excalidraw-ui → yjs-server:1234
```

**Step 4: Test Connectivity**
```bash
# From y-websocket pod, can it reach Redis?
sudo kubectl -n whiteboard exec <yjs-pod> -- nc -zv redis 6379
# Should print: Connection to redis 6379 port [tcp/*] succeeded!
```

**Fix Summary:**
1. If y-websocket pod not running: Restart deployment
2. If Redis unreachable: Check firewall and network policy
3. If pub/sub broken: Restart Redis pod

---

## Database Connectivity

### Symptom: MongoDB Atlas connection failing

**Step 1: Check Secret**
```bash
# Is secret present?
sudo kubectl -n whiteboard get secret mongo-uri

# Decode and verify URI
sudo kubectl -n whiteboard get secret mongo-uri -o jsonpath='{.data.MONGO_URI}' | base64 --decode
# Should output valid MongoDB connection string
```

**Step 2: Test Connectivity from Pod**
```bash
# Exec into y-websocket pod
sudo kubectl -n whiteboard exec -it <yjs-pod> -- /bin/sh

# Inside pod, try connecting with mongo client (if available)
mongosh "mongodb+srv://..."
# Or use curl to test if available
```

**Step 3: Check Atlas Network Access**
```bash
# Via gcloud, check Atlas IP allowlist
# (Usually done in MongoDB Atlas console)
# Ensure Cloud NAT IP range is included

# Get Cloud NAT IP
gcloud compute addresses describe private-cloud-nat-ip --region=us-central1 --format="value(address)"
```

**Fix:**
1. If connection string wrong: Update secret
2. If IP not allowlisted: Add Cloud NAT IP to MongoDB Atlas IP whitelist
3. If certificate error: Ensure CA certificates are in container image

```bash
# Update secret if needed
sudo kubectl -n whiteboard create secret generic mongo-uri \
  --from-literal=MONGO_URI="<new-uri>" \
  --dry-run=client -o yaml | sudo kubectl apply -f -

# Restart pods to pick up new secret
sudo kubectl -n whiteboard rollout restart deploy yjs-server
```

---

## GCS Snapshot Issues

### Symptom: CronJob not running or failing

**Step 1: Check CronJob**
```bash
sudo kubectl -n whiteboard get cronjob snapshot-export -o yaml

# Verify:
# - schedule is valid (e.g., "0 */4 * * *" = every 4 hours)
# - suspend: false (not suspended)
# - serviceAccountName: snapshot-sa (correct)
```

**Step 2: Check Recent Jobs**
```bash
sudo kubectl -n whiteboard get jobs -l cronjob-name=snapshot-export --sort-by=.metadata.creationTimestamp | tail -3
# View recent job attempts
```

**Step 3: Check Job Logs**
```bash
# Get latest job
LATEST_JOB=$(sudo kubectl -n whiteboard get jobs -l cronjob-name=snapshot-export -o jsonpath='{.items[-1].metadata.name}')

# Check logs
sudo kubectl -n whiteboard logs -l job-name=$LATEST_JOB --tail=100
# Look for error messages
```

**Step 4: Check Workload Identity**
```bash
# Is annotation present?
sudo kubectl -n whiteboard get sa snapshot-sa -o yaml | grep -i gcp-service-account

# Verify annotation format: iam.gke.io/gcp-service-account: <email>@<project>.iam.gserviceaccount.com
```

**Step 5: Check GCS Access**
```bash
# Verify service account has permissions
gcloud projects get-iam-policy helical-sled-477919-e9 \
  --flatten="bindings[].members" \
  --filter="bindings.role:roles/storage.objectAdmin" | grep snapshot-sa
```

**Fix by Symptom:**

| Symptom | Cause | Fix |
|---------|-------|-----|
| **Job doesn't appear** | CronJob schedule not reached | Wait for next schedule, or manually trigger: `kubectl create job --from=cronjob/snapshot-export test-manual` |
| **Job fails immediately** | Pod crash (CrashLoopBackOff) | Check logs, verify image and script |
| **403 Forbidden from GCS** | Workload Identity IAM missing | `gcloud projects add-iam-policy-binding ... --role=roles/storage.objectAdmin` |
| **Connection timeout** | MongoDB or GCS unreachable | Check network policy, firewall, IP allowlist |

**Manually Trigger Snapshot Job (for testing)**
```bash
# Create one-off job from CronJob template
sudo kubectl -n whiteboard create job snapshot-manual-$(date +%s) --from=cronjob/snapshot-export

# Check pod
sudo kubectl -n whiteboard get pods -l job-name=snapshot-manual-* -w

# Check logs
sudo kubectl -n whiteboard logs -l job-name=snapshot-manual-* -f
```

---

## Node Issues

### Symptom: Node shows NotReady

**Step 1: Check Node Status**
```bash
sudo kubectl describe node <node-name>

# Look for:
# - Ready: False/Unknown
# - Conditions (what's failing?)
# - Allocatable resources
```

**Step 2: SSH to Node and Check**
```bash
# SSH to the node
gcloud compute ssh <node-vm-name> --zone=us-central1-a --tunnel-through-iap

# Check k3s service
sudo systemctl status k3s
# Should be active/running

# Check logs
sudo journalctl -u k3s -n 50
# Look for errors

# Check connectivity to server
sudo kubectl get nodes
# Should see all nodes
```

**Step 3: Check Resources**
```bash
# On the node, check:
df -h  # Disk space
free -h  # Memory
ps aux | grep -E "kubelet|docker|containerd"  # Processes running
```

**Fix:**
1. If k3s service down: `sudo systemctl restart k3s`
2. If disk full: `sudo rm -rf /var/lib/rancher/k3s/agent/containerd/io.containerd.content.v1.content/blobs/sha256/*` (clear old images)
3. If memory low: Restart node or reduce workload

---

## Cleanup Commands

### Remove Failed Pods
```bash
# Delete all CrashLoopBackOff pods
sudo kubectl -n whiteboard delete pods --field-selector=status.phase=Failed

# Force delete stuck pod
sudo kubectl -n whiteboard delete pod <pod-name> --grace-period=0 --force
```

### Clear Old Snapshots
```bash
# Delete old snapshot jobs
sudo kubectl -n whiteboard delete jobs -l cronjob-name=snapshot-export --field-selector=status.successful=1 -k 3
# Keeps last 3 successful jobs
```

### Reset Cluster
```bash
# Delete entire namespace (cascades all resources)
sudo kubectl delete namespace whiteboard

# Redeploy
sudo kubectl apply -f k8s-manifests/00-namespace.yaml
# (Continue with other manifests)
```

---

## Quick Reference: Common Fixes

| Problem | Command | Expected Output |
|---------|---------|-----------------|
| Pod not running | `kubectl logs <pod>` | Application logs (no errors) |
| Service unreachable | `kubectl get endpoints` | IP:port listed |
| Ingress not routing | `kubectl get ingress -o yaml` | Correct backend service names |
| Redis not syncing | `redis-cli PING` | PONG |
| GCS access denied | `gcloud projects get-iam-policy ...` | service account listed |
| Snapshot job stuck | `kubectl create job --from=cronjob/...` | Job created manually |

---

**Always start with:** `kubectl describe [resource]` and `kubectl logs [pod]`

These two commands reveal 90% of issues.
