variable "aiven_api_token" {
  description = "Aiven API token"
  type        = string
}

variable aiven_project_name {
  type = string
}

/*variable "source_kafka_service" {
  description = "Aiven Source Kafka Service"
  type        = string
  default = "source-aiven-kafka-service-name"
}*/

variable "external_source_aiven_kafka_endpoint_id_rf3_set1" {
  description = "Endpoint ID - Strimzi Source Kafka Service via External Integration"
  type        = string
  //default = "your-aiven-project-name/source-integration-endpoint-id"
}

# variable "external_source_strimzi_kafka_endpoint_id_rf2" {
#   description = "Endpoint ID - Strimzi Source Kafka Service via External Integration"
#   type        = string
#   //default     = "kafka-migration-labs/strimzi-kafka-external-endpoint-1-guid"
# }
# variable "external_source_strimzi_kafka_endpoint_id_rf3_set1" {
#   description = "Endpoint ID - Strimzi Source Kafka Service via External Integration"
#   type        = string
#   //default     = "kafka-migration-labs/strimzi-kafka-external-endpoint-2-guid"
# }

# variable "external_source_strimzi_kafka_endpoint_id_rf3_set2" {
#   description = "Endpoint ID - Strimzi Source Kafka Service via External Integration"
#   type        = string
#   //default     = "kafka-migration-labs/strimzi-kafka-external-endpoint-3-guid"
# }
variable "destination_kafka_service" {
  description = "Strimzi Source Kafka Service"
  type        = string
  //default = "destination-aiven-kafka-service-name"
}

# variable "aiven-labs-mm2-rf2" {
#   description = "Mirror Maker2 Service Name RF2"
#   type        = string
#   //default     = "aiven-labs-mm2-rf2"
# }

variable "aiven-labs-mm2-rf3-set1" {
  description = "Mirror Maker2 Service Name RF3 set 1"
  type        = string
  default     = "demo-mm2-rf3-set1"
}

# variable "aiven-labs-mm2-rf3-set2" {
#   description = "Mirror Maker2 Service Name RF3 set 2"
#   type        = string
#   //default     = "aiven-labs-mm2-rf3-set2"
# }