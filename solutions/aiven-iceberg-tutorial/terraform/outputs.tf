output "kafka_bootstrap_servers" {
  description = "Kafka bootstrap servers"
  value       = aiven_kafka.iceberg_kafka.service_uri
} 