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

variable "data_replication_topics" {
  description = "Java regular expressions for business data topics to replicate from spoke to hub. Keep this list narrow to avoid mirroring unrelated topics."
  type        = list(string)
}

variable "replication_topics_blacklist" {
  description = "Java regular expressions for topics excluded from MM2 replication flows."
  type        = list(string)
  default     = [".*[\\-\\.]internal", ".*\\.replica", "__.*", "connect.*"]
}

variable "replication_config_properties_exclude" {
  description = "Topic configuration properties and regular expressions that MM2 should not replicate."
  type        = list(string)
  default     = ["follower\\.replication\\.throttled\\.replicas", "leader\\.replication\\.throttled\\.replicas", "message\\.timestamp\\.difference\\.max\\.ms", "message\\.timestamp\\.type"]
}

variable "data_replication_exactly_once_delivery_enabled" {
  description = "Enable exactly-once delivery for the spoke-to-hub data replication flow."
  type        = bool
  default     = true
}

variable "data_replication_factor" {
  description = "Replication factor used for MM2 internal topics created for the data replication flow."
  type        = number
  default     = 3
}
