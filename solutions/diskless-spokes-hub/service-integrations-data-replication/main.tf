# // DATA REPLICATION : MM2 spoke service integration for Data Replication
resource "aiven_service_integration" "mm2-spoke-svc-integration-data-source-1" {
  project                  = var.aiven_project_name
  integration_type         = "kafka_mirrormaker"
  source_service_name      = aiven_kafka.spoke_kafka_1.service_name
  destination_service_name = aiven_kafka_mirrormaker.mm2_data_replication_spoke_1.service_name
  kafka_mirrormaker_user_config {
    cluster_alias = "aiven-spoke-data-source-cluster-1" //could use name suffix with region name 
    kafka_mirrormaker {
      producer_max_request_size = 66901452 // default
      producer_buffer_memory    = 33554432 // default, required size is that producer batch fits to buffer memory.
      producer_batch_size       = 12000
      producer_linger_ms        = 100
    }
  }
}

# // DATA REPLICATION : MM2 Hub service integration for Data Replication
resource "aiven_service_integration" "mm2-hub-svc-integration-data-destination" {
  project                  = var.aiven_project_name
  integration_type         = "kafka_mirrormaker"
  source_endpoint_id       = var.external_source_aiven_kafka_endpoint_id_euw1
  destination_service_name = aiven_kafka_mirrormaker.mm2_data_replication_spoke_1.service_name
  kafka_mirrormaker_user_config {
    cluster_alias = "aiven-hub-data-destination-cluster" // could suffix with region name
    kafka_mirrormaker {
      producer_max_request_size = 66901452 // default
      producer_buffer_memory    = 33554432 // default, required size is that producer batch fits to buffer memory.
      producer_batch_size       = 12000
      producer_linger_ms        = 100
    }
  }
}

# // DATA REPLICATION : spoke -> hub replication flow
resource "aiven_mirrormaker_replication_flow" "spoke_to_hub_data" {
  depends_on = [
    aiven_service_integration.mm2-spoke-svc-integration-data-source-1,
    aiven_service_integration.mm2-hub-svc-integration-data-destination
  ]

  project                             = var.aiven_project_name
  service_name                        = aiven_kafka_mirrormaker.mm2_data_replication_spoke_1.service_name
  source_cluster                      = "aiven-spoke-data-source-cluster-1"
  target_cluster                      = "aiven-hub-data-destination-cluster"
  replication_policy_class            = "org.apache.kafka.connect.mirror.IdentityReplicationPolicy"
  exactly_once_delivery_enabled       = var.data_replication_exactly_once_delivery_enabled
  sync_group_offsets_enabled          = true
  sync_group_offsets_interval_seconds = 10
  offset_syncs_topic_location         = "target"
  emit_heartbeats_enabled             = true
  enable                              = true
  replication_factor                  = var.data_replication_factor
  config_properties_exclude           = var.replication_config_properties_exclude
  topics                              = var.data_replication_topics
  topics_blacklist                    = var.replication_topics_blacklist
}
