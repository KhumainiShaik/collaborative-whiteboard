#!/bin/bash
set -e
NAMESPACE=monitoring

kubectl -n "$NAMESPACE" get svc || true
kubectl -n "$NAMESPACE" get pods -o wide || true

kubectl -n "$NAMESPACE" run prom-check-2 --image=curlimages/curl --restart=Never --command -- sleep 300 >/dev/null 2>&1 || true
sleep 1

echo '--- PROMETHEUS TARGETS ---'
kubectl -n "$NAMESPACE" exec prom-check-2 -- curl -sS http://prometheus:9090/api/v1/targets || true

echo

echo '--- PROMETHEUS CONFIG STATUS ---'
kubectl -n "$NAMESPACE" exec prom-check-2 -- curl -sS http://prometheus:9090/api/v1/status/config || true

kubectl -n "$NAMESPACE" delete pod prom-check-2 --ignore-not-found

echo 'done'
