variable "project" {
  type = string
}

variable "prefix" {
  type = string
}

variable "cloud_name" {
  type = string
}

variable "os_log_integration_plan" {
  type    = string
  default = "startup-16"
}

variable "m3db_metrics_integration_plan" {
  type    = string
  default = "business-8"
}

variable "grafana_integration_plan" {
  type    = string
  default = "startup-8"
}

variable "maint_dow" {
  type    = string
  default = "saturday"
}

variable "maint_time" {
  type    = string
  default = "10:00:00"
}

variable "m3db_version" {
  type    = string
  default = "1.5"
}

variable "prom_name" {
  type = string
}

variable "prom_username" {
  type = string
}

variable "prom_password" {
  type = string
}

variable "svcs" {}
//variable "vpc_id" {}