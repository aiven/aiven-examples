variable "aiven_api_token" {
  description = "Aiven API token (used by provider.tf)"
  type        = string
  sensitive   = true
}

variable "aiven_project_name" {
  description = "Aiven project where hub Kafka, MM2 schema replication service, and integrations live"
  type        = string
}

variable "external_source_aiven_kafka_endpoint_id_use1" {
  description = "ID of the project-level external_kafka integration endpoint (same value as replication-setup / project-integrations output, e.g. project-name/endpoint-uuid)"
  type        = string
}

variable "external_source_aiven_kafka_endpoint_id_euw1" {
  description = "Same shape as service-integrations-data-replication; optional here because schema main.tf does not reference it unless you add a second integration."
  type        = string
  default     = null
  nullable    = true
}
