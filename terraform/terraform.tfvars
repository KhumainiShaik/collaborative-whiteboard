# terraform.tfvars - Configure these values for your environment

gcp_project_id         = "storied-catwalk-477918-e0"
gcp_region             = "us-central1"
private_vpc_cidr       = "10.10.0.0/16"
private_subnet_cidr    = "10.10.1.0/24"
k3s_node_count         = 3  # 1 server + 2 workers
k3s_server_machine_type = "t2a-standard-2"  # ARM64, 2 vCPU, 8GB RAM
k3s_worker_machine_type = "t2a-standard-2"  # ARM64, 2 vCPU, 8GB RAM
boot_disk_size_gb      = 50
enable_cloud_nat       = true
enable_monitoring      = true
environment            = "private-cloud"

tags = ["k3s", "private-cloud", "whiteboard", "excalidraw"]
