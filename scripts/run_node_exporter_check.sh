#!/bin/bash
set -e

NODE_ALT="https://raw.githubusercontent.com/prometheus-operator/kube-prometheus/main/manifests/node-exporter-daemonset.yaml"

echo "Applying alternative node-exporter manifest: $NODE_ALT"
kubectl apply -f "$NODE_ALT" || echo "node-exporter alt apply failed"

echo

echo "Pods across namespaces containing 'kube-state-metrics'"
kubectl get pods --all-namespaces | grep kube-state-metrics || true

echo

echo "monitoring namespace pods"
kubectl -n monitoring get pods -o wide || true

echo
if [ -x /tmp/check_prom_targets.sh ]; then
  echo "running /tmp/check_prom_targets.sh"
  /tmp/check_prom_targets.sh || true
else
  echo "/tmp/check_prom_targets.sh not found"
fi

if [ -x /tmp/check_prom.sh ]; then
  echo "running /tmp/check_prom.sh"
  /tmp/check_prom.sh || true
else
  echo "/tmp/check_prom.sh not found"
fi

echo "run_node_exporter_check done"
