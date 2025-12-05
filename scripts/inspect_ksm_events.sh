#!/bin/bash
set -e

NS=kube-system
RS=$(kubectl -n $NS get rs -o name | grep kube-state-metrics || true)
if [ -n "$RS" ]; then
  echo "Describe ReplicaSet: $RS"
  kubectl -n $NS describe $RS || true
fi

echo

echo "Recent events in $NS (last 50)"
kubectl -n $NS get events --sort-by=.lastTimestamp | tail -n 50 || true

echo done
