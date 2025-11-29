output "vpc_name" {
  description = "Private VPC name"
  value       = google_compute_network.private_vpc.name
}

output "subnet_name" {
  description = "Private subnet name"
  value       = google_compute_subnetwork.private_subnet.name
}

output "k3s_server_ip" {
  description = "K3s server node internal IP"
  value       = google_compute_instance.k3s_server.network_interface[0].network_ip
}

output "k3s_worker_ips" {
  description = "K3s worker nodes internal IPs"
  value = [for worker in google_compute_instance.k3s_workers : 
    worker.network_interface[0].network_ip
  ]
}

output "k3s_server_name" {
  description = "K3s server instance name"
  value       = google_compute_instance.k3s_server.name
}

output "k3s_worker_names" {
  description = "K3s worker instance names"
  value = [for worker in google_compute_instance.k3s_workers : 
    worker.name
  ]
}

output "http_load_balancer_ip" {
  description = "Public HTTP Load Balancer IP (Excalidraw + WebSocket)"
  value       = google_compute_global_forwarding_rule.http.ip_address
}

output "http_url" {
  description = "Public HTTP URL for Excalidraw UI"
  value       = "http://${google_compute_global_forwarding_rule.http.ip_address}/"
}

output "iap_ssh_command" {
  description = "SSH to k3s server via IAP (no public IP)"
  value       = "gcloud compute ssh ${google_compute_instance.k3s_server.name} --zone ${google_compute_instance.k3s_server.zone} --tunnel-through-iap"
}

output "gcs_bucket" {
  description = "GCS bucket for snapshot export"
  value       = google_storage_bucket.snapshots.name
}

output "snapshot_sa_email" {
  description = "Service account for snapshot CronJob (Workload Identity)"
  value       = google_service_account.snapshot_sa.email
}
