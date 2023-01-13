terraform {
  required_providers {
    aiven = {
      source = "aiven/aiven"
      version = "3.11.0" }
  }
}

provider "aiven" {
  api_token = data.external.env.result["auth_token"]
}