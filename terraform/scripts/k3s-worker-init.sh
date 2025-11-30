#!/bin/bash
set -e

echo "=== K3s Worker Node Initialization ==="

########################################
# 0. Disable IPv6 (GCP NAT uses IPv4)
########################################
sysctl -w net.ipv6.conf.all.disable_ipv6=1
sysctl -w net.ipv6.conf.default.disable_ipv6=1
sysctl -w net.ipv6.conf.lo.disable_ipv6=1

########################################
# 1. System update
########################################
apt-get update -y
apt-get upgrade -y

########################################
# 2. Install dependencies
########################################
apt-get install -y curl wget git jq htop net-tools docker.io

systemctl enable docker
systemctl start docker

sleep 200

########################################
# 3. Set K3s server connection details
########################################
K3S_VERSION="v1.34.2+k3s1"
K3S_TOKEN="${K3S_TOKEN}"
K3S_SERVER_IP="${K3S_SERVER_IP}"

echo "Connecting to K3s server at: https://$K3S_SERVER_IP:6443"

########################################
# 4. Install K3s agent
########################################
echo "Installing K3s agent version $K3S_VERSION..."
curl -sfL https://get.k3s.io | INSTALL_K3S_VERSION="$K3S_VERSION" \
  K3S_URL="https://$K3S_SERVER_IP:6443" \
  K3S_TOKEN="$K3S_TOKEN" sh -

########################################
# 5. Wait for K3s agent service to be active
########################################
echo "Waiting for K3s agent service..."
for i in {1..30}; do
  if systemctl is-active --quiet k3s-agent; then
    echo "K3s agent is running!"
    break
  fi
  echo "Attempt $i/30..."
  sleep 5
done

########################################
# 6. Wait for node to appear in server cluster
########################################
NODE=$(hostname)
echo "Waiting for worker node $NODE to appear in cluster..."
for i in {1..60}; do
  if k3s kubectl get nodes | grep "$NODE" &>/dev/null; then
    echo "Node $NODE registered in cluster!"
    break
  fi
  echo "Attempt $i/60..."
  sleep 5
done

########################################
# 7. Label the worker node
########################################
if k3s kubectl get node "$NODE" &>/dev/null; then
  k3s kubectl label nodes "$NODE" node-role.kubernetes.io/worker=true --overwrite
  echo "Worker node labeled successfully"
else
  echo "Warning: node $NODE not found in cluster yet"
fi

########################################
# 8. Summary
########################################
echo "=== K3s Worker Ready ==="
k3s kubectl get nodes
echo "Worker IP: $(hostname -I | awk '{print $1}')"
echo "==== WORKER SETUP COMPLETE ===="
