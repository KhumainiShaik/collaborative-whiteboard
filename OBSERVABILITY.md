# Observability Setup: Prometheus, Grafana & Exporters

**Purpose:** Detailed guide to monitoring stack. Covers data sources, dashboards, and troubleshooting.

---

## Architecture

```
┌──────────────────────────────────────┐
│     Prometheus (scraper)              │
│  - kubernetes_sd (pod discovery)      │
│  - Scrapes at 15s intervals           │
└─────────────┬──────────────────────────┘
              │
              ├─→ kube-state-metrics:8080
              │   (pod state, resource requests)
              │
              ├─→ node-exporter:9100 (x3 nodes)
              │   (CPU, memory, disk, network)
              │
              ├─→ cAdvisor:8080 (x3 nodes)
              │   (container CPU, memory, network)
              │
              └─→ Grafana's Prometheus datasource
                  (PromQL queries → panels)
```

---

## Component Details

### 1. Prometheus (`k8s-manifests/12-prometheus.yaml`)

**Purpose:** Time-series metrics database; scrapes exporters.

**Key Config:**
- Namespace: `monitoring`
- Service: `http://prometheus.monitoring.svc.cluster.local:9090`
- Scrape interval: 15 seconds
- Storage: In-memory (~15GB default, configurable)

**Access locally:**
```bash
kubectl -n monitoring port-forward svc/prometheus 9090:9090
# Browse: http://127.0.0.1:9090
```

**Check targets:**
Visit http://127.0.0.1:9090/api/v1/targets

Expected targets (all status "up"):
- kube-state-metrics:8080
- node-exporter:9100 (one per node)
- cAdvisor:8080 (one per node)

---

### 2. kube-state-metrics

**Purpose:** Exposes Kubernetes object state (pods, deployments, nodes) as metrics.

**Deployment:**
```bash
kubectl apply -f k8s-manifests/ksm-rbac.yaml
# kube-state-metrics deployment auto-created if using Prometheus service discovery
```

**Key Metrics Available:**
- `kube_pod_info`: pod name, namespace, node, uid
- `kube_pod_container_resource_requests`: CPU/memory requests per container
- `kube_deployment_status_replicas`: deployment replica counts
- `kube_horizontalpodautoscaler_status_current_replicas`: current HPA replicas

**Example Query:**
```promql
# Count pods in whiteboard namespace
count(kube_pod_info{namespace="whiteboard"})

# CPU requests for excalidraw-ui pods
sum by (pod) (kube_pod_container_resource_requests{
  namespace="whiteboard",
  resource="cpu",
  pod=~"excalidraw-ui.*"
})
```

---

### 3. node-exporter (`k8s-manifests/15-node-exporter.yaml`)

**Purpose:** Exports node-level (Linux) metrics: CPU, memory, disk, network, filesystem.

**Deployment:**
```bash
kubectl apply -f k8s-manifests/15-node-exporter.yaml
```

**Key Metrics:**
- `node_cpu_seconds_total`: CPU time per core
- `node_memory_MemAvailable_bytes`, `node_memory_MemTotal_bytes`
- `node_disk_read_bytes_total`, `node_disk_write_bytes_total`
- `node_network_receive_bytes_total`, `node_network_transmit_bytes_total`

**Example Query:**
```promql
# Network receive rate across all nodes
rate(node_network_receive_bytes_total[5m])

# Memory available % per node
100 * (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes)
```

---

### 4. cAdvisor (`k8s-manifests/16-cadvisor.yaml`)

**Purpose:** Container-level resource metrics from the kubelet/containerd.

**Deployment:**
```bash
kubectl apply -f k8s-manifests/16-cadvisor.yaml
```

**Key Metrics:**
- `container_cpu_usage_seconds_total`: cumulative CPU seconds per container
- `container_memory_usage_bytes`: memory usage per container
- `container_network_receive_bytes_total`, `container_network_transmit_bytes_total`
- `container_fs_usage_bytes`: filesystem usage

**Known Limitation:**
- cAdvisor only exposes metrics for containers on the node it runs on (DaemonSet)
- Container metrics lack `pod`/`namespace` labels → must join with `kube_pod_container_info` or use container ID
- For most dashboards, kube-state-metrics + node-exporter are sufficient

---

### 5. Grafana (`k8s-manifests/13-grafana.yaml`)

**Purpose:** Dashboard and alerting UI.

**Deployment:**
```bash
kubectl apply -f k8s-manifests/13-grafana.yaml
kubectl apply -f k8s-manifests/16-grafana-ingress.yaml
```

**Access:**
```
http://<LOAD_BALANCER_IP>/grafana/
Credentials: admin/admin (change on first login)
```

