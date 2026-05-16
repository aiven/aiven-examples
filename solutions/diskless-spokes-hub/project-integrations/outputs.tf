output "external_kafka_endpoint_id" {
  description = "ID of the Aiven external Kafka service integration endpoint"
  value       = aiven_service_integration_endpoint.external_kafka.id
}

output "external_kafka_endpoint_name" {
  description = "Configured endpoint name"
  value       = aiven_service_integration_endpoint.external_kafka.endpoint_name
}

output "aiven_kafka_source_example_endpoint_id" {
  description = "Set when example_aiven_source_kafka_service_name is non-empty; ID of the Aiven Kafka source example endpoint"
  value       = try(aiven_service_integration_endpoint.aiven_kafka_source_example[0].id, null)
}
