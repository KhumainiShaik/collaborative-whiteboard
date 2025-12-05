#!/bin/bash
set -u

echo "Deploying node-exporter and kube-state-metrics (best-effort)"
NODE_URL="https://raw.githubusercontent.com/prometheus/node_exporter/master/examples/node-exporter-daemonset.yaml"
KSM_URL="https://raw.githubusercontent.com/kubernetes/kube-state-metrics/master/examples/standard/deployment.yaml"

echo "Applying node-exporter from $NODE_URL"
kubectl apply -f "$NODE_URL" || echo "node-exporter apply failed"

echo "Applying kube-state-metrics from $KSM_URL"
kubectl apply -f "$KSM_URL" || echo "kube-state-metrics apply failed"

echo "Sleeping 25s for pods to start"
sleep 25

if [ -x /tmp/check_prom_targets.sh ]; then
  echo "running /tmp/check_prom_targets.sh"
  /tmp/check_prom_targets.sh
else
  echo "/tmp/check_prom_targets.sh not found"
fi

if [ -x /tmp/check_prom.sh ]; then
  echo "running /tmp/check_prom.sh"
  /tmp/check_prom.sh
else
  echo "/tmp/check_prom.sh not found"
fi

echo "deploy script done"
