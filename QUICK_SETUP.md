# Quick Setup: Manual Execution

## Prerequisites
- `gcloud` CLI installed and authenticated
- `kubectl` installed
- `terraform` installed
- Git cloned repo with all manifests

## Step 1: Infrastructure Setup (5-10 min)
```bash
cd terraform/
terraform init
terraform plan
terraform apply -auto-approve
```

Save outputs:
```bash
terraform output -json > ../terraform-outputs.json
export HTTP_URL=$(terraform output -raw http_url)
export ZONE=$(terraform output -raw zone)
export SERVER_NAME=$(terraform output -raw k3s_server_name)
```

## Step 2: Get Kubeconfig
```bash
gcloud compute ssh $SERVER_NAME --zone=$ZONE --tunnel-through-iap \
  --command "cat /root/.kube/config" > ~/.kube/config
chmod 600 ~/.kube/config
```

Verify connection:
```bash
kubectl get nodes
```

## Step 3: Deploy Kubernetes Resources
```bash
cd k8s-manifests/

# Create namespace
kubectl apply -f 00-namespace.yaml

# Add MongoDB Atlas connection (update with your credentials)
kubectl create secret generic mongo-uri \
  -n whiteboard \
  --from-literal=MONGO_URI='mongodb+srv://user:pass@cluster.mongodb.net/db'

# Create Redis secret (update password)
kubectl create secret generic redis-secret \
  -n whiteboard \
  --from-literal=REDIS_PASSWORD='your-redis-password-here' \
  --from-literal=REDIS_URL='redis://:your-redis-password-here@redis:6379'

# Deploy all manifests
kubectl apply -f 01-mongodb-secret.yaml
kubectl apply -f 02-kcc-pubsub.yaml
kubectl apply -f 03-kcc-gcs.yaml
kubectl apply -f 04-k8s-serviceaccount.yaml
kubectl apply -f 05-yjs-deployment.yaml
kubectl apply -f 06-excalidraw-deployment.yaml
kubectl apply -f 07-network-policy.yaml
```

## Step 4: Verify Deployment
```bash
# Check all pods running
kubectl get pods -n whiteboard

# Check services
kubectl get svc -n whiteboard

# Check ingress
kubectl get ingress -n whiteboard

# View logs (wait 1-2 min after deployment)
kubectl logs -n whiteboard -l app=yjs-server
kubectl logs -n whiteboard -l app=excalidraw-ui
```

## Step 5: Access Application
Open browser: `http://$HTTP_URL`

Or get the exact URL:
```bash
kubectl get ingress -n whiteboard -o jsonpath='{.items[0].status.loadBalancer.ingress[0].ip}'
```

## Cleanup
```bash
kubectl delete namespace whiteboard
terraform destroy -auto-approve
```

---

**Time to deploy**: ~15-20 minutes (excluding Terraform init time)
