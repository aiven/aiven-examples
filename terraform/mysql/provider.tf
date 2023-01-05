terraform {
  required_providers {
    aiven = {
      source = "aiven/aiven"
    version = ">=2.8.1, <=3.10.0" }
    datadog = {
      source  = "DataDog/datadog"
    version = "3.12.0" }
  }
}

provider "aiven" {
  api_token = var.aiven_api_token
}

provider "datadog" {
  api_key = var.datadog_api_key
  app_key = var.datadog_app_key
}
