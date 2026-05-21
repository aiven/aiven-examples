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

variable "schema_replication_topics" {
  description = "Java regular expressions for schema topics to replicate from hub to spoke."
  type        = list(string)
  default     = ["_schemas"]
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

variable "schema_replication_exactly_once_delivery_enabled" {
  description = "Enable exactly-once delivery for the hub-to-spoke schema replication flow."
  type        = bool
  default     = true
}

variable "schema_replication_factor" {
  description = "Replication factor used for MM2 internal topics created for the schema replication flow."
  type        = number
  default     = 3
}
