variable "aiven_project" {
  type    = string
}

variable "cloud_name" {
  type    = string
  default = "google-europe-west3"
}

variable "service_prefix" {
  type    = string
  default = ""
}

variable "postgres_plan" {
  type    = string
  default = "startup-4"
}

variable "kafka_plan" {
  type    = string
  default = "startup-2"
}

variable "kafka_connect_plan" {
  type    = string
  default = "startup-4"
}

variable "aws_region" {
  type    = string
  default = "eu-central-1"
}

variable "aws_access_key" {
  type    = string
  default = ""
}

variable "aws_secret_access_key" {
  type      = string
  sensitive = true
  default   = ""
}

variable "secret_name" {
  type    = string
  default = "test/aiven"
}

variable "secret_key" {
  type    = string
  default = "password"
}
