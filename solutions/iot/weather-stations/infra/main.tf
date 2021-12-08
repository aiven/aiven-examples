
terraform {
  required_providers {
    aiven = {
      source = "aiven/aiven"
      version = "2.3.2"
    }
  }
}

provider "aiven" {
  api_token = var.avn_api_token
}
