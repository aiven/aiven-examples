variable "aiven_api_token" {
  description = "Aiven API token"
  type        = string
  sensitive   = true
}

variable "aiven_project_name" {
  description = "Aiven project name"
  type        = string
}

variable "s3_warehouse_location" {
  description = "S3 warehouse location for Iceberg tables"
  type        = string
}

variable "snowflake_uri" {
  description = "Snowflake URI for Open Catalog"
  type        = string
}

variable "snowflake_warehouse" {
  description = "Snowflake warehouse name"
  type        = string
}

variable "snowflake_database" {
  description = "Snowflake database name"
  type        = string
} 