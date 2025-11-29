#!/bin/bash
# Deploy all Kubernetes manifests in correct order

set -e

echo "🚀 Deploying Kubernetes manifests..."
echo

# Ensure kubectl is available
if ! command -v kubectl &> /dev/null; then
  echo "❌ kubectl not found. Install kubectl first."
  exit 1
fi

# Check cluster connection
if ! kubectl cluster-info &> /dev/null; then
  echo "❌ Cannot connect to Kubernetes cluster"
  exit 1
fi

echo "✅ Kubernetes cluster is accessible"
echo

# Step 1: Create namespace
echo "📦 Step 1: Creating namespace..."
kubectl apply -f k8s-manifests/00-namespace.yaml
sleep 2

# Step 2: Create secrets
echo "🔐 Step 2: Creating secrets..."
kubectl apply -f k8s-manifests/01-mongodb-secret.yaml
sleep 2

# Step 3: Deploy internal services (Redis, MongoDB)
echo "🗄️  Step 3: Deploying storage services..."
kubectl apply -f k8s-manifests/03-redis-statefulset.yaml
kubectl apply -f k8s-manifests/04-mongodb-statefulset.yaml
echo "⏳ Waiting for Redis and MongoDB to be ready..."
sleep 10

# Step 4: Deploy workloads
echo "🌐 Step 4: Deploying application workloads..."
kubectl apply -f k8s-manifests/05-yjs-deployment.yaml
kubectl apply -f k8s-manifests/06-excalidraw-deployment.yaml
kubectl apply -f k8s-manifests/09-snapshot-aggregator-deployment.yaml
echo "⏳ Waiting for workloads to be ready..."
sleep 10

# Step 5: Apply network policies (after workloads are running)
echo "🔒 Step 5: Applying network policies..."
kubectl apply -f k8s-manifests/07-network-policy.yaml
sleep 2

# Step 6: Apply ingress (after NGINX is installed)
echo "🌐 Step 6: Applying ingress configuration..."
kubectl apply -f k8s-manifests/08-ingress-tls.yaml
sleep 5

echo
echo "✅ Deployment complete!"
echo
echo "📋 Checking pod status..."
kubectl get pods -n whiteboard

echo
echo "📊 Checking services..."
kubectl get svc -n whiteboard

echo
echo "🌐 Checking ingress..."
kubectl get ingress -n whiteboard

echo
echo "🎯 Next steps:"
echo "  1. Wait for all pods to be Ready (use 'kubectl get pods -n whiteboard -w')"
echo "  2. Get the Ingress IP: kubectl get ingress -n whiteboard"
echo "  3. Add /etc/hosts entry: <INGRESS_IP> excalidraw.local"
echo "  4. Open browser: https://excalidraw.local (ignore self-signed cert warning)"
echo "  5. Test sync: open in 2+ tabs and draw"
