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
      producer_buffer_memory    = 33554432 // default, required size is that producer batch fits to buffer memory.
      producer_batch_size       = 12000
      producer_linger_ms        = 100
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
      producer_buffer_memory    = 33554432 // default, required size is that producer batch fits to buffer memory.
      producer_batch_size       = 12000
      producer_linger_ms        = 100
    }
  }
}

# // SCHEMA REPLICATION : hub -> spoke replication flow
resource "aiven_mirrormaker_replication_flow" "hub_to_spoke_schema" {
  depends_on = [
    aiven_service_integration.mm2-hub-svc-integration-schema-source,
    aiven_service_integration.mm2-spoke-svc-integration-schema-destination
  ]

  project                             = var.aiven_project_name
  service_name                        = aiven_kafka_mirrormaker.mm2_schema_replication_1.service_name
  source_cluster                      = "aiven-hub-schema-produce-cluster"
  target_cluster                      = "aiven-spoke-schema-receiver-cluster"
  replication_policy_class            = "org.apache.kafka.connect.mirror.IdentityReplicationPolicy"
  exactly_once_delivery_enabled       = var.schema_replication_exactly_once_delivery_enabled
  sync_group_offsets_enabled          = true
  sync_group_offsets_interval_seconds = 10
  offset_syncs_topic_location         = "target"
  emit_heartbeats_enabled             = true
  enable                              = true
  replication_factor                  = var.schema_replication_factor
  config_properties_exclude           = var.replication_config_properties_exclude
  topics                              = var.schema_replication_topics
  topics_blacklist                    = var.replication_topics_blacklist
}