# Implementation Guide: Current → New Architecture

## What Changes & What Stays the Same

### ✅ STAYS UNCHANGED

1. **K3s cluster infrastructure**
   - Same 3 VMs (1 server + 2 workers)
   - Same network topology
   - Same firewall rules (+ MongoDB allowlist)

2. **Excalidraw UI application**
   - No code changes needed
   - Same Docker image works
   - Just different networking

3. **Redis (mostly)**
   - StatefulSet already exists
   - Now used for Pub/Sub (was only cache)
   - PVC stays same size

4. **Kubernetes namespace & RBAC**
   - Same "whiteboard" namespace
   - Same service accounts
   - Same pod security policies

---

### ❌ CHANGES REQUIRED

| Component | Change | Complexity |
|-----------|--------|-----------|
| Load Balancer | Traefik → GCP HTTP LB | Medium |
| Database | Cloud SQL → MongoDB Atlas | High |
| Snapshot Strategy | Auto backup → CronJob export | Low |
| y-websocket | Single pod → Clustered with Redis | High |
| Terraform | Add new files + modify existing | High |
| Environment Variables | Add Atlas URI + Redis Pub/Sub config | Low |

---

## Detailed Change Breakdown

### Change 1: Load Balancer Setup

**File:** NEW `terraform/load-balancer.tf`

```hcl
# NEW FILE: Add GCP HTTP Load Balancer

resource "google_compute_instance_group" "k3s_nodes" {
  name        = "k3s-node-group"
  description = "Instance group for k3s nodes"
  zone        = var.gcp_zone

  instances = [
    google_compute_instance.k3s_master.id,
    google_compute_instance.k3s_worker[0].id,
    google_compute_instance.k3s_worker[1].id,
  ]
}

resource "google_compute_http_health_check" "ingress" {
  name               = "ingress-health-check"
  request_path       = "/"
  port               = 80
  check_interval_sec = 10
  timeout_sec        = 5
}

resource "google_compute_backend_service" "ingress" {
  name            = "ingress-backend-service"
  protocol        = "HTTP"
  port_name       = "http"
  health_checks   = [google_compute_http_health_check.ingress.id]
  session_affinity = "NONE"

  backend {
    group           = google_compute_instance_group.k3s_nodes.id
    balancing_mode  = "RATE"
    max_rate_per_endpoint = 100
  }

  log_config {
    enable = true
  }
}

resource "google_compute_url_map" "default" {
  name            = "url-map"
  default_service = google_compute_backend_service.ingress.id
}

resource "google_compute_target_http_proxy" "default" {
  name       = "http-proxy"
  url_map    = google_compute_url_map.default.id
}

resource "google_compute_global_forwarding_rule" "default" {
  name       = "global-forwarding-rule"
  target     = google_compute_target_http_proxy.default.id
  ip_protocol = "TCP"
  port_range = "80"
  ip_address = google_compute_address.static_ip.address

  depends_on = [google_compute_address.static_ip]
}
```

**File:** MODIFY `terraform/network.tf`

```hcl
# ADD to firewall rules:

resource "google_compute_firewall" "allow_ingress_health_check" {
  name    = "allow-ingress-health-check"
  network = google_compute_network.vpc.name

  allow {
    protocol = "tcp"
    ports    = ["80"]
  }

  source_ranges = ["35.191.0.0/16", "130.211.0.0/22"]  # GCP health check ranges
  target_tags   = ["k3s-node"]
}

resource "google_compute_firewall" "allow_mongodb_atlas" {
  name    = "allow-mongodb-atlas"
  network = google_compute_network.vpc.name

  allow {
    protocol = "tcp"
    ports    = ["27017"]
  }

  source_ranges = [google_compute_route.cloud_nat.next_hop_gateway]
  target_tags   = ["k3s-node"]
  direction     = "EGRESS"
}
```

---

### Change 2: Database Migration

**File:** NEW `terraform/mongodb-atlas.tf`

