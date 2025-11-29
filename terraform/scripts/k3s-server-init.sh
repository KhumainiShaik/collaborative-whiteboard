#!/bin/bash
set -e

# K3s Server (Control Plane) initialization script
# Runs on the first VM to set up the control plane

echo "=== K3s Server Node Initialization ==="

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

# Install K3s server (single node / control plane)
echo "Installing K3s server..."
export INSTALL_K3S_SKIP_DOWNLOAD=false
export INSTALL_K3S_VERSION=v1.28.0
export K3S_CLUSTER_INIT=true
export K3S_TOKEN=k3s-secret-token-12345

curl -sfL https://get.k3s.io | sh -

# Wait for K3s to be ready
echo "Waiting for K3s to be ready..."
for i in {1..30}; do
  if kubectl get nodes &> /dev/null; then
    echo "K3s is ready!"
    break
  fi
  echo "Attempt $i/30: Waiting for K3s..."
  sleep 10
done

# Label the server node with proper K3s roles and identifiers
echo "Labeling K3s server node..."
kubectl label nodes $(hostname) \
  node-role.kubernetes.io/master=true \
  node-role.kubernetes.io/control-plane=true \
  role=k3s-server \
  --overwrite

# Add taint to prevent user workloads from running on control plane
kubectl taint nodes $(hostname) \
  node-role.kubernetes.io/master=true:NoSchedule \
  --overwrite || true  # May already exist

# Install NGINX Ingress Controller
echo "Installing NGINX Ingress Controller..."
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.8.0/deploy/static/provider/baremetal/deploy.yaml

# Wait for ingress controller
kubectl wait --namespace ingress-nginx \
  --for=condition=ready pod \
  --selector=app.kubernetes.io/component=controller \
  --timeout=120s || echo "Ingress controller timeout - continuing anyway"

# Install cert-manager
echo "Installing cert-manager..."
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.13.0/cert-manager.yaml

# Wait for cert-manager
kubectl wait --namespace cert-manager \
  --for=condition=ready pod \
  --selector=app.kubernetes.io/instance=cert-manager \
  --timeout=120s || echo "Cert-manager timeout - continuing anyway"

# Create whiteboard namespace
kubectl create namespace whiteboard || echo "Namespace already exists"
kubectl label namespace whiteboard name=whiteboard --overwrite

# Install metrics-server (needed for HPA)
echo "Installing metrics-server..."
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml

# Verify installation
echo "=== K3s Server Ready ==="
kubectl get nodes
kubectl get pods -A

# Save kubeconfig to a world-readable location
mkdir -p /root/.kube
cp /etc/rancher/k3s/k3s.yaml /root/.kube/config
chmod 644 /root/.kube/config

# Write K3s token for workers
echo "$(cat /var/lib/rancher/k3s/server/node-token)" > /tmp/k3s-token.txt
chmod 644 /tmp/k3s-token.txt

echo "K3s Server initialization complete!"
echo "Server IP: $(hostname -I | awk '{print $1}')"
echo "Token saved to: /tmp/k3s-token.txt"
