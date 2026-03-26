variable "aiven_api_token" {
  description = "Aiven API token"
  type        = string
}
variable "aiven_project_name" {
  type = string
  default = "sa-inkless-gcp"
}
variable "service_prefix" {
  type = string
  default = "mp-demo"
}
variable "cloud_name_hub"{
  type = string
  default = "cce-cce56a315b8c0b-private-workload-us-west-2"
}

variable "cloud_name_spoke_1"{
  type = string
  default = "cce-cce56a315b8c0b-private-workload-us-west-2"
}

variable "hub_kafka_plan" {
  type = string
  default = "business-8-inkless"
}

variable "spoke_kafka_plan" {
  type = string
  default = "business-8-inkless"
}

variable "mm2_plan_hub_cluster" {
  type = string
  default = "business-4"
}

variable "mm2_plan_spoke_cluster" {
  type = string
  default = "business-4"
}