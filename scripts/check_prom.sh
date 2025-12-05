#!/bin/bash
set -e
NAMESPACE=monitoring
POD=prom-check-$(date +%s)

echo "Creating temp pod $POD in namespace $NAMESPACE..."
kubectl -n "$NAMESPACE" run "$POD" --image=curlimages/curl --restart=Never --command -- sleep 300 >/dev/null 2>&1 || true
sleep 2

queries=(
  'rate(container_cpu_usage_seconds_total{pod=~"(excalidraw-ui|yjs-server|redis).*"}[5m])'
  'container_memory_usage_bytes{pod=~"(excalidraw-ui|yjs-server|redis).*"}'
  'count(kube_pod_info{namespace="whiteboard"})'
  'count(kube_pod_info{namespace="whiteboard", pod=~"yjs-server.*"})'
  'rate(container_network_receive_bytes_total{pod=~"(excalidraw-ui|yjs-server|redis).*"}[5m])'
)

for q in "${queries[@]}"; do
  echo
  echo "=== QUERY: $q ==="
  kubectl -n "$NAMESPACE" exec "$POD" -- curl -sS --get --data-urlencode "query=$q" 'http://prometheus:9090/api/v1/query' || true
  echo
done

echo "Cleaning up pod $POD..."
kubectl -n "$NAMESPACE" delete pod "$POD" --ignore-not-found

echo "done"