**Configuration:**
- GF_SERVER_ROOT_URL: `http://34.49.56.133/grafana`
- GF_SERVER_SERVE_FROM_SUB_PATH: `true` (serves under `/grafana/` path)
- Service: ClusterIP (fronted by ingress, not NodePort)

---

## Dashboard Import

### Grafana Dashboard JSON (`grafana-dashboard.json`)

**Location:** Workspace root

**Panels (Current Implementation):**
1. **Running Pods**: `count(kube_pod_info{namespace="whiteboard"})` — shows total pods
2. **Yjs Server Replicas**: `count(kube_pod_info{pod=~"yjs-server.*"})` — should be 1
3. **Excalidraw UI Replicas**: `count(kube_pod_info{pod=~"excalidraw-ui.*"})` — shows HPA autoscale count
4. **Pod CPU Requests**: `sum by (pod) (kube_pod_container_resource_requests{resource="cpu"})` — CPU cores requested
5. **Pod Memory Requests**: `sum by (pod) (kube_pod_container_resource_requests{resource="memory"})` — memory requested
6. **Node Network RX/TX**: `rate(node_network_receive/transmit_bytes_total[5m])` — network rates per interface

**Import Steps:**
1. Grafana UI → Create → Import
2. Paste contents of `grafana-dashboard.json`
3. Select Prometheus as datasource
4. Click Import
5. Panels should populate with data within 1 minute

---

## Common PromQL Patterns

### Pod/Namespace Queries
```promql
# All pods in whiteboard
kube_pod_info{namespace="whiteboard"}

# excalidraw-ui pods only
kube_pod_info{namespace="whiteboard", pod=~"excalidraw-ui.*"}

# Count by status
count by (pod_phase)(kube_pod_status_phase{namespace="whiteboard"})
```

### Resource Usage
```promql
# Pod CPU requests vs limits
kube_pod_container_resource_requests{resource="cpu"}
kube_pod_container_resource_limits{resource="cpu"}

# Memory usage (from node metrics as aggregate)
rate(node_memory_MemAvailable_bytes[5m])
```

### Deployment Health
```promql
# Deployment replica status
kube_deployment_status_replicas{namespace="whiteboard"}
kube_deployment_status_replicas_available{namespace="whiteboard"}
kube_deployment_status_replicas_ready{namespace="whiteboard"}

# Ready vs desired
kube_deployment_status_replicas_ready / kube_deployment_spec_replicas
```

### HPA Status
```promql
# Current HPA metrics
kube_horizontalpodautoscaler_status_current_replicas
kube_horizontalpodautoscaler_status_desired_replicas
kube_horizontalpodautoscaler_info
```

---

## Troubleshooting

### Problem: Grafana shows "No data" for panel
**Solution:**
1. Go to Dashboard → Panel → Edit
2. Click "Explore" to test query in Prometheus directly
3. Check time range (default "last 6 hours"); may need data first
4. Verify metric exists: `SELECT * FROM <metric_name>` in Explore

### Problem: Prometheus targets show "down"
**Solution:**
1. Check target logs: `kubectl logs -n monitoring <pod>`
2. Common causes:
   - Application doesn't expose `/metrics` endpoint (expected for excalidraw-ui)
   - Port mismatch in kubernetes_sd scrape config
   - Pod not annotated with `prometheus.io/scrape: "true"`

### Problem: High memory usage in Prometheus
**Solution:**
1. Reduce retention: Edit `k8s-manifests/12-prometheus.yaml` env `PROMETHEUS_STORAGE_TSDB_RETENTION_TIME`
2. Increase pod resource limits
3. Consider external storage (Thanos, remote write)

### Problem: Metrics missing after pod restart
**Solution:**
- Prometheus stores only in-memory; restart clears data
- Implement persistent storage via PVC (see k8s-manifests/12-prometheus.yaml comments)

---

## Manual Metric Verification

```bash
# Port-forward Prometheus
kubectl -n monitoring port-forward svc/prometheus 9090:9090 &

# Query via HTTP API
curl 'http://127.0.0.1:9090/api/v1/query?query=kube_pod_info{namespace="whiteboard"}' | jq .

# List available metrics
curl 'http://127.0.0.1:9090/api/v1/label/__name__/values' | jq . | grep -i pod | head -20

# Kill port-forward
pkill -f 'kubectl -n monitoring port-forward'
```

---

## Next Steps

- Set up alerting rules in Prometheus (alert on pod crash, high memory, etc.)
- Configure Grafana notifications (Slack, email)
- Add custom dashboards for application-specific metrics (if needed)
- Enable persistent storage for Prometheus (not recommended for demo, but needed for production)

