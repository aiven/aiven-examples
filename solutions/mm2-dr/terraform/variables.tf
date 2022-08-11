variable aiven_api_token {
  type = string
}

variable aiven_project_name {
  type = string
}

variable cloud_name_primary {
  type = string
  default = "aws-us-east-1"
}

variable cloud_name_backup {
  type = string
  default = "aws-us-east-2"
}

variable kafka_plan {
  type = string
  default = "business-8"
}

variable mm2_plan {
  type = string
  default = "business-8"
}

variable service_prefix {
  type = string
  default = "dr-arch"
}

variable kafka_version {
  type    = string
  default = "3.1"
}