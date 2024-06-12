variable "aiven_api_token" {
  description = "Aiven API token"
  type        = string
}

variable "aiven_project_name" {
  type = string
}
variable "service_prefix" {
  type = string
}
variable "cloud_name_primary" {
  type = string
}

variable "mm2_plan" {
  type = string
}

variable "strimzi_bootstrap_url" {
  type = string
}

variable "aiven_kafka_bootstrap_url" {
  type = string
}