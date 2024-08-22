resource "aiven_service_integration" "mm2-primary-svc-integration" {
  project                  = var.aiven_project_name
  integration_type         = "kafka_mirrormaker"
  /////// If Source Kafka is then we will use internal service name instead of external endpoint
  //source_service_name      = var.source_kafka_service
  source_endpoint_id = var.external_source_strimzi_kafka_endpoint_id
  destination_service_name = var.mm2_service_name
  kafka_mirrormaker_user_config {
    cluster_alias = "strimzi-source-kafka-1"
    kafka_mirrormaker {
      producer_max_request_size = 66901452
      producer_buffer_memory = 33554432
      consumer_max_poll_records = 1000
      producer_batch_size = 32768
      producer_linger_ms = 100
    }
}
}
resource "aiven_service_integration" "mm2-backup-svc-integration" {
  project                  = var.aiven_project_name
  integration_type         = "kafka_mirrormaker"
  source_service_name      = var.destination_kafka_service
  destination_service_name = var.mm2_service_name
  kafka_mirrormaker_user_config {
    cluster_alias = "aiven-destination-kafka-1"
    kafka_mirrormaker {
      producer_max_request_size = 66901452
      producer_buffer_memory = 33554432
      consumer_max_poll_records = 1000
      producer_batch_size = 32768
      producer_linger_ms = 100
    }
  }
}
/*
resource "aiven_service_integration" "mm2-backup-svc-integration-2" {
  project                  = var.aiven_project_name
  integration_type         = "kafka_mirrormaker"
  source_endpoint_id = var.external_aiven_destination_kafka_service_1_endpoint_id
  //source_service_name      = var.external_aiven_destination_kafka_service_1
  destination_service_name = var.mm2_service_name
  kafka_mirrormaker_user_config {
    cluster_alias = "aiven-external-destination-kafka-2"
  }
}

resource "aiven_service_integration" "mm2-backup-svc-integration-3" {
  project                  = var.aiven_project_name
  integration_type         = "kafka_mirrormaker"
  source_endpoint_id = var.external_aiven_destination_kafka_service_1_endpoint_id
  //source_service_name      = var.external_aiven_destination_kafka_service_1
  destination_service_name = var.mm2_service_name
  kafka_mirrormaker_user_config {
    cluster_alias = "aiven-external-destination-kafka-3"
  }
} */

resource "time_sleep" "wait_180_seconds" {
  depends_on = [
    aiven_service_integration.mm2-primary-svc-integration,
    aiven_service_integration.mm2-backup-svc-integration,
    //aiven_service_integration.mm2-backup-svc-integration-2
  ]
  create_duration = "180s"
}

//Replication Flow - RF=3 --- This will be using Aiven Kafka Internal Service Integration as --- Check and match cluster_alias with target_cluster
resource "aiven_mirrormaker_replication_flow" "replication-flow-1" {
  depends_on = [
    time_sleep.wait_180_seconds,
  ]
  project                    = var.aiven_project_name
  service_name               = var.mm2_service_name
  source_cluster             = "strimzi-source-kafka-1"
  target_cluster             = "aiven-destination-kafka-1"
  replication_policy_class   = "org.apache.kafka.connect.mirror.IdentityReplicationPolicy"
  sync_group_offsets_enabled = true
  offset_syncs_topic_location = "target"
  emit_heartbeats_enabled    = true
  enable                     = false
  sync_group_offsets_interval_seconds = 1
  replication_factor = 3
  config_properties_exclude = ["follower\\.replication\\.throttled\\.replicas", "leader\\.replication\\.throttled\\.replicas", "message\\.timestamp\\.difference\\.max\\.ms", "message\\.timestamp\\.type"]
  topics = [
    "meta_test_topic_rf_3"
  ]
  topics_blacklist = [".*[\\-\\.]internal",".*\\.replica","__.*","connect.*"]
}

/*//Replication Flow - RF=2 --- This will be using Aiven Kafka External Service Integration --- Check and match cluster_alias with target_cluster
resource "aiven_mirrormaker_replication_flow" "replication-flow-ext-1" {
  depends_on = [
    time_sleep.wait_180_seconds,
  ]
  project                    = var.aiven_project_name
  service_name               = var.mm2_service_name
  source_cluster             = "strimzi-source-kafka-1"
  target_cluster             = "aiven-external-destination-kafka-2"
  replication_policy_class   = "org.apache.kafka.connect.mirror.IdentityReplicationPolicy"
  sync_group_offsets_enabled = true
  offset_syncs_topic_location = "target"
  emit_heartbeats_enabled    = true
  enable                     = true
  sync_group_offsets_interval_seconds = 1
  replication_factor = 2
  config_properties_exclude = ["follower\\.replication\\.throttled\\.replicas", "leader\\.replication\\.throttled\\.replicas", "message\\.timestamp\\.difference\\.max\\.ms", "message\\.timestamp\\.type"]
  topics = [
    "meta_test_topic_rf_2"
  ]
}

//Replication Flow - RF=1 --- This will be using Aiven Kafka External Service Integration --- Check and match cluster_alias with target_cluster
resource "aiven_mirrormaker_replication_flow" "replication-flow-ext-2" {
  depends_on = [
    time_sleep.wait_180_seconds,
  ]
  project                    = var.aiven_project_name
  service_name               = var.mm2_service_name
  source_cluster             = "strimzi-source-kafka-1"
  target_cluster             = "aiven-external-destination-kafka-3"
  replication_policy_class   = "org.apache.kafka.connect.mirror.IdentityReplicationPolicy"
  sync_group_offsets_enabled = true
  offset_syncs_topic_location = "target"
  emit_heartbeats_enabled    = true
  enable                     = true
  sync_group_offsets_interval_seconds = 1
  replication_factor = 1
  config_properties_exclude = ["follower\\.replication\\.throttled\\.replicas", "leader\\.replication\\.throttled\\.replicas", "message\\.timestamp\\.difference\\.max\\.ms", "message\\.timestamp\\.type"]
  topics = [
    "meta_test_topic_rf_1"
  ]
} */