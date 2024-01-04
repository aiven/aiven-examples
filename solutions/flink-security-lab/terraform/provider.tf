terraform {
  required_providers {
    aiven = {
      source = "aiven/aiven"
    version = ">=4.0.0, < 5.0.0" }
  }
}

provider "aiven" {
  api_token = data.external.env.result["auth_token"]
}