terraform {
  required_providers {
    aiven = {
      source = "aiven/aiven"
      version = "2.6.0"
    }
    time = {
      source = "hashicorp/time"
      version = "0.7.1"
    }
  }
}

provider "aiven" {
  api_token = var.aiven_api_token
}

provider "time" {}