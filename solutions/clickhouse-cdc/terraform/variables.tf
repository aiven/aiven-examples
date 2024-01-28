variable "aiven_project" {
  type    = string
  default = "felixwu-demo"
}

variable "cloud_name" {
  type    = string
  default = "google-us-west1"
}

variable "clickhouse_plan" {
  type    = string
  default = "startup-16"
}

variable "kafka_plan" {
  type    = string
  default = "business-4"
}

variable "pg_plan" {
  type    = string
  default = "startup-4"
}
