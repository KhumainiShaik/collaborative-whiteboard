# ============================================================
# External HTTP Load Balancer (public IP for Excalidraw + WebSocket)
# Routes to NGINX Ingress → private k3s cluster
# ============================================================

# Health check for backend
resource "google_compute_health_check" "http_health" {
  name        = "${var.environment}-http-health"
  http_health_check {
    port = 80
  }
}

# Backend service for HTTP
resource "google_compute_backend_service" "http_backend" {
  name            = "${var.environment}-http-backend"
  protocol        = "HTTP"
  port_name       = "http"
  timeout_sec     = 30
  health_checks   = [google_compute_health_check.http_health.id]
  load_balancing_scheme = "EXTERNAL"

  backend {
    group = google_compute_instance_group.k3s_nodes_ig.id
  }
}

# Instance group (all k3s nodes, for NGINX Ingress)
resource "google_compute_instance_group" "k3s_nodes_ig" {
  name        = "${var.environment}-nodes-ig"
  zone        = "${var.gcp_region}-a"
  instances   = concat([google_compute_instance.k3s_server.self_link], 
                       [for w in google_compute_instance.k3s_workers : w.self_link])
  
  named_port {
    name = "http"
    port = 80
  }
}

# URL map for routing
resource "google_compute_url_map" "http_map" {
  name            = "${var.environment}-http-map"
  default_service = google_compute_backend_service.http_backend.id
}

# HTTP proxy
resource "google_compute_target_http_proxy" "http_proxy" {
  name    = "${var.environment}-http-proxy"
  url_map = google_compute_url_map.http_map.id
}

# Global forwarding rule (public IP)
resource "google_compute_global_forwarding_rule" "http" {
  name                  = "${var.environment}-http-forwarding"
  load_balancing_scheme = "EXTERNAL"
  ip_protocol           = "TCP"
  port_range            = "80"
  target                = google_compute_target_http_proxy.http_proxy.id
}

# Firewall: Allow HTTP from internet to nodes
resource "google_compute_firewall" "allow_http_from_internet" {
  name    = "${var.environment}-allow-http-from-internet"
  network = google_compute_network.private_vpc.id

  allow {
    protocol = "tcp"
    ports    = ["80"]
  }

  source_ranges = ["0.0.0.0/0"]
}
