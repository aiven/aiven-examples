variable "aiven_api_token" {
  description = "Aiven API token (used by provider.tf)"
  type        = string
  sensitive   = true
}

variable "aiven_project_name" {
  description = "Aiven project where spoke Kafka, the data-replication MM2 service, and these integrations live"
  type        = string
}

variable "external_source_aiven_kafka_endpoint_id_euw1" {
  description = "Project-level external_kafka integration endpoint ID for reaching the hub Kafka cluster from MM2 (used as source_endpoint_id on mm2-hub-svc-integration-data-destination), e.g. project-name/endpoint-uuid from project-integrations"
  type        = string
}

variable "external_source_aiven_kafka_endpoint_id_use1" {
  description = "Same naming convention as service-integrations-schema-replication; optional here because current main.tf does not reference it. Defaults to null for future or symmetric tfvars layouts."
  type        = string
  default     = null
  nullable    = true
}
