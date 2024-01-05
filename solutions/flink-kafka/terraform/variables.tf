variable "aiven_project" {
  type    = string
  default = "myproject"
}

variable "cloud_name" {
  type    = string
  default = "google-us-west1"
}

variable "kafka_plan" {
  type    = string
  default = "business-4"
}

variable "flink_plan" {
  type    = string
  default = "business-4"
}
