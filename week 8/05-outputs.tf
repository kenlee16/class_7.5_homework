# 05-outputs.tf
# Outputs surface computed attributes after `terraform apply`.
# These are read-only values that GCP assigns — not set by us in the config.

output "internal_ip" {
  description = "The private (internal VPC) IP address of the VM."
  value       = google_compute_instance.hw8_vm.network_interface[0].network_ip
}

output "external_ip" {
  description = "The public (ephemeral) IP address of the VM. Requires access_config block on the network_interface."
  value       = google_compute_instance.hw8_vm.network_interface[0].access_config[0].nat_ip
}

output "vm_name" {
  description = "The human-readable name of the VM as set in the resource config."
  value       = google_compute_instance.hw8_vm.name
}

output "vm_id" {
  description = "The GCP-assigned numeric ID for the instance. Computed after creation."
  value       = google_compute_instance.hw8_vm.id
}

output "vm_self_link" {
  description = "The full GCP REST API URL for this instance. Used when other resources need to reference this VM by its canonical path."
  value       = google_compute_instance.hw8_vm.self_link
}
