INFRA CHANGELOG & LOCKS
========================

Scope
-----
This document captures all changes and fixes applied to the collaborative-whiteboard deployment (v1.4.6 stable), and provides a practical locking / snapshotting plan to avoid hours of debugging on future infra setups. Place this file at the root of the repo and follow the lock steps after any confirmed working release.

Executive summary
-----------------
- Stabilized application to version: Excalidraw UI `v1.4.6` and y-websocket `v1.4-fixed2` (rebuilt to bind 0.0.0.0). Redis `7-alpine` statefulset used.
- Kubernetes changes: pinned images, removed Yjs HPA, fixed NetworkPolicy namespace selector, created NodePort for Traefik mapping, added ClusterIP service for `yjs-server`.
- GCP changes: backend instance-group named port aligned to Traefik nodePort `31853`; health-check updated to probe `31853`; firewall rule `private-cloud-allow-nodeport` updated to allow `31853`.
- Terraform: temporarily commented Workload Identity IAM binding (identity pool missing) to allow plan/apply to succeed.

Why lock manifests and infra
---------------------------
- Reproducible deployments: pinned artifacts (image tags/digests) and snapshots make rollbacks and reproductions deterministic.
- Faster recovery: snapshot + documented fixes let you redeploy a known-good state without debugging cloud and networking issues again.
- Safer CI/CD: CI can automatically verify digests and prevent drifting images from being deployed unknowingly.

Files changed (representative)
------------------------------
- `k8s-manifests/03-redis-statefulset.yaml` — Redis statefulset (unchanged, included for completeness)
- `k8s-manifests/05-yjs-deployment.yaml` — updated image to `skkhumaini1119/y-websocket:v1.4-fixed2` and confirmed single replica
- `k8s-manifests/06-excalidraw-deployment.yaml` — Excalidraw UI image pinned to `skkhumaini1119/excalidraw-yjs:v1.4.6`, NodePort service present
- `k8s-manifests/07-network-policy.yaml` — fixed namespaceSelector label to `kubernetes.io/metadata.name: kube-system` and added DNS egress rules
- `terraform/gcs.tf` — commented out Workload Identity IAM binding until identity pool exists
- `Dockerfile.yjs-rebuild` — new Dockerfile that builds a y-websocket server binding to `0.0.0.0` and exposes `/health`

High-level timeline of fixes
----------------------------
1. Client fixes: removed debounced sync, fixed Yjs transact calls, cleared stale IndexedDB handling.
2. Server fixes: pinned y-websocket version and rebuilt a custom image (`v1.4-fixed2`) that binds 0.0.0.0 and exposes a `/health` HTTP endpoint.
3. K8s fixes: removed Yjs HPA, pinned images, corrected NetworkPolicy namespace label, created NodePort for Traefik.
4. GCP fixes: updated instance group named port to `traefik-nodeport:31853`, updated LB health-check to `31853`, updated firewall to allow `31853`.
5. Terraform: commented workload-identity binding to continue provisioning; document created to reintroduce Workload Identity when pool exists.

Immediate recommendations to "lock" your infra
---------------------------------------------
1. Pin images to immutable digests (sha256):
   - For each container image in your manifests, replace `image: repository/name:tag` with `image: repository/name@sha256:<digest>`.
   - Get digest example:
     ```bash
     docker pull skkhumaini1119/y-websocket:v1.4-fixed2
     docker inspect --format='{{index .RepoDigests 0}}' skkhumaini1119/y-websocket:v1.4-fixed2
     # or for gcr
     gcloud container images describe gcr.io/PROJECT_ID/y-websocket:v1.4-fixed2 --format='get(image_summary.fully_qualified_digest)'
     ```
   - Commit the digest-pinned manifests to `k8s-manifests/locked/`.

2. Snapshot and sign manifests (recommended):
   - Create a snapshot tarball of all k8s manifests, terraform, and scripts and store it in a versioned path (GCS / S3 / Git tag).
   - Use the provided script `scripts/snapshot_manifests.sh` to create dated snapshots automatically.

3. Terraform locking and provider pinning:
   - Add explicit provider versions in `versions.tf`:
     ```hcl
     terraform {
       required_version = ">= 1.4.0"
       required_providers {
         google = {
           source = "hashicorp/google"
           version = "~> 4.0"
         }
       }
       backend "gcs" { }
     }
     ```
   - Use `terraform init -upgrade=false` and rely on the `.terraform.lock.hcl` file. Commit the lock file.

4. Keep health checks & firewall rules in code:
   - Ensure LB health checks, firewall rules, and named-ports are codified in Terraform (or documented in the snapshot) so new infra gets the same config.

5. CI gating and canary rollouts:
   - Add a CI job that: builds images, records digests, runs `kubectl apply --server-dry-run`, deploys to a staging cluster, runs smoke tests (health + websocket), then flips production.

6. Document rollback steps and emergency contacts:
   - Include quick commands to revert to the last snapshot (e.g., `kubectl apply -f infra-locks/manifests-2025-12-03.tar.gz` after untarring).

How to reproduce the current working setup (quick)
-------------------------------------------------
1. Clone this repo and checkout `main` (or the commit where these files were committed).
2. Create a manifest snapshot and pin images (recommended):
   ```bash
   ./scripts/snapshot_manifests.sh
   # get image digests and update the manifests in k8s-manifests/locked/
   ```
3. Apply Terraform (if using terraform):
   ```bash
   cd terraform
   terraform init
   terraform apply
   ```
4. Deploy the manifests:
   ```bash
   kubectl -n whiteboard apply -f k8s-manifests/locked/
   ```
5. Verify:
   - LB health check -> `gcloud compute health-checks describe private-cloud-http-health --global`
   - Backend health -> `gcloud compute backend-services get-health private-cloud-http-backend --global`
   - App -> open `http://<EXTERNAL_IP>/` and confirm `ws://<EXTERNAL_IP>/ws/room1` connects.

Scripts included
----------------
- `scripts/snapshot_manifests.sh` — creates a timestamped tar.gz of `k8s-manifests/`, `terraform/`, and other infra-related files and writes a checklist file with changed files.

Rollback and emergency steps
----------------------------
- If a change breaks the system, restore the last snapshot and redeploy the same images:
  1. ``tar xzf infra-locks/manifests-YYYYMMDD-HHMMSS.tar.gz -C /tmp``
  2. ``kubectl -n whiteboard apply -f /tmp/k8s-manifests/locked/``
  3. If LB health check mismatch recurs: ensure instance-group named-ports and backend health-check `port` matches Traefik nodePort.

Open items / TODOs
------------------
- Reintroduce Workload Identity binding in `terraform/gcs.tf` after creating an Identity Pool. (See comment in file `terraform/gcs.tf`)
- Replace image tags with digest-pinned images and commit to `k8s-manifests/locked/`.
- Add CI pipeline steps for automated builds, digests, and staging gates.

Contact & metadata
------------------
- Snapshot created at: 2025-12-03 (this file)
- Maintainer: Khumaini (repo owner)


