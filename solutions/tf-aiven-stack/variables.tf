variable "aiven_api_token" {
  type = string
}

variable "project" {
  type = string
}

variable "prefix" {
  type = string
}

variable "account" {
  type = string
}

variable "cloud_name" {
  type    = string
  default = "google-us-west1"
}

variable "kafka_plan_size" {
  type    = string
  default = "business-8"
}

variable "os_log_analytics_plan" {
  type    = string
  default = "business-64"
}

variable "os_log_internal_plan" {
  type    = string
  default = "business-16"
}

variable "os_disk_space" {
  type    = string
  default = "2100G"
}

variable "external_account_id" {
  type = string
}

variable "external_vpc_id" {
  type = string
}

variable "vpc_cidr_range" {
  type = string
}

variable "prom_name" {
  type    = string
  default = "prometheus"
}

variable "prom_username" {
  type = string
}

variable "prom_password" {
  type = string
}