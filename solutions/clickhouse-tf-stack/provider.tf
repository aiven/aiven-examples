terraform {
  required_providers {
    aiven = {
      source = "aiven/aiven"
      version = ">=4.0.0, <5.0.0"
    }
    time = {
      source = "hashicorp/time"
      version = "0.7.2"
    }
  }
}

provider "aiven" {
  api_token = var.aiven_api_token
}