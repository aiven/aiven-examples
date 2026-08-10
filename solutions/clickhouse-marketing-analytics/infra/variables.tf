variable "aiven_api_token" {
  description = "Aiven API token (use an internal/demo project token)"
  type        = string
  sensitive   = true
}

variable "project" {
  description = "Aiven project name"
  type        = string
}

variable "cloud_name" {
  description = "Aiven cloud/region (shared by both services)"
  type        = string
  default     = "azure-southeastasia"
}

variable "clickhouse_plan" {
  description = "Aiven for ClickHouse plan"
  type        = string
  default     = "business-16"
}

variable "clickhouse_version" {
  description = "ClickHouse major version"
  type        = string
  default     = "26.3"
}

variable "clickhouse_service_name" {
  description = "ClickHouse service name"
  type        = string
  default     = "clickhouse-marketing-analytics"
}

variable "valkey_plan" {
  description = "Aiven for Valkey plan"
  type        = string
  default     = "business-8"
}

variable "valkey_version" {
  description = "Valkey major version"
  type        = string
  default     = "9.1"
}

variable "valkey_service_name" {
  description = "Valkey service name"
  type        = string
  default     = "valkey-ingest-buffer"
}
