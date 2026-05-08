terraform {
  required_version = ">= 1.5.7, < 2.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0" # Latest major version as of 2025; allows minor/patch updates
    }
  }
}
