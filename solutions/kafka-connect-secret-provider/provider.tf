terraform {
  required_providers {
    aiven = {
      source  = "aiven/aiven"
      version = ">=4.20.0, < 5.0.0"
    }
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    env = {
      source  = "tchupp/env"
      version = "0.0.2"
    }
  }
}

provider "aiven" {
  api_token = data.external.env.result["auth_token"]
}

provider "aws" {
  region     = var.aws_region
  access_key = local.aws_access_key
  secret_key = local.aws_secret_access_key
}
