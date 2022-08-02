variable "prefix" {
  type = string
}

variable "project" {
  type = string
}

variable "cloud_name" {
  type = string
}

variable "kafka_plan_size" {
  type = string
}

variable "os_version" {
  type    = string
  default = "1"
}

variable "kafka_version" {
  type    = string
  default = "3.2"
}

variable "os_log_analytics_plan" {
  type = string
}

variable "os_log_internal_plan" {
  type = string
}

variable "opensearch_logs_total_disk" {
  type = string
}

variable "maint_dow" {
  type    = string
  default = "monday"
}

variable "maint_time" {
  type    = string
  default = "23:00:00"
}

variable "ip_filter" {}
variable "vpc_id" {}