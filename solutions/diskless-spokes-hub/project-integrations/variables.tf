variable "aiven_api_token" {
  description = "Aiven API token"
  type        = string
  sensitive   = true
}

variable "aiven_project_name" {
  description = "Aiven project where the integration endpoint is created"
  type        = string
}

variable "external_kafka_endpoint_name" {
  description = "Name of the project-level external Kafka integration endpoint"
  type        = string
}

variable "external_kafka_bootstrap_servers" {
  description = "Kafka bootstrap servers (comma-separated host:port list). Non-secret; keep credentials only in Secrets Manager."
  type        = string
}

variable "aws_region" {
  description = "AWS region for Secrets Manager"
  type        = string
}

variable "external_kafka_credentials_secret_id" {
  description = "Secrets Manager secret id or ARN holding JSON with SASL credentials (and optional ssl_ca_cert)"
  type        = string
}

variable "external_kafka_ssl_ca_cert" {
  description = "Optional PEM CA bundle as a literal string. If empty, use ssl_ca_cert from the secret JSON when present."
  type        = string
  sensitive   = true
  default     = null
}

variable "example_aiven_source_kafka_service_name" {
  description = "Optional. When set, creates an example aiven_service_integration_endpoint that uses an existing Aiven Kafka service as an external_kafka source (SASL_SSL + SCRAM-SHA-256)."
  type        = string
  default     = null
  nullable    = true
}

variable "example_aiven_source_kafka_project_name" {
  description = "Project that owns the source Kafka service. Defaults to aiven_project_name when example is enabled."
  type        = string
  default     = null
  nullable    = true
}

variable "example_aiven_kafka_source_endpoint_name" {
  description = "endpoint_name for the optional Aiven-Kafka-as-source example endpoint"
  type        = string
  default     = "aiven-kafka-source-example"
}
