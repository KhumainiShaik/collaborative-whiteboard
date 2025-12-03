# master Branch: Setup & Operations Guide

**Branch:** `master`  
**Status:** Reference baseline for comparison  
**Use Case:** Compare with nginx-migration branch

---

## Overview

The master branch contains the earlier iteration with Traefik ingress. It serves as a reference point for understanding the migration to NGINX.

---

## Key Differences from nginx-migration

| Aspect | master | nginx-migration |
|--------|--------|-----------------|
| **Ingress** | Traefik | NGINX |
| **Helm** | May use Helm | No Helm (manual YAML) |
| **CRDT Server** | Original binding | Fixed (0.0.0.0) |
| **GCS IAM** | Not configured | Fixed (roles/storage.objectAdmin) |
| **NodePort** | 30080 or higher | 31853 (mapped to LB) |
| **Complexity** | Higher | Simplified |

---

## Quick Setup (Historical Reference)

If reverting or comparing, use master branch:

```bash
git checkout master
git pull origin master

# Review manifests in k8s-manifests/
# Note: Traefik integration (if present)
```

---

## Why nginx-migration is Better

✅ Cleaner YAML (no Helm)  
✅ Explicit ingress routes  
✅ Fixed y-websocket binding  
✅ GCS IAM permissions  
✅ Easier to troubleshoot  
✅ Minimal external dependencies  

---

## When to Use master

1. **Audit trail:** Check original design decisions
2. **Comparison:** Understand what changed
3. **Rollback:** If nginx-migration has issues (unlikely)
4. **Documentation:** Reference older setup

---

## Migration Path (master → nginx-migration)

If on master and want to switch:

```bash
# Backup current state
kubectl -n whiteboard get all -o yaml > backup.yaml

# Switch branch
git checkout nginx-migration

# Reapply manifests
kubectl apply -f k8s-manifests/

# Verify
kubectl -n whiteboard get pods
```

---

**Recommendation:** Use `nginx-migration` branch for all new deployments. Use `master` for reference only.
