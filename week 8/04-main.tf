# 04-main.tf
# Provisions a single GCP Compute Engine VM instance with:
#   - CentOS Stream 10 OS image
#   - 100 GB root persistent disk
#   - N2 machine type (n2-standard-2: 2 vCPU, 8 GB RAM)
#   - External IP via access_config
#   - http-server network tag (enables default-allow-http firewall rule on port 80)
#   - RHEL-compatible startup script pulled from the course repo

resource "google_compute_instance" "hw8_vm" {
  name         = "hw8-centos-vm"
  machine_type = "n2-standard-2" # N series; 2 vCPU, 8 GB RAM
  zone         = var.zone

  # Network tags: "http-server" activates the default VPC firewall rule
  # that allows TCP 80 ingress, so the web server is reachable externally.
  tags = ["http-server"]

  boot_disk {
    initialize_params {
      # centos-cloud is the GCP-maintained project for CentOS images.
      # Using the family name (centos-stream-10) instead of a specific image
      # name means Terraform always picks the latest published image in that family.
      image = "centos-cloud/centos-stream-10"
      size  = 100  # GB — root persistent disk
      type  = "pd-balanced"
    }
  }

  network_interface {
    # Attaches to the default VPC. No subnetwork arg needed — GCP picks the
    # default subnet in the specified zone automatically.
    network = "default"

    # An empty access_config block tells GCP to assign an ephemeral external IP.
    # Without this block the instance has no external IP at all.
    access_config {}
  }

  # startup.sh in the same module directory provides the startup script.
  metadata_startup_script = file("${path.module}/startup.sh")
}
