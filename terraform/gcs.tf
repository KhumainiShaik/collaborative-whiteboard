# ============================================================
# GCS Bucket for Snapshot Export
# ============================================================

resource "google_storage_bucket" "snapshots" {
  name          = "${var.gcp_project_id}-whiteboard-snapshots"
  location      = var.gcp_region
  force_destroy = false

  uniform_bucket_level_access = true

  versioning {
    enabled = true
  }

  lifecycle_rule {
    action {
      type = "Delete"
    }
    condition {
      age = 90  # Delete snapshots after 90 days
    }
  }

  labels = {
    application = "excalidraw"
    tier        = "snapshots"
  }
}

# ============================================================
# Service Account for Snapshot CronJob (Workload Identity)
# ============================================================

resource "google_service_account" "snapshot_sa" {
  account_id   = "${var.environment}-snapshot-job"
  display_name = "Service account for snapshot export CronJob"
}

# GCS permissions for snapshot SA
resource "google_storage_bucket_iam_member" "snapshot_bucket_write" {
  bucket = google_storage_bucket.snapshots.name
  role   = "roles/storage.objectCreator"
  member = "serviceAccount:${google_service_account.snapshot_sa.email}"
}

# Workload Identity: K8s SA → GCP SA
# Binding: namespace/k8s-sa → gcp-sa
resource "google_service_account_iam_member" "snapshot_workload_identity" {
  service_account_id = google_service_account.snapshot_sa.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:${var.gcp_project_id}.svc.id.goog[whiteboard/snapshot-sa]"
}

