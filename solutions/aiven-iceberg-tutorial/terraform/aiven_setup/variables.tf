variable "aiven_project_name" {
  description = "Aiven project name"
  type        = string
}

variable "aiven_api_token" {
  description = "Aiven API token"
  type        = string
}

variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-west-2"
}

variable "cloud_name" {
  description = "Cloud provider region"
  type        = string
  default     = "aws-us-west-2"
}

variable "snowflake_client_id" {
  description = "Snowflake client id"
  type        = string
}

variable "snowflake_client_secret" {
  description = "Snowflake client secret"
  type        = string
}

variable "iceberg_catalog_tables_config" {
  description = "Iceberg tables configuration"
  type        = string
}

variable "iceberg_catalog_name" {
  description = "Iceberg catalog name"
  type        = string
}

variable "iceberg_control_topic" {
  description = "Iceberg control topic name"
  type        = string
  default     = "control-iceberg"
}

variable "cdc_orders_topic" {
  description = "Debezium CDC output topic the Iceberg sink consumes (<topic.prefix>.<schema>.<table>)"
  type        = string
  default     = "live_orders.public.orders"
}

variable "iceberg_table_id_columns" {
  description = "Comma-separated columns recorded as the row identity (primary key) on auto-created tables — metadata only; the sink always appends"
  type        = string
  default     = "order_id"
}

variable "iceberg_catalog_uri" {
  description = "Iceberg catalog URI"
  type        = string
}

variable "iceberg_catalog_scope" {
  description = "Iceberg catalog scope with format PRINCIPAL_ROLE:<role>"
  type        = string
}

variable "iceberg_catalog_region" {
  description = "Iceberg catalog region"
  type        = string
  default     = "us-west-2"
}

variable "aws_access_key_id" {
  description = "S3 access key for Iceberg"
  type        = string
}

variable "aws_secret_access_key" {
  description = "S3 secret key for Iceberg"
  type        = string
} 

variable "aiven_kafka_name" {
  description = "Aiven Kafka service name"
  type        = string
}