terraform {
  required_providers {
    aiven = {
      source  = "aiven/aiven"
      version = ">=3.0.0, <4.0.0" 
    }
  }
}

# Initialize provider.
provider "aiven" {
  api_token = var.aiven_api_token
}
