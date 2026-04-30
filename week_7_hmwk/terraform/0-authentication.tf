terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }

    local = {
      source  = "hashicorp/local"
      version = "~> 2.0"
    }
  }
}

# 👇 OUTSIDE terraform block
provider "google" {
  project = "cyberproject-490100"
  region  = "us-central1"
}

resource "local_file" "favorite_food" {
  filename = "${path.module}/favorite_food.txt"
  content  = "My favorite food is pizza"
}