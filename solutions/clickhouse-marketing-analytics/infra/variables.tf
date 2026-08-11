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
  default     = "azure-indonesia-central"
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

variable "thanos_plan" {
  description = "Aiven for Metrics (Thanos) plan"
  type        = string
  default     = "startup-4"
}

variable "thanos_service_name" {
  description = "Thanos service name"
  type        = string
  default     = "metrics-ingest-bench"
}

variable "grafana_plan" {
  description = "Aiven for Grafana plan (startup-1 is not offered in azure-indonesia-central; startup-8 is)"
  type        = string
  default     = "startup-8"
}

# Grafana is only a UI - if your region lacks a suitable plan, parking it in
# a nearby region changes nothing about the benchmark, only dashboard-refresh
# latency. Empty = same region as everything else.
variable "grafana_cloud_name" {
  description = "Region for Grafana. Empty = same as cloud_name."
  type        = string
  default     = ""
}

variable "grafana_service_name" {
  description = "Grafana service name"
  type        = string
  default     = "grafana-ingest-bench"
}
