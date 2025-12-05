#!/bin/bash
set -e

echo "== Deployments (all namespaces) containing 'kube-state-metrics' =="
kubectl get deployments --all-namespaces -o wide | grep kube-state-metrics || true

echo

echo "== Pods (all namespaces) containing 'kube-state-metrics' =="
kubectl get pods --all-namespaces -o wide | grep kube-state-metrics || true

echo

echo "== Services (all namespaces) containing 'kube-state-metrics' =="
kubectl get svc --all-namespaces -o wide | grep kube-state-metrics || true

echo

echo "== Describe kube-state-metrics deployment if found in any namespace =="
NS=$(kubectl get deployments --all-namespaces -o jsonpath='{range .items[?(@.metadata.name=="kube-state-metrics")]}{.metadata.namespace}{"\n"}{end}')
if [ -n "$NS" ]; then
  kubectl -n "$NS" describe deployment kube-state-metrics || true
  echo
  echo "== Pod logs for kube-state-metrics =="
  kubectl -n "$NS" get pods -l app.kubernetes.io/name=kube-state-metrics -o name || true
  for p in $(kubectl -n "$NS" get pods -l app.kubernetes.io/name=kube-state-metrics -o name 2>/dev/null || true); do
    echo "--- logs $p ---"
    kubectl -n "$NS" logs "$p" || true
  done
else
  echo "kube-state-metrics deployment not found"
fi

echo done
