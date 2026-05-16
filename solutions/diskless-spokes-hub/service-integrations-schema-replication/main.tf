# // MM2 Hub service integration for Schema Replication --- This is local within the same VPC and hence it uses kafka service name
resource "aiven_service_integration" "mm2-hub-svc-integration-schema-source" {
project                  = var.aiven_project_name
integration_type         = "kafka_mirrormaker"
source_service_name      = aiven_kafka.hub_kafka.service_name
destination_service_name = aiven_kafka_mirrormaker.mm2_schema_replication_1.service_name
kafka_mirrormaker_user_config {
    cluster_alias = "aiven-hub-schema-produce-cluster"
    kafka_mirrormaker {
        producer_max_request_size = 66901452 // default
        producer_buffer_memory = 33554432 // default, required size is that producer batch fits to buffer memory.
        producer_batch_size = 12000
        producer_linger_ms = 100
    }
    }
}

# // MM2 spoke service integration for Schema Replication -- This integration has to talk over an external kafka or Aiven Kafka within a different VPC network it needs to be using service endpoint id
resource "aiven_service_integration" "mm2-spoke-svc-integration-schema-destination" {
project                  = var.aiven_project_name
integration_type         = "kafka_mirrormaker"
source_endpoint_id       = var.external_source_aiven_kafka_endpoint_id_use1
destination_service_name = aiven_kafka_mirrormaker.mm2_schema_replication_1.service_name
kafka_mirrormaker_user_config {
    cluster_alias = "aiven-spoke-schema-receiver-cluster"
    kafka_mirrormaker {
        producer_max_request_size = 66901452 // default
        producer_buffer_memory = 33554432 // default, required size is that producer batch fits to buffer memory.
        producer_batch_size = 12000 
        producer_linger_ms = 100
    }
    }
}