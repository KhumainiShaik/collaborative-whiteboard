#!/bin/bash
set -e

echo "=== K3s Server Node Initialization (HTTPS-Free) ==="

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
# 3. Install K3s (official installer, correct version)
########################################
K3S_VERSION="v1.34.2+k3s1"
K3S_TOKEN="${K3S_TOKEN}"

echo "Installing K3s server version $K3S_VERSION..."
curl -sfL https://get.k3s.io | INSTALL_K3S_VERSION="$K3S_VERSION" \
  K3S_TOKEN="$K3S_TOKEN" sh -

########################################
# 4. Wait for Kubernetes API
########################################
echo "Waiting for K3s API to become ready..."
for i in {1..30}; do
  if k3s kubectl get nodes &> /dev/null; then
    echo "K3s API is ready!"
    break
  fi
  echo "Attempt $i/30..."
  sleep 5
done

########################################
# 5. Wait for node to register in cluster
########################################
NODE=$(hostname)
echo "Waiting for node $NODE to register in cluster..."
for i in {1..60}; do
  if k3s kubectl get node "$NODE" &> /dev/null; then
    echo "Node $NODE is registered!"
    break
  fi
  echo "Attempt $i/60..."
  sleep 5
done

########################################
# 6. Label the control plane node
########################################
echo "Labeling control plane node..."
k3s kubectl label nodes "$NODE" node-role.kubernetes.io/master=true --overwrite
k3s kubectl label nodes "$NODE" node-role.kubernetes.io/control-plane=true --overwrite
k3s kubectl taint nodes "$NODE" node-role.kubernetes.io/master=true:NoSchedule --overwrite || true

########################################
# 7. Create namespace for your app
########################################
k3s kubectl create namespace whiteboard || true
k3s kubectl label namespace whiteboard name=whiteboard --overwrite

########################################
# 8. Install metrics-server
########################################
k3s kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml

########################################
# 9. Save kubeconfig
########################################
mkdir -p /root/.kube
cp /etc/rancher/k3s/k3s.yaml /root/.kube/config
chmod 644 /root/.kube/config

########################################
# 10. Save token for worker nodes
########################################
cp /var/lib/rancher/k3s/server/node-token /tmp/k3s-token.txt
chmod 644 /tmp/k3s-token.txt

########################################
# 11. Summary
########################################
echo "=== K3s Server Ready ==="
k3s kubectl get nodes
k3s kubectl get pods -A

echo "Server IP: $(hostname -I | awk '{print $1}')"
echo "Worker token saved to: /tmp/k3s-token.txt"
echo "==== SETUP COMPLETE ===="