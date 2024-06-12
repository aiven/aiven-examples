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
  default = "hv-ingest-test"
}*/

variable "external_source_strimzi_kafka_endpoint_id" {
  description = "Endpoint ID - Strimzi Source Kafka Service via External Integration"
  type        = string
  //default = "mparikh-demo/c725dd4a-23d4-435a-baa2-e5a614aee170"
  //default = "your-aiven-project-name/source-integration-endpoint-id"
}

variable "destination_kafka_service" {
  description = "Strimzi Source Kafka Service"
  type        = string
  //default = "kafka-oci-ashburn"
}

variable "external_aiven_destination_kafka_service_1_endpoint_id" {
  description = "Endpoint ID - Aiven Kafka Destination Service via External Integration"
  type        = string
  //default = "mparikh-demo/c725dd4a-23d4-435a-baa2-e5a614aee170"
  //default = "your-aiven-project-name/source-integration-endpoint-id"
}

variable "mm2_service_name" {
  description = "Mirror Maker2 Service Name"
  type        = string
  //default = "your mm2 service name"
}