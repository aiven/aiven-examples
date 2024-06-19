variable "aiven_project" {
  type = string
  default = "testproject-ecfq"
}
variable "service_prefix" {
  type = string
  default = ""
}
variable "cloud_name" {
  type = string
  default = "google-europe-west10"
}

variable "mm2_plan" {
  type = string
  default = "startup-4"
}

variable "kafka_plan" {
  type = string
  default = "startup-2"
}
