terraform {
  required_providers {
    aiven = {
      source = "aiven/aiven"
    version = ">= 3.8.1" }
  }
}

provider "aiven" {
  api_token = var.aiven_api_token
}
