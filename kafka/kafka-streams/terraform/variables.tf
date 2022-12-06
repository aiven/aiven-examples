variable "aiven_project" {
  type    = string
  default = "my-project"
}

variable "aiven_service" {
  type    = string
  default = "kafka-streams"
}

variable "cloud_name" {
  type    = string
  default = "google-us-west1"
}

variable "kafka_plan" {
  type    = string
  default = "startup-2"
}
