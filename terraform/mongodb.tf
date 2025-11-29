# ============================================================
# MongoDB Atlas (External Managed Database)
# ============================================================

# Provider: mongodbatlas (configure in terraform block or provider)

resource "random_password" "mongodb_password" {
  length  = 16
  special = true
}

# MongoDB Atlas Project
resource "mongodbatlas_project" "whiteboard" {
  org_id = var.mongodb_org_id
  name   = "excalidraw-whiteboard"
}

# MongoDB Atlas Cluster (M0 free tier for demo, M2 for production)
resource "mongodbatlas_cluster" "whiteboard" {
  project_id = mongodbatlas_project.whiteboard.id
  name       = "whiteboard-cluster"

  provider_name             = "GCP"
  provider_region_name      = var.gcp_region
  provider_instance_size_name = "M0"  # Free tier

  backup_enabled = true

  tags = {
    Environment = "production"
    Application = "excalidraw-whiteboard"
  }
}

# Database user
resource "mongodbatlas_database_user" "snapshot_aggregator" {
  project_id         = mongodbatlas_project.whiteboard.id
  auth_database_name = "admin"
  username           = var.mongodb_username
  password           = random_password.mongodb_password.result

  roles {
    role_name     = "readWrite"
    database_name = "whiteboard"
  }
}

# IP Whitelist: Allow from k3s cluster NAT IP
resource "mongodbatlas_project_ip_whitelist" "k3s_cluster" {
  project_id = mongodbatlas_project.whiteboard.id
  ip_address = google_compute_address.k3s_nat_ip.address
  comment    = "K3s cluster Cloud NAT gateway"
}
# Kubernetes Secret: MongoDB Connection String
# ============================================================

# After MongoDB is provisioned, create this secret:
resource "kubernetes_secret" "mongodb_credentials" {
  metadata {
    name      = "mongodb-credentials"
    namespace = kubernetes_namespace.whiteboard.metadata[0].name
  }

  data = {
    MONGO_URL = "mongodb+srv://${mongodbatlas_database_user.snapshot_aggregator.username}:${urlencode(mongodbatlas_database_user.snapshot_aggregator.password)}@${mongodbatlas_cluster.whiteboard.connection_strings.0.standard_srv}"
  }

  depends_on = [
    mongodbatlas_database_user.snapshot_aggregator,
    mongodbatlas_cluster.whiteboard
  ]
}

# ============================================================
# Outputs: Connection Information for Deployment
# ============================================================

output "mongodb_connection_string" {
  description = "MongoDB Atlas connection string for snapshot aggregator"
  value = "mongodb+srv://${mongodbatlas_database_user.snapshot_aggregator.username}:${urlencode(mongodbatlas_database_user.snapshot_aggregator.password)}@${mongodbatlas_cluster.whiteboard.connection_strings.0.standard_srv}"
  sensitive = true
}

output "mongodb_connection_string_k8s_secret" {
  description = "How to reference in K8s: valueFrom.secretKeyRef.name=mongodb-credentials, key=MONGO_URL"
  value = "mongodb-credentials"
}

output "mongodb_org_id" {
  description = "MongoDB Atlas Organization ID"
  value = var.mongodb_org_id
}

output "mongodb_project_id" {
  description = "MongoDB Atlas Project ID"
  value = mongodbatlas_project.whiteboard.id
}

output "mongodb_cluster_name" {
  description = "MongoDB Atlas Cluster Name"
  value = mongodbatlas_cluster.whiteboard.name
}

output "mongodb_cluster_status" {
  description = "MongoDB Atlas Cluster Status"
  value = mongodbatlas_cluster.whiteboard.state_name
}
