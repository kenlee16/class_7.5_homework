# 03-variables.tf
# Input variables for the configuration.
# Set project_id either via terraform.tfvars (gitignored) or -var flag at apply time.

variable "project_id" {
  description = "The GCP project ID to deploy resources into."
  type        = string
  default     = "cyberproject-490100"
}

variable "region" {
  description = "The GCP region for the provider default."
  type        = string
  default     = "us-central1"
}

variable "zone" {
  description = "The GCP zone to deploy the VM into."
  type        = string
  default     = "us-central1-a"
}
