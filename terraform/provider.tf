terraform {
  required_version = ">= 1.0"
  
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
  }

  # Uncomment to use Cloud Storage as backend
  # backend "gcs" {
  #   bucket  = "your-terraform-state-bucket"
  #   prefix  = "private-cloud/k3s"
  # }
}

provider "google" {
  project = var.gcp_project_id
  region  = var.gcp_region
}
