# 02-provider.tf
# Configures the Google Cloud provider.
# The project and region here set the defaults for all resources in this config.
# Override per-resource if needed.

provider "google" {
  project = var.project_id
  region  = var.region
}
