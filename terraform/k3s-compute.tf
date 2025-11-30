# Generate secure K3s cluster token for worker node authentication
resource "random_password" "k3s_token" {
  length  = 32
  special = true
}

# K3s Server Node startup script
locals {
  k3s_server_startup_script = templatefile("${path.module}/scripts/k3s-server-init.sh", {
    cluster_name = var.environment
    private_subnet_cidr = var.private_subnet_cidr
    K3S_TOKEN = random_password.k3s_token.result
  })

  k3s_worker_startup_script = templatefile("${path.module}/scripts/k3s-worker-init.sh", {
    cluster_name = var.environment
    K3S_SERVER_IP = google_compute_instance.k3s_server.network_interface[0].network_ip
    K3S_TOKEN = random_password.k3s_token.result
  })
}

# Service Account for K3s VMs
resource "google_service_account" "k3s_sa" {
  account_id   = "${var.environment}-k3s-sa"
  display_name = "K3s nodes service account"
}

# IAM Binding for IAP (Identity-Aware Proxy) access
# Allows users to connect via "gcloud compute ssh --tunnel-through-iap"
resource "google_project_iam_member" "k3s_iap_tunnel_access" {
  project = var.gcp_project_id
  role    = "roles/iap.tunnelResourceAccessor"
  member  = "serviceAccount:${google_service_account.k3s_sa.email}"
}

# IAM Binding for service account to use Workload Identity (optional)
# Allows K3s pods to authenticate to GCP APIs with service account credentials
resource "google_service_account_iam_member" "k3s_workload_identity" {
  service_account_id = google_service_account.k3s_sa.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:${google_service_account.k3s_sa.email}"
}

# IAM roles for K3s nodes
resource "google_project_iam_member" "k3s_logging" {
  project = var.gcp_project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.k3s_sa.email}"
}

resource "google_project_iam_member" "k3s_monitoring" {
  project = var.gcp_project_id
  role    = "roles/monitoring.metricWriter"
  member  = "serviceAccount:${google_service_account.k3s_sa.email}"
}

# K3s Server Instance (Control Plane)
resource "google_compute_instance" "k3s_server" {
  name         = "${var.environment}-server-0"
  machine_type = var.k3s_server_machine_type
  zone         = "${var.gcp_region}-a"

  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-11"
      size  = var.boot_disk_size_gb
    }
  }

  network_interface {
    subnetwork = google_compute_subnetwork.private_subnet.id
    # No external IP - entirely private (access via IAP TCP forwarding)
  }

  service_account {
    email  = google_service_account.k3s_sa.email
    scopes = ["cloud-platform"]
  }

  metadata = {
    startup-script = local.k3s_server_startup_script
  }

  labels = {
    environment = var.environment
    role        = "k3s-server"
  }

  tags = var.tags
}

# K3s Worker Instances
resource "google_compute_instance" "k3s_workers" {
  count        = var.k3s_node_count - 1  # -1 because we have 1 server
  name         = "${var.environment}-worker-${count.index}"
  machine_type = var.k3s_worker_machine_type
  zone         = "${var.gcp_region}-a"  # Keep all instances in same zone for instance group

  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-11"
      size  = var.boot_disk_size_gb
    }
  }

  network_interface {
    subnetwork = google_compute_subnetwork.private_subnet.id
    # No external IP - entirely private (access via IAP TCP forwarding)
  }

  service_account {
    email  = google_service_account.k3s_sa.email
    scopes = ["cloud-platform"]
  }

  metadata = {
    startup-script = local.k3s_worker_startup_script
  }

  labels = {
    environment = var.environment
    role        = "k3s-worker"
  }

  tags = var.tags

  depends_on = [google_compute_instance.k3s_server]
}

# Health check for K3s control plane API
resource "google_compute_health_check" "k3s_api_health" {
  name        = "${var.environment}-k3s-api-health"
  description = "Health check for K3s control plane API"

  tcp_health_check {
    port = "6443"
  }

  check_interval_sec  = 10
  timeout_sec         = 5
  healthy_threshold   = 2
  unhealthy_threshold = 3
}
