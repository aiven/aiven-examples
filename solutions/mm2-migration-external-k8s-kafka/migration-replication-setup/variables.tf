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

variable "external_source_strimzi_kafka_endpoint_id" {
  description = "Endpoint ID - Strimzi Source Kafka Service via External Integration"
  type        = string
  //default = "your-aiven-project-name/source-integration-endpoint-id"
}

variable "destination_kafka_service" {
  description = "Strimzi Source Kafka Service"
  type        = string
  //default = "destination-aiven-kafka-service-name"
}

variable "external_aiven_destination_kafka_service_1_endpoint_id" {
  description = "Endpoint ID - Aiven Kafka Destination Service via External Integration"
  type        = string
  //default = "your-aiven-project-name/source-integration-endpoint-id"
}

variable "mm2_service_name" {
  description = "Mirror Maker2 Service Name"
  type        = string
  //default = "your mm2 service name"
}