```hcl
# Configuration for MongoDB Atlas (optional - mostly manual setup)

# Note: MongoDB Atlas is managed outside Terraform
# This file documents the connection for reference

variable "mongodb_atlas_uri" {
  description = "MongoDB Atlas connection string"
  type        = string
  sensitive   = true
  # Example: mongodb+srv://username:password@cluster0.xxxxx.mongodb.net/whiteboard?retryWrites=true&w=majority
}

output "mongodb_atlas_uri" {
  description = "MongoDB Atlas URI (from manual setup)"
  value       = var.mongodb_atlas_uri
  sensitive   = true
}
```

**File:** NEW `k8s-manifests/02-mongodb-atlas-secret.yaml`

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: mongodb-atlas-uri
  namespace: whiteboard
type: Opaque
stringData:
  uri: mongodb+srv://username:password@cluster0.xxxxx.mongodb.net/whiteboard?retryWrites=true&w=majority
```

**Setup Steps (Manual):**
1. Create MongoDB Atlas account
2. Create cluster (M0 free tier acceptable for demo)
3. Get connection string
4. Add firewall rule: Allow connections from Cloud NAT IP
5. Create secret in Kubernetes with connection string

---

### Change 3: Redis Pub/Sub Configuration

**File:** MODIFY `k8s-manifests/03-redis-statefulset.yaml`

```yaml
# Change: Add Pub/Sub configuration

apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: redis
  namespace: whiteboard
spec:
  serviceName: redis
  replicas: 1  # Can scale to 3+ for HA
  selector:
    matchLabels:
      app: redis
  template:
    metadata:
      labels:
        app: redis
    spec:
      containers:
      - name: redis
        image: redis:7-alpine
        ports:
        - containerPort: 6379
          name: redis
        command:
          - redis-server
          - "--appendonly"
          - "yes"
          - "--maxmemory"
          - "512mb"
          - "--maxmemory-policy"
          - "allkeys-lru"
        resources:
          requests:
            cpu: 200m
            memory: 256Mi
          limits:
            cpu: 500m
            memory: 512Mi
        volumeMounts:
        - name: redis-storage
          mountPath: /data
      volumes:
      - name: redis-storage
        emptyDir: {}  # OR use PVC for persistence
  volumeClaimTemplates:
  - metadata:
      name: redis-storage
    spec:
      accessModes: ["ReadWriteOnce"]
      resources:
        requests:
          storage: 10Gi
```

---

### Change 4: y-websocket Clustering

**File:** MODIFY `k8s-manifests/05-yjs-deployment.yaml`

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: yjs-server
  namespace: whiteboard
spec:
  replicas: 2  # NOW CAN SCALE HORIZONTALLY
  selector:
    matchLabels:
      app: yjs-server
  template:
    metadata:
      labels:
        app: yjs-server
    spec:
      containers:
      - name: yjs-server
        image: skkhumaini1119/y-websocket:v1.1-redis-cluster  # NEW IMAGE
        ports:
        - containerPort: 1234
        env:
        - name: PORT
          value: "1234"
        - name: REDIS_URL  # NEW
          value: "redis://redis:6379"
        - name: REDIS_CHANNEL  # NEW
          value: "yjs-sync"
        - name: YROOM
          value: "room1"
        resources:
          requests:
            cpu: 250m
            memory: 256Mi
          limits:
            cpu: 1000m
            memory: 1Gi
        livenessProbe:
          tcpSocket:
            port: 1234
          initialDelaySeconds: 30
          periodSeconds: 10
        readinessProbe:
          tcpSocket:
            port: 1234
          initialDelaySeconds: 10
          periodSeconds: 5
```

---

### Change 5: Snapshot CronJob

**File:** NEW `k8s-manifests/11-snapshot-cronjob.yaml`

```yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: yjs-snapshot-export
  namespace: whiteboard
spec:
  schedule: "0 */6 * * *"  # Every 6 hours
  concurrencyPolicy: Forbid
  successfulJobsHistoryLimit: 3
  failedJobsHistoryLimit: 1
  jobTemplate:
    spec:
      backoffLimit: 3
      template:
        spec:
          serviceAccountName: snapshot-exporter
          containers:
          - name: exporter
            image: google/cloud-sdk:alpine
            env:
            - name: GCS_BUCKET
              value: excalidraw-snapshots
            - name: MONGODB_URI
              valueFrom:
                secretKeyRef:
                  name: mongodb-atlas-uri
                  key: uri
            - name: YROOM
              value: room1
            command:
            - /bin/bash
            - -c
            - |
              set -e
              TIMESTAMP=$(date -u +"%Y-%m-%d-%H-%M-%S")
              SNAPSHOT_FILE="/tmp/snapshot-${TIMESTAMP}.json"
              
              # Query MongoDB for current state
              mongosh "$MONGODB_URI" --eval "
                db.drawings.findOne({ room: '$YROOM' }, { state: 1 })
              " > $SNAPSHOT_FILE
              
              # Compress snapshot
              gzip $SNAPSHOT_FILE
              SNAPSHOT_FILE="${SNAPSHOT_FILE}.gz"
              
              # Upload to GCS (uses Workload Identity)
              gsutil cp $SNAPSHOT_FILE gs://${GCS_BUCKET}/snapshots/
              
              # Update metadata in MongoDB
              mongosh "$MONGODB_URI" --eval "
                db.snapshots.insertOne({
                  room: '$YROOM',
                  timestamp: new Date(),
                  gcs_path: 'gs://${GCS_BUCKET}/snapshots/${SNAPSHOT_FILE##*/}',
                  size_bytes: $(stat -f%z $SNAPSHOT_FILE)
                })
              "
              
              echo "Snapshot exported to gs://${GCS_BUCKET}/snapshots/${SNAPSHOT_FILE##*/}"
            resources:
              requests:
                cpu: 100m
                memory: 128Mi
              limits:
                cpu: 500m
                memory: 512Mi
          restartPolicy: OnFailure
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: snapshot-exporter
  namespace: whiteboard
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: snapshot-exporter
rules:
- apiGroups: [""]
  resources: ["secrets"]
  verbs: ["get"]
  resourceNames: ["mongodb-atlas-uri"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: snapshot-exporter
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: snapshot-exporter
subjects:
- kind: ServiceAccount
  name: snapshot-exporter
  namespace: whiteboard
```

---

### Change 6: Workload Identity Setup

**File:** MODIFY `terraform/provider.tf`

```hcl
# ADD Workload Identity configuration

resource "google_service_account" "snapshot_exporter" {
  account_id   = "snapshot-exporter"
  display_name = "Service account for snapshot export CronJob"
}

resource "google_project_iam_member" "snapshot_gcs_admin" {
  project = var.gcp_project_id
  role    = "roles/storage.admin"
  member  = "serviceAccount:${google_service_account.snapshot_exporter.email}"
}

resource "google_iam_workload_identity_binding" "snapshot_exporter" {
  parent              = "projects/${var.gcp_project_id}/locations/global/workloadIdentityPools/my-pool/providers/my-provider"
  service_account     = google_service_account.snapshot_exporter.email
  principal_set       = "attribute.io/gke_namespace/whiteboard"
  principal           = "kubernetes.io/namespace/whiteboard/serviceAccount/snapshot-exporter"
}

# NOTE: Replace my-pool/my-provider with your actual workload identity pool
```

---

### Change 7: Environment Variables & Secrets

**File:** MODIFY App configuration (excalidraw deployment or ConfigMap)

```yaml
# k8s-manifests/09-excalidraw-nginx-config.yaml (add to index.html injection)

<script>
  window.__EXCALIDRAW_YJS_CONFIG__ = {
    wsUrl: "ws://" + window.location.hostname + ":1234",
    redisUrl: "redis://redis:6379",  // NEW - for future use
    mongoUri: "mongodb+srv://..."    // NEW - for future use
  };
</script>
```

---

## Migration Steps (Phase-by-Phase)

### Phase 1: Preparation (Day 1)
```bash
# 1. Set up MongoDB Atlas account
# 2. Create M0 cluster
# 3. Get connection string
# 4. Save to secure location

# 5. Create GCS bucket for snapshots
gsutil mb gs://excalidraw-snapshots

# 6. Create service account
gcloud iam service-accounts create snapshot-exporter \
  --display-name="Snapshot Exporter"

# 7. Grant GCS permissions
gcloud projects add-iam-policy-binding ${GCP_PROJECT} \
  --member="serviceAccount:snapshot-exporter@${GCP_PROJECT}.iam.gserviceaccount.com" \
  --role="roles/storage.admin"
```

