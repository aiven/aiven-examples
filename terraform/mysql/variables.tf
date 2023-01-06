variable "aiven_api_token" {
  description = "Aiven console API token"
  type        = string
}

variable "project_name" {
  description = "Aiven console project name"
  type        = string
}

variable "cloud_name" {
  type    = string
  default = "google-us-west1"
}

variable "mysql_plan" {
  type    = string
  default = "business-4"
}

variable "endpoint_name" {
  type    = string
  default = "my-Datadog"
}

variable "datadog_api_key" {
  description = "API Key for the Datadog Agent to submit metrics to Datadog"
  sensitive   = true
  type        = string
}

variable "datadog_app_key" {
  description = "APP Key gives users access to Datadog’s programmatic API"
  sensitive   = true
  type        = string
}

variable "datadog_site" {
  default = "datadoghq.com"
  type    = string
}

variable "tag" {
  description = "Custom endpoint tag"
  type        = string
  default     = "environment:dev"
}

variable "mysql_service" {
  description = "Service name for MySQL"
  type        = string
  default     = "mysql-datadog"
}
