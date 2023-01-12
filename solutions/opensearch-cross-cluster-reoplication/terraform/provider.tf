terraform {
  required_providers {
    aiven = {
      source = "aiven/aiven"
      version = ">= 2.5.0, < 3.0.0" }
  }
}

provider "aiven" {
  api_token = data.external.env.result["auth_token"]
}