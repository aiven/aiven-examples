variable "aiven_api_token" {
  description = "Aiven API token"
  type        = string
}

variable "aiven_source_project_name" {
  type = string
}

variable "aiven_destination_project_name" {
  type = string
}

variable "kafka_source_name" {
  type = string
}
variable "service_prefix" {
  type = string
}
variable "cloud_name_primary" {
  type = string
}

variable "mm2_plan_cluster_2" {
  type = string
}

variable "mm2_plan_cluster_3" {
  type = string
}

variable "aiven_source_bootstrap_url" {
  type = string
}

variable "dest_kafka_plan" {
  type = string
}