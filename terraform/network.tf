# Private VPC for the private cloud
resource "google_compute_network" "private_vpc" {
  name                    = "${var.environment}-vpc"
  auto_create_subnetworks = false
  description             = "Private VPC for K3s cluster (no public access)"
}

# Private subnet with no public IP auto-assignment
resource "google_compute_subnetwork" "private_subnet" {
  name          = "${var.environment}-subnet"
  ip_cidr_range = var.private_subnet_cidr
  region        = var.gcp_region
  network       = google_compute_network.private_vpc.id

  private_ip_google_access = true
  description              = "Private subnet for K3s control plane and worker nodes"

  log_config {
    aggregation_interval = "INTERVAL_5_SEC"
    flow_logs_enabled    = true
    metadata             = "INCLUDE_ALL_METADATA"
  }
}

# Cloud NAT for private subnet egress
# Allows nodes to pull Docker images and OS updates
resource "google_compute_router" "private_router" {
  count   = var.enable_cloud_nat ? 1 : 0
  name    = "${var.environment}-router"
  region  = var.gcp_region
  network = google_compute_network.private_vpc.id

  bgp {
    asn = 64514
  }
}

resource "google_compute_router_nat" "cloud_nat" {
  count                          = var.enable_cloud_nat ? 1 : 0
  name                           = "${var.environment}-nat"
  router                         = google_compute_router.private_router[0].name
  region                         = var.gcp_region
  nat_ip_allocate_option         = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"

  # Log NAT traffic (optional, for auditing)
  log_config {
    enable = true
    filter = "ERRORS_ONLY"
  }
}

# Firewall: Allow SSH via IAP (Identity-Aware Proxy)
# Traffic from IAP to SSH port is allowed
# IAP provides authentication and encryption without exposing SSH publicly
resource "google_compute_firewall" "allow_ssh_from_iap" {
  name    = "${var.environment}-allow-ssh-from-iap"
  network = google_compute_network.private_vpc.id

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  # Google IAP's public IPs - these are fixed and maintained by Google
  source_ranges = ["35.235.240.0/20"]
}

# Firewall: Allow inter-pod communication (internal K3s networking)
# Critical K3s cluster communication ports
resource "google_compute_firewall" "allow_k3s_api" {
  name    = "${var.environment}-allow-k3s-api"
  network = google_compute_network.private_vpc.id

  allow {
    protocol = "tcp"
    ports    = ["6443"]  # K3s API server
  }

  source_ranges = [var.private_subnet_cidr]
}

# Firewall: Allow kubelet communication
resource "google_compute_firewall" "allow_kubelet" {
  name    = "${var.environment}-allow-kubelet"
  network = google_compute_network.private_vpc.id

  allow {
    protocol = "tcp"
    ports    = ["10250"]  # kubelet API
  }

  source_ranges = [var.private_subnet_cidr]
}

# Firewall: Allow etcd communication (if using external etcd)
resource "google_compute_firewall" "allow_etcd" {
  name    = "${var.environment}-allow-etcd"
  network = google_compute_network.private_vpc.id

  allow {
    protocol = "tcp"
    ports    = ["2379", "2380"]  # etcd client and peer ports
  }

  source_ranges = [var.private_subnet_cidr]
}

# Firewall: Allow Flannel VXLAN networking
resource "google_compute_firewall" "allow_flannel_vxlan" {
  name    = "${var.environment}-allow-flannel-vxlan"
  network = google_compute_network.private_vpc.id

  allow {
    protocol = "udp"
    ports    = ["8472"]  # Flannel VXLAN
  }

  source_ranges = [var.private_subnet_cidr]
}

# Firewall: Allow metadata server access (required for Workload Identity, monitoring, logging)
resource "google_compute_firewall" "allow_metadata_server" {
  name    = "${var.environment}-allow-metadata-server"
  network = google_compute_network.private_vpc.id

  allow {
    protocol = "tcp"
    ports    = ["80"]
  }

  destination_ranges = ["169.254.169.254/32"]  # GCP Metadata Server
  source_ranges      = [var.private_subnet_cidr]
}

# Firewall: Allow internal DNS (required for service discovery)
resource "google_compute_firewall" "allow_dns_internal" {
  name    = "${var.environment}-allow-dns-internal"
  network = google_compute_network.private_vpc.id

  allow {
    protocol = "udp"
    ports    = ["53"]
  }

  allow {
    protocol = "tcp"
    ports    = ["53"]
  }

  source_ranges = [var.private_subnet_cidr]
}

# Firewall: Allow NTP outbound (required for clock synchronization)
resource "google_compute_firewall" "allow_ntp_outbound" {
  name      = "${var.environment}-allow-ntp-outbound"
  network   = google_compute_network.private_vpc.id
  direction = "EGRESS"

  allow {
    protocol = "udp"
    ports    = ["123"]
  }

  destination_ranges = ["0.0.0.0/0"]  # NTP servers on internet
}

# Firewall: Allow all internal traffic within subnet
resource "google_compute_firewall" "allow_internal" {
  name    = "${var.environment}-allow-internal"
  network = google_compute_network.private_vpc.id

  allow {
    protocol = "tcp"
  }

  allow {
    protocol = "udp"
  }

  allow {
    protocol = "icmp"
  }

  source_ranges = [var.private_subnet_cidr]
}
