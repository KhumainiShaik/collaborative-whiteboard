#!/bin/bash
set -e

# K3s Worker Node initialization script
# Runs on worker VMs to join the K3s cluster

echo "=== K3s Worker Node Initialization ==="

# Update system
apt-get update
apt-get upgrade -y

# Install dependencies
apt-get install -y \
    curl \
    wget \
    git \
    docker.io \
    jq \
    htop \
    net-tools

# Start Docker
systemctl enable docker
systemctl start docker

# Wait for K3s server to be ready
echo "Waiting for K3s server to initialize (30 seconds)..."
sleep 30

# Get K3s token from server (you need to configure this)
# This is a placeholder - in production, use a secrets backend
K3S_TOKEN="k3s-secret-token-12345"
K3S_SERVER_IP="10.10.1.2"  # Internal IP of server node

# Install K3s worker
echo "Installing K3s worker..."
export INSTALL_K3S_SKIP_DOWNLOAD=false
export INSTALL_K3S_VERSION=v1.28.0

curl -sfL https://get.k3s.io | \
  K3S_URL=https://${K3S_SERVER_IP}:6443 \
  K3S_TOKEN=${K3S_TOKEN} \
  sh -

# Wait for kubelet to be ready
echo "Waiting for worker node to join cluster..."
for i in {1..30}; do
  if systemctl is-active --quiet k3s-agent; then
    echo "Worker node is ready!"
    break
  fi
  echo "Attempt $i/30: Waiting for k3s-agent..."
  sleep 5
done

# Verify worker node joined cluster and label it
echo "Labeling K3s worker node..."
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
HOSTNAME=$(hostname)

# Wait for node to appear in cluster (max 5 minutes)
for i in {1..60}; do
  if kubectl get node "$HOSTNAME" &>/dev/null; then
    echo "Node $HOSTNAME appeared in cluster"
    break
  fi
  echo "Attempt $i/60: Waiting for node to appear in cluster..."
  sleep 5
done

# Label the worker node
if kubectl get node "$HOSTNAME" &>/dev/null; then
  kubectl label nodes "$HOSTNAME" \
    node-role.kubernetes.io/worker=true \
    role=k3s-worker \
    --overwrite
  echo "Worker node labeled successfully"
else
  echo "Warning: Could not label node - not yet in cluster"
fi
