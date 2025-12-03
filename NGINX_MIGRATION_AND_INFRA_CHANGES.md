# NGINX Ingress Migration & Infra Changes

Summary of actions performed during migration to the "professional" architecture (NGINX ingress, no-Helm), and notes for new infra setup.

Date: 2025-12-03

Key changes performed

- Rebuilt `y-websocket` image to bind 0.0.0.0 and expose `/health` endpoint. Image tag: `skkhumaini1119/y-websocket:v1.4-fixed2`.
- Replaced Traefik with a no‑Helm `ingress-nginx` deployment using manifests in `k8s-manifests/11-nginx-ingress.yaml` (Service is `NodePort`, ports: 80->31853, 443->30306).
- Created `IngressClass: nginx` and updated Ingress manifests to use `ingressClassName: nginx`.
- Updated GCP instance-group named-port and health-check to target NodePort for HTTP (31853).
- Added RBAC required for the nginx controller (ServiceAccount, ClusterRole, ClusterRoleBinding in `11-nginx-ingress.yaml`).
- Patched `ingress-nginx` readinessProbe to `/healthz` to ensure controller Pod readiness.

Outstanding / follow-ups

- NodePort DNAT for NodePort `31853` is not present on the node kernel iptables (KUBE-NODEPORTS/KUBE-SERVICES missing DNAT). This prevents GCP backend health checks from marking backends healthy; external LB returned intermittent 502.
- Need to investigate `k3s`/kube-proxy behaviour and ensure nodePort rules are programmed on all nodes.
- Terraform: restore Workload Identity and lock image tags in IaC for reproducibility.

Checks to perform after migration

- Node-level: verify `iptables -t nat -L KUBE-NODEPORTS` contains entries for 31853 on every node.
- Controller: `kubectl -n kube-system get pods` -> check nginx controller `Ready` and `logs` for proxying errors.
- App: `kubectl -n whiteboard get pods` -> ensure `yjs-server`, `redis`, `excalidraw-ui` pods are `Ready` and healthy.
- Redis: verify `StatefulSet` replicas, persistent volumes, and `redis` readiness; check `redis` pubsub messages during a collaboration session.
- Mongo: verify `excalidraw` backend connects to MongoDB Atlas (check `MONGO_URI` env var and pod logs for connection errors).
- Snapshots: verify CronJob configuration for snapshots, service account/keys for GCS upload, and recent job logs.

How to remediate nodePort programming issues (short checklist)

1. Check `k3s` / `k3s-agent` logs on each node for errors while creating services (journalctl -u k3s[-agent]).
2. Confirm kube-proxy mode (iptables vs ipvs) in k3s config; ensure required kernel modules are present.
3. Restart `k3s-agent` on workers and `k3s` on server to force re-programming (disruptive).
4. If still missing, inspect for taints/daemonset issues or iptables conflicts from host-level firewall.

Contact / ownership

- Primary operator: khumaini (repo owner)
- For production rollout: follow the checklist above and perform a maintenance window for disruptive node restarts.

---

(Generated automatically by the migration run; keep this file in a feature branch and expand with exact command outputs before merging.)
