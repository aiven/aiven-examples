variable aiven_project_name {
  type = string
}

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