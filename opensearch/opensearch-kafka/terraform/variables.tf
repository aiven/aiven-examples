variable aiven_api_token {}
variable aiven_project_name {}
variable cloud_name {
  type    = string
  default = "google-us-west1"
}
variable os_plan {
  type = string
  default = "startup-4"
}

variable kafka_plan {
  type    = string
  default = "business-4"
}