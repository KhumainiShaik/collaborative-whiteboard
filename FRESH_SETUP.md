# Fresh Infrastructure Setup & Debugging Guide

**Purpose:** Quick reference for deploying a fresh instance and avoiding known pitfalls.

## Prerequisites
- k3s cluster running (GCP Compute Engine or similar)
- `kubectl`, `gcloud`, `helm` installed locally
- kubeconfig configured to target cluster
- Terraform for GCP resources (if using snapshots/GCS)

---

## Phase 1: Core Workload Deployment

### 1.1 Namespace & Secrets
```bash
kubectl apply -f k8s-manifests/00-namespace.yaml
kubectl apply -f k8s-manifests/01-mongodb-secret.yaml
```

### 1.2 Stateful Components
```bash
kubectl apply -f k8s-manifests/03-redis-statefulset.yaml
```
**Wait for Redis pod to be Ready:**
```bash
kubectl -n whiteboard wait --for=condition=Ready pod -l app=redis --timeout=2m
```

### 1.3 Application Deployments
```bash
kubectl apply -f k8s-manifests/06-excalidraw-deployment.yaml
kubectl apply -f k8s-manifests/05-yjs-deployment.yaml
```

**Verify:**
```bash
kubectl -n whiteboard get pods
# Expected: excalidraw-ui, yjs-server in Running state
```

---

## Phase 2: Networking & Ingress

### 2.1 Network Policy (Optional but recommended)
```bash
kubectl apply -f k8s-manifests/07-network-policy.yaml
```

### 2.2 Nginx Ingress Controller
```bash
kubectl apply -f k8s-manifests/11-nginx-ingress.yaml
```

**Wait for ingress controller to be ready:**
```bash
kubectl -n ingress-nginx wait --for=condition=Ready pod -l app.kubernetes.io/name=ingress-nginx --timeout=2m
```

### 2.3 Ingress Rules
```bash
kubectl apply -f k8s-manifests/08-ingress-tls.yaml
kubectl apply -f k8s-manifests/16-grafana-ingress.yaml
```

**Verify ingress is provisioned:**
```bash
kubectl get ingress -n whiteboard
kubectl get ingress -n monitoring
```

---

## Phase 3: Autoscaling & Metrics Server

### 3.1 Metrics Server (Required for HPA)
```bash
kubectl apply -f k8s-manifests/15-metrics-server.yaml
```

**Verify metrics available:**
```bash
kubectl get nodes --show-metrics  # May take 1-2 mins
```

### 3.2 Horizontal Pod Autoscaling
```bash
kubectl apply -f k8s-manifests/14-hpa.yaml
```

**Check HPA status:**
```bash
kubectl -n whiteboard get hpa
# excalidraw-ui-hpa should show TARGETS (cpu/memory utilization)
```

---

## Phase 4: Monitoring Stack

### 4.1 Prometheus
```bash
kubectl apply -f k8s-manifests/12-prometheus.yaml
```

### 4.2 Grafana
```bash
kubectl apply -f k8s-manifests/13-grafana.yaml
```

**Access Grafana:**
```
http://<LOAD_BALANCER_IP>/grafana/
# Default: admin/admin
```

### 4.3 Exporters (Metrics Collection)

**kube-state-metrics (pod state metrics):**
```bash
kubectl apply -f k8s-manifests/ksm-rbac.yaml
# kube-state-metrics deployment is auto-created by Prometheus discovery
```

**node-exporter (node-level metrics):**
```bash
kubectl apply -f k8s-manifests/15-node-exporter.yaml
```

**cAdvisor (container-level metrics):**
```bash
kubectl apply -f k8s-manifests/16-cadvisor.yaml
```

---

## Known Issues & Fixes

### Issue 1: Grafana shows "Data source not found"
**Cause:** Prometheus data source not registered in Grafana.

**Fix:**
1. In Grafana UI: Connections → Data Sources → Add Prometheus
2. URL: `http://prometheus.monitoring.svc.cluster.local:9090`
3. Save & test

### Issue 2: HPA shows "unknown" for metrics
**Cause:** Metrics Server not ready or not collecting metrics.

**Fix:**
```bash
# Force metrics to be collected
kubectl top nodes
kubectl top pods -n whiteboard

# If still failing, restart metrics-server
kubectl -n kube-system rollout restart deployment/metrics-server
```

### Issue 3: cAdvisor pods CrashLoopBackOff
**Cause:** Invalid storage driver argument or missing serviceaccount mount.

**Fix:** Already patched in current `16-cadvisor.yaml`:
- `automountServiceAccountToken: false` (disables projected mount that causes read-only FS error)
- Removed invalid `--storage_driver=memory` argument

### Issue 4: Prometheus targets show "down" (HTTP 404 at /metrics)
**Cause:** Application pods don't expose Prometheus endpoints.

**Fix:** This is expected for excalidraw-ui and yjs-server. Panels use kube-state-metrics and node-exporter instead (see OBSERVABILITY.md).

### Issue 5: Yjs sync issues after HPA scale-up
**Cause:** In-memory room state lost when pod scales; new pod joins with empty state.

**Fix:** Already in place:
- `k8s-manifests/14-hpa.yaml`: yjs HPA set to `minReplicas: 1` (no autoscale, keeps state singleton)
- `k8s-manifests/05-yjs-deployment.yaml`: Service has `sessionAffinity: ClientIP` (sticky sessions)

---

## Snapshot CronJob (Optional)

If using GCS snapshot export:

```bash
terraform apply -f terraform/gcs.tf
kubectl apply -f k8s-manifests/10-snapshot-cronjob.yaml
```

---

## Verification Checklist

- [ ] All pods in `whiteboard` namespace are Running
- [ ] Ingress has an external IP assigned
- [ ] Grafana accessible at `/grafana/` path
- [ ] Prometheus targets show at least: kube-state-metrics, node-exporter, cAdvisor (status "up")
- [ ] Grafana dashboard imports with no errors
- [ ] HPA shows current/desired replicas for excalidraw-ui
- [ ] yjs deployment has 1 replica (not autoscaled)

---

## Rolling Back

To remove all resources:
```bash
kubectl delete namespace whiteboard
kubectl delete namespace monitoring
kubectl delete namespace ingress-nginx
```

