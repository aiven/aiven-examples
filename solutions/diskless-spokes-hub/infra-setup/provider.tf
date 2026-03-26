terraform {
  required_providers {
    aiven = {
      source = "aiven/aiven"
      version = "~> 4.0"
    }
    time = {
      source = "hashicorp/time"
      version = "0.7.2"
    }
    env = {
      source  = "tchupp/env"
      version = "0.0.2"
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.0"
    }
  }
}

provider "aiven" {
  api_token = var.aiven_api_token
}