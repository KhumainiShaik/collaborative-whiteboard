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
# 2. Install dependencies
########################################
apt-get install -y curl wget git jq htop net-tools

########################################
# 3. Wait for K3s server to be reachable
########################################
K3S_SERVER_IP="${K3S_SERVER_IP}"
echo "Checking TCP connectivity to K3s server at $K3S_SERVER_IP:6443"

########################################
# 4. Install K3s agent
########################################
K3S_VERSION="v1.34.2+k3s1"
K3S_TOKEN="${K3S_TOKEN}"

echo "Installing K3s agent version $K3S_VERSION..."
curl -sfL https://get.k3s.io | \
  INSTALL_K3S_VERSION="$K3S_VERSION" \
  K3S_URL="https://$K3S_SERVER_IP:6443" \
  K3S_TOKEN="$K3S_TOKEN" \
  sh -

########################################
# 5. Ensure k3s-agent is running
########################################
echo "Waiting for k3s-agent service to start..."
systemctl enable k3s-agent

for i in {1..30}; do
  if systemctl is-active --quiet k3s-agent; then
    echo "k3s-agent is active!"
    break
  fi
  echo "Attempt $i/30..."
  sleep 5
done

########################################
# 6. Summary (no kubectl needed)
########################################
echo "=== K3s Worker Ready ==="
echo "Worker hostname: $(hostname)"
echo "Worker IP: $(hostname -I | awk '{print $1}')"
echo "Agent service:"
systemctl status k3s-agent --no-pager | head -15

echo "==== WORKER SETUP COMPLETE ===="
