variable "gcp_project_id" {
  description = "GCP Project ID"
  type        = string
}

variable "gcp_region" {
  description = "GCP region for resources"
  type        = string
  default     = "us-central1"
}

variable "private_vpc_cidr" {
  description = "CIDR range for private VPC"
  type        = string
  default     = "10.10.0.0/16"
}

variable "private_subnet_cidr" {
  description = "CIDR range for private subnet"
  type        = string
  default     = "10.10.1.0/24"
}

variable "k3s_node_count" {
  description = "Number of K3s nodes (1 server + N workers)"
  type        = number
  default     = 3
}

variable "k3s_server_machine_type" {
  description = "Machine type for K3s server node"
  type        = string
  default     = "t2a-standard-2"
}

variable "k3s_worker_machine_type" {
  description = "Machine type for K3s worker nodes"
  type        = string
  default     = "t2a-standard-2"
}

variable "boot_disk_size_gb" {
  description = "Boot disk size in GB"
  type        = number
  default     = 50
}

variable "enable_cloud_nat" {
  description = "Enable Cloud NAT for private subnet"
  type        = bool
  default     = true
}

variable "enable_monitoring" {
  description = "Enable Prometheus/Grafana monitoring"
  type        = bool
  default     = true
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "private-cloud"
}

variable "tags" {
  description = "Tags for GCP resources"
  type        = list(string)
  default     = ["k3s", "private-cloud", "whiteboard"]
}

# ============================================================
# MongoDB Configuration Variables
# ============================================================

variable "mongodb_deployment" {
  description = "MongoDB deployment method: 'atlas' (cloud-managed) or 'self-hosted'"
  type        = string
  default     = "atlas"
  validation {
    condition     = contains(["atlas", "self-hosted"], var.mongodb_deployment)
    error_message = "mongodb_deployment must be either 'atlas' or 'self-hosted'."
  }
}

variable "mongodb_org_id" {
  description = "MongoDB Atlas Organization ID (required if mongodb_deployment='atlas')"
  type        = string
  default     = ""
  sensitive   = true
}

variable "mongodb_username" {
  description = "MongoDB username for snapshot aggregator"
  type        = string
  default     = "snapshot-aggregator"
  sensitive   = true
}

variable "mongodb_storage_gb" {
  description = "MongoDB persistent volume size in GB (for self-hosted)"
  type        = number
  default     = 20
}
