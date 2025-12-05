# Kubernetes Monitoring & HPA Setup - Documentation

## Quick Navigation

This workspace contains comprehensive documentation for a production-grade Kubernetes monitoring and autoscaling setup. Choose the document that matches your need:

### 📋 [FRESH_SETUP.md](./FRESH_SETUP.md)
**For:** Setting up from scratch or debugging deployment issues.

**Contains:**
- 6-phase deployment walkthrough with verification at each step
- Common issues and fixes (Grafana datasource, cAdvisor crashes, etc.)
- Manual verification commands
- Troubleshooting checklist

**Start here if:** You're deploying the cluster for the first time or need to understand what each manifest does.

---

### 🔍 [OBSERVABILITY.md](./OBSERVABILITY.md)
**For:** Understanding monitoring architecture and querying metrics.

**Contains:**
- System architecture (Prometheus → kube-state-metrics → Grafana)
- Component reference (each exporter's purpose and metrics)
- PromQL patterns (CPU, memory, network, pod count queries)
- Troubleshooting: missing data, cardinality errors, metric discovery

**Start here if:** You need to debug "no data in dashboard," add new panels, or understand metric sources.

---

### 🎯 [TASK4_DEMO.md](./TASK4_DEMO.md)
**For:** Running a live demo of HPA, Yjs sync, and monitoring.

**Contains:**
- Step-by-step demo walkthrough (~15 min)
- Load generation, HPA scaling observation, dashboard live view
- Yjs synchronization verification
- Talk track and Q&A topics
- Success criteria and copy-paste commands

**Start here if:** You're presenting the system or testing autoscaling behavior.

---

## Files Reference

### Kubernetes Manifests (`k8s-manifests/`)
Essential manifests for this setup (listed in deployment order):

| Manifest | Purpose | Status |
|----------|---------|--------|
| `00-namespace.yaml` | Create whiteboard namespace | ✅ Applied |
| `01-mongodb-secret.yaml` | MongoDB credentials | ✅ Applied |
| `02-kcc-pubsub.yaml` | GCP Pub/Sub integration | ✅ Applied |
| `03-kcc-gcs.yaml` | GCP GCS snapshot support | ✅ Applied |
| `04-k8s-serviceaccount.yaml` | Service account for workloads | ✅ Applied |
| `05-yjs-deployment.yaml` | Yjs server (WebSocket sync) | ✅ Applied |
| `06-excalidraw-deployment.yaml` | Excalidraw UI (frontend) | ✅ Applied |
| `07-network-policy.yaml` | Pod network isolation | ✅ Applied |
| `08-ingress-tls.yaml` | HTTPS ingress rules | ✅ Applied |
| `11-nginx-ingress.yaml` | NGINX ingress controller | ✅ Applied |
| `12-prometheus.yaml` | Prometheus scraper + config | ✅ Applied |
| `13-grafana.yaml` | Grafana UI + datasource config | ✅ Applied |
| `14-hpa.yaml` | HPA resources (autoscaling) | ✅ Applied |
| `15-metrics-server.yaml` | Metrics server (HPA data) | ✅ Applied |
| `15-node-exporter.yaml` | Node-exporter DaemonSet | ✅ Applied |
| `16-cadvisor.yaml` | cAdvisor DaemonSet | ✅ Applied |
| `16-grafana-ingress.yaml` | Grafana ingress rule | ✅ Applied |
| `ksm-rbac.yaml` | kube-state-metrics + RBAC | ✅ Applied |

**Note:** Redis StatefulSet and other prerequisites are included in the core manifests. See FRESH_SETUP.md for deployment order.

---

## Architecture Summary

```
┌──────────────────────────────────────────────────────────┐
│                    External Load Balancer                 │
│                   (GCP HTTP(S) LB)                        │
│                       ↓                                   │
│         http://<IP>/ (excalidraw app)                    │
│         http://<IP>/grafana/ (monitoring)                │
│         http://<IP>/api/ (backend API)                   │
└──────────────────────────────────────────────────────────┘
                       ↓
      ┌────────────────────────────────────┐
      │   NGINX Ingress Controller         │
      │   (routing, TLS termination)       │
      └────────────────────────────────────┘
           ↙                    ↓                  ↖
    ┌──────────────┐    ┌─────────────────┐    ┌─────────────┐
    │ excalidraw-ui│    │  yjs-server     │    │   Grafana   │
    │ (3-8 replicas)    │  (1 replica)    │    │  (frontend) │
    │  (HPA: CPU60%)    │  (sessionAffinity)  │  (Prometheus)│
    └──────────────┘    └─────────────────┘    └─────────────┘
           ↓                    ↓
    ┌─────────────────────────────────┐
    │       Service Mesh (optional)   │
    │  (network policies enforced)    │
    └─────────────────────────────────┘
           ↓
    ┌──────────────────────────────────┐
    │  Monitoring Stack                │
    │  ┌──────────────────────────────┐│
    │  │  Prometheus (metrics store)  ││
    │  └──────────────────────────────┘│
    │         ↙        ↙       ↙       │
    │    kube-state-  node-     cAdvisor
    │    metrics      exporter   (containers)
    │  (pod/HPA info) (node info)(limited)
    └──────────────────────────────────┘
```

**Key insight:** Metrics flow from exporters → Prometheus → Grafana. Each component is independently verifiable.

---

## Quick Troubleshooting

### "Grafana shows no data"
→ See [OBSERVABILITY.md: Troubleshooting](./OBSERVABILITY.md#troubleshooting) → "Dashboard panels empty" section

### "Pods not scaling up"
→ See [FRESH_SETUP.md: Known Issues](./FRESH_SETUP.md#known-issues) → "HPA metrics unhealthy" section

### "Yjs room state lost after scale"
→ See [FRESH_SETUP.md: Phase 2 Fix](./FRESH_SETUP.md#phase-2-yjs-sync-stability-fixed) → Session affinity explanation

### "How do I add a new dashboard panel?"
→ See [OBSERVABILITY.md: PromQL Patterns](./OBSERVABILITY.md#promql-patterns) for query examples

---

## Deployment Sequence

If starting from scratch:

```bash
# 1. Prepare cluster (see FRESH_SETUP.md Phase 1)
kubectl apply -f k8s-manifests/00-namespace.yaml
kubectl apply -f k8s-manifests/01-mongodb-secret.yaml
# ... (other core resources)

# 2. Deploy workloads (see FRESH_SETUP.md Phase 2-3)
kubectl apply -f k8s-manifests/05-yjs-deployment.yaml
kubectl apply -f k8s-manifests/06-excalidraw-deployment.yaml

# 3. Setup monitoring (see FRESH_SETUP.md Phase 4-5)
kubectl apply -f k8s-manifests/12-prometheus.yaml
kubectl apply -f k8s-manifests/13-grafana.yaml
kubectl apply -f k8s-manifests/ksm-rbac.yaml
kubectl apply -f k8s-manifests/15-node-exporter.yaml
kubectl apply -f k8s-manifests/16-cadvisor.yaml

# 4. Configure HPA (see FRESH_SETUP.md Phase 6)
kubectl apply -f k8s-manifests/14-hpa.yaml

# 5. Verify (see FRESH_SETUP.md Verification)
kubectl get pods -n whiteboard -o wide
kubectl get hpa -n whiteboard
```

For detailed steps with verification, see **FRESH_SETUP.md**.

---

## Key Configuration Highlights

### HPA (Horizontal Pod Autoscaler)
- **excalidraw-ui:** minReplicas=3, maxReplicas=8, CPU 60%, Memory 75%
- **yjs-server:** minReplicas=1, maxReplicas=1 (no autoscale; singleton design)

**Why?** Yjs maintains in-memory room state; scaling loses state unless persisted to Redis. For this demo, we keep it singleton.

### Session Affinity (yjs-service)
- `sessionAffinity: ClientIP` ensures client requests route to same pod
- Prevents transient connections if pod flaps

### Grafana Config
- Served at `/grafana/` subdirectory (not root)
- Configured via `GF_SERVER_ROOT_URL` + `GF_SERVER_SERVE_FROM_SUB_PATH`
- Datasource: Prometheus (in-cluster at `http://prometheus-service.monitoring:9090`)

### Prometheus Scraping
- 15-second interval
- Service discovery: Kubernetes SD
- Targets: all pods with `prometheus.io/scrape: "true"` annotation

---

## Verification Checklist

Before running the demo:

- [ ] All pods running: `kubectl get pods -n whiteboard`
- [ ] HPA active: `kubectl get hpa -n whiteboard`
- [ ] Ingress has external IP: `kubectl get ingress -n whiteboard`
- [ ] Grafana accessible: `curl -I http://<IP>/grafana/`
- [ ] Prometheus targets up: Check Prometheus UI or Grafana datasource
- [ ] Dashboard panels have data: Open Grafana → Dashboard → Excalidraw System Monitoring

---

## Next Steps

1. **Deploy the cluster:** Follow FRESH_SETUP.md
2. **Understand metrics:** Read OBSERVABILITY.md
3. **Run the demo:** Follow TASK4_DEMO.md
4. **Extend monitoring:** Add custom panels or exporters as needed

---

## Support & Additional Context

- **Cluster:** k3s on GCP (3 nodes: 1 control, 2 workers)
- **Ingress:** NGINX controller behind HTTP Load Balancer
- **Namespace:** `whiteboard` (all workloads), `monitoring` (Prometheus/exporters), `ingress-nginx` (ingress)
- **Git:** Original Excalidraw repo + custom YJS integration + K8s manifests

For detailed architecture, component interactions, and troubleshooting, see the individual docs.
