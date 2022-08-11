terraform {
  required_providers {
    aiven = {
      source = "aiven/aiven"
      version = "3.3.1"
    }
  }
}

provider "aiven" {
  api_token = var.aiven_api_token
}