### Phase 2: Infrastructure (Day 2)
```bash
# 1. Update Terraform files
# 2. Apply changes
cd terraform
terraform plan -out=phase2.tfplan
terraform apply phase2.tfplan

# 3. Verify load balancer
gcloud compute forwarding-rules describe global-forwarding-rule \
  --global --format="value(IPAddress)"
```

### Phase 3: K8s Deployment (Day 3)
```bash
# 1. Create MongoDB Atlas secret
kubectl apply -f k8s-manifests/02-mongodb-atlas-secret.yaml

# 2. Deploy updated Redis config
kubectl apply -f k8s-manifests/03-redis-statefulset.yaml

# 3. Deploy updated y-websocket
kubectl apply -f k8s-manifests/05-yjs-deployment.yaml

# 4. Deploy snapshot CronJob
kubectl apply -f k8s-manifests/11-snapshot-cronjob.yaml

# 5. Verify all pods running
kubectl get pods -n whiteboard -o wide
```

### Phase 4: Validation (Day 4-5)
```bash
# 1. Test multi-client sync
# 2. Monitor Redis Pub/Sub
redis-cli -n 0 SUBSCRIBE yjs-sync

# 3. Verify snapshots are created
gsutil ls gs://excalidraw-snapshots/snapshots/

# 4. Check MongoDB Atlas
# Manual: via MongoDB Compass or Atlas UI
```

---

## Rollback Plan

If new architecture has issues:

```bash
# Quick rollback to current v1.4.6:

# 1. Revert y-websocket image
kubectl set image deployment/yjs-server -n whiteboard \
  yjs-server=skkhumaini1119/y-websocket:v1.1-fixed

# 2. Scale back to 1 replica
kubectl scale deployment yjs-server -n whiteboard --replicas=1

# 3. Disable snapshot CronJob
kubectl patch cronjob yjs-snapshot-export -n whiteboard \
  -p '{"spec" : {"suspend" : true }}'

# 4. Keep using Cloud SQL for durability (no change needed)
# Current Excalidraw deployment stays unchanged
```

---

## Testing Checklist

### Before Cutover
- [ ] y-websocket pods start and report "Redis connected"
- [ ] Redis Pub/Sub messages flowing (redis-cli MONITOR)
- [ ] Load balancer health checks passing
- [ ] Multi-client sync working across 2+ browsers
- [ ] Snapshot CronJob runs successfully
- [ ] Snapshots appear in GCS bucket
- [ ] Metadata appears in MongoDB Atlas
- [ ] Rollback procedure tested

### During Demo
- [ ] Monitor pod logs for errors
- [ ] Check Redis throughput (`redis-cli INFO stats`)
- [ ] Verify snapshot frequency
- [ ] Test failover (manually kill a yjs-server pod)
- [ ] Measure latency (browser console logs)

---

## Summary of Files Changed

| File | Status | Change |
|------|--------|--------|
| `terraform/load-balancer.tf` | NEW | GCP HTTP Load Balancer |
| `terraform/network.tf` | MODIFY | Firewall rules for MongoDB + LB health checks |
| `terraform/mongodb-atlas.tf` | NEW | MongoDB Atlas reference (mostly manual) |
| `k8s-manifests/02-mongodb-atlas-secret.yaml` | NEW | MongoDB connection secret |
| `k8s-manifests/03-redis-statefulset.yaml` | MODIFY | Add Pub/Sub config |
| `k8s-manifests/05-yjs-deployment.yaml` | MODIFY | Add Redis env vars, scale to 2+ replicas |
| `k8s-manifests/11-snapshot-cronjob.yaml` | NEW | Snapshot export CronJob |
| `k8s-manifests/snapshot-exporter-sa.yaml` | NEW | Service account for CronJob |
| All others | UNCHANGED | No modifications needed |

---

**Total Changes:** ~8 files (mostly new files, a few modifications)  
**Risk Level:** Low-Medium (new services added, but core system unchanged)  
**Estimated Setup Time:** 2-3 days  
**Estimated Testing Time:** 1 day
