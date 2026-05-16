terraform {
  required_providers {
    aiven = {
      source  = "aiven/aiven"
      version = "~> 4.0"
    }
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aiven" {
  api_token = var.aiven_api_token
}

provider "aws" {
  region = var.aws_region
}
