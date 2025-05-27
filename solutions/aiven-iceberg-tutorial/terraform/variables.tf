variable "aiven_project_name" {
  description = "Aiven project name"
  type        = string
}

variable "aiven_api_token" {
  description = "Aiven API token"
  type        = string
  sensitive   = true
}

variable "iceberg_sink_name" {
  description = "Iceberg sink name"
  type        = string
  default     = "iceberg-sink"
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

variable "iceberg_kafka_connect_service_name" {
  description = "Iceberg Kafka connect service name"
  type        = string
  default     = "iceberg-kafka-connect"
}

variable "snowflake_access_key_id" {
  description = "S3 access key id"
  type        = string
}

variable "snowflake_secret_access_key" {
  description = "S3 secret access key"
  type        = string
  sensitive   = true
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

variable "iceberg_tables_config" {
  description = "Iceberg tables configuration"
  type        = string
  default     = "spark_demo.product"
}

variable "iceberg_catalog_name" {
  description = "Iceberg catalog name"
  type        = string
  default     = "icebergdoyo"
}

variable "iceberg_control_topic" {
  description = "Iceberg control topic name"
  type        = string
  default     = "control-iceberg"
}

variable "iceberg_catalog_uri" {
  description = "Iceberg catalog URI"
  type        = string
  default     = "https://aqb65601.us-west-2.snowflakecomputing.com/polaris/api/catalog"
}

variable "iceberg_catalog_warehouse" {
  description = "Iceberg catalog warehouse"
  type        = string
  default     = "icebergdoyo"
}

variable "iceberg_catalog_credential" {
  description = "Iceberg catalog credential"
  type        = string
  sensitive   = true
}

variable "iceberg_catalog_scope" {
  description = "Iceberg catalog scope"
  type        = string
  default     = "PRINCIPAL_ROLE:TestPrincipalDemo"
}

variable "iceberg_catalog_region" {
  description = "Iceberg catalog region"
  type        = string
  default     = "us-west-2"
}

variable "iceberg_s3_access_key" {
  description = "S3 access key for Iceberg"
  type        = string
  sensitive   = true
}

variable "iceberg_s3_secret_key" {
  description = "S3 secret key for Iceberg"
  type        = string
  sensitive   = true
}

variable "iceberg_kafka_bootstrap_servers" {
  description = "Kafka bootstrap servers for Iceberg"
  type        = string
  default     = "iceberg-kafka-dyoung-demo.c.aivencloud.com:23283"
} 