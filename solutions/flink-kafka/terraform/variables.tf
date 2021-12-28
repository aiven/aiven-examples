variable "aiven_api_token" {
  type    = string
  default = ""
}
variable "aiven_project" {
  type    = string
  default = "flink-demo"
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
