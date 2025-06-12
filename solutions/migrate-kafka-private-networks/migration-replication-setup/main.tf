# resource "aiven_service_integration" "mm2-primary-svc-integration-rf2" {
#   project                  = var.aiven_project_name
#   integration_type         = "kafka_mirrormaker"
#   source_endpoint_id       = var.source_kafka_service
#   destination_service_name = var.aiven-labs-mm2-rf2
#   kafka_mirrormaker_user_config {
#     cluster_alias = "aiven-source-kafka-rf2"
#     kafka_mirrormaker {
#       consumer_max_poll_records = 500
#       //producer_max_request_size = 66901452
#       //producer_buffer_memory = 33554432
#       //producer_batch_size = 32768
#       //producer_linger_ms = 100
#     }
#   }
# }

# // Large suite of topics with RF=3
# resource "aiven_service_integration" "mm2-primary-svc-integration-rf3-set1" {
#   project                  = var.aiven_project_name
#   integration_type         = "kafka_mirrormaker"
#   source_service_name       = var.source_kafka_service
#   destination_service_name = var.aiven-labs-mm2-rf3-set1
#   kafka_mirrormaker_user_config {
#     cluster_alias = "aiven-source-kafka-rf3-set1"
#     kafka_mirrormaker {
#       consumer_max_poll_records = 500
#       //producer_max_request_size = 66901452
#       //producer_buffer_memory = 33554432
#       //producer_batch_size = 32768
#       //producer_linger_ms = 100
#     }
#   }
# }

# // One high throughput low latency topic, one of the patterns is ~500 records per second per partition.
# resource "aiven_service_integration" "mm2-primary-svc-integration-rf3-set2" {
#   project                  = var.aiven_project_name
#   integration_type         = "kafka_mirrormaker"
#   source_endpoint_id       = var.source_kafka_service
#   destination_service_name = var.aiven-labs-mm2-rf3-set2
#   kafka_mirrormaker_user_config {
#     cluster_alias = "aiven-source-kafka-rf3-set2"
#     kafka_mirrormaker {
#       consumer_max_poll_records = 500
#       //producer_max_request_size = 66901452
#       //producer_buffer_memory = 33554432
#       //producer_batch_size = 32768
#       //producer_linger_ms = 100
#     }
#   }
# }

# // Does not benefit from performance tuning, traffic is low
# resource "aiven_service_integration" "mm2-backup-svc-integration-rf2" {
#   project                  = var.aiven_project_name
#   integration_type         = "kafka_mirrormaker"
#   source_service_name      = var.destination_kafka_service
#   destination_service_name = var.aiven-labs-mm2-rf2
#   kafka_mirrormaker_user_config {
#     cluster_alias = "aiven-destination-kafka-rf2"
#     kafka_mirrormaker {
#       producer_max_request_size = 66901452 // default
#       producer_buffer_memory = 33554432 // default
#       producer_batch_size = 16384 // default
#       producer_linger_ms = 100
#     }
#   }
# }

# // Big list of topics
# // ~180000 records per second
# // 192 tasks => 180000/192 = 938 <- max poll
# resource "aiven_service_integration" "mm2-backup-svc-integration-rf3-set1" {
#   project                  = var.aiven_project_name
#   integration_type         = "kafka_mirrormaker"
#   destination_service_name   = var.destination_kafka_service
#   source_service_name = var.aiven-labs-mm2-rf3-set1
#   kafka_mirrormaker_user_config {
#     cluster_alias = "aiven-destination-kafka-rf3-set1"
#     kafka_mirrormaker {
#       producer_max_request_size = 66901452 // default
#       producer_buffer_memory = 33554432 // default
#       producer_batch_size = 450000
#       producer_linger_ms = 1000
#     }
#   }
# }

# // The high throughput low latency topic, pattern is ~500 records per second per partition.
# resource "aiven_service_integration" "mm2-backup-svc-integration-rf3-set2" {
#   project                  = var.aiven_project_name
#   integration_type         = "kafka_mirrormaker"
#   source_service_name      = var.destination_kafka_service
#   destination_service_name = var.aiven-labs-mm2-rf3-set2
#   kafka_mirrormaker_user_config {
#     cluster_alias = "aiven-destination-kafka-rf3-set2"
#     kafka_mirrormaker {
#       producer_max_request_size = 66901452 // default
#       producer_buffer_memory = 33554432 // default, required size is that producer batch fits to buffer memory.
#       producer_batch_size = 120000 // average record is 480 bytes, max poll records * average record.
#       producer_linger_ms = 1000
#     }
#   }
# }

# resource "time_sleep" "wait_180_seconds" {
#   depends_on = [
#     # aiven_service_integration.mm2-primary-svc-integration-rf2,
#     aiven_service_integration.mm2-primary-svc-integration-rf3-set1,
#     # aiven_service_integration.mm2-primary-svc-integration-rf3-set1,
#     # aiven_service_integration.mm2-backup-svc-integration-rf2,
#     aiven_service_integration.mm2-backup-svc-integration-rf3-set1,
#     # aiven_service_integration.mm2-backup-svc-integration-rf3-set2
#   ]
#   create_duration = "180s"
# }

# //Replication Flow - RF=2 --- This will be using Aiven Kafka Internal Service Integration as --- Check and match cluster_alias with target_cluster
# resource "aiven_mirrormaker_replication_flow" "replication-flow-rf2" {
#   depends_on = [
#     time_sleep.wait_180_seconds,
#   ]
#   project                     = var.aiven_project_name
#   service_name                = var.aiven-labs-mm2-rf2
#   source_cluster              = "aiven-source-kafka-rf2"
#   target_cluster              = "aiven-destination-kafka-rf2"
#   replication_policy_class    = "org.apache.kafka.connect.mirror.IdentityReplicationPolicy"
#   sync_group_offsets_enabled  = true
#   offset_syncs_topic_location = "target"
#   emit_heartbeats_enabled     = true
#   enable                      = true
#   sync_group_offsets_interval_seconds = 1
#   replication_factor          = 2
#   config_properties_exclude   = ["follower\\.replication\\.throttled\\.replicas", "leader\\.replication\\.throttled\\.replicas", "message\\.timestamp\\.difference\\.max\\.ms", "message\\.timestamp\\.type"]
#   topics = [
#     "rf2-topic-1",
#     "rf2-topic-2"
#   ]
#   topics_blacklist = [".*[\\-\\.]internal",".*\\.replica","__.*","connect.*"]
# }

# //Replication Flow - RF=3 --- This will be using Aiven Kafka Internal Service Integration as --- Check and match cluster_alias with target_cluster
# resource "aiven_mirrormaker_replication_flow" "replication-flow-rf3-set1" {
#   depends_on = [
#     time_sleep.wait_180_seconds,
#   ]
#   project                     = var.aiven_project_name
#   service_name                = var.aiven-labs-mm2-rf3-set1
#   source_cluster              = "aiven-source-kafka-rf3-set1"
#   target_cluster              = "aiven-destination-kafka-rf3-set1" 
#   replication_policy_class    = "org.apache.kafka.connect.mirror.IdentityReplicationPolicy"
#   sync_group_offsets_enabled  = true
#   offset_syncs_topic_location = "target"
#   emit_heartbeats_enabled     = true
#   enable                      = true
#   sync_group_offsets_interval_seconds = 1
#   replication_factor          = 3
#   config_properties_exclude   = ["follower\\.replication\\.throttled\\.replicas", "leader\\.replication\\.throttled\\.replicas", "message\\.timestamp\\.difference\\.max\\.ms", "message\\.timestamp\\.type"]
#   topics = [
#     "product"
#   ]
#   topics_blacklist = [".*[\\-\\.]internal",".*\\.replica","__.*","connect.*"]
# }

# //Replication Flow - RF=3 --- This will be using Aiven Kafka Internal Service Integration as --- Check and match cluster_alias with target_cluster
# resource "aiven_mirrormaker_replication_flow" "replication-flow-rf3-set2" {
#   depends_on = [
#     time_sleep.wait_180_seconds,
#   ]
#   project                     = var.aiven_project_name
#   service_name                = var.aiven-labs-mm2-rf3-set2
#   source_cluster              = "aiven-source-kafka-rf3-set2"
#   target_cluster              = "aiven-destination-kafka-rf3-set2"
#   replication_policy_class    = "org.apache.kafka.connect.mirror.IdentityReplicationPolicy"
#   sync_group_offsets_enabled  = true
#   offset_syncs_topic_location = "target"
#   emit_heartbeats_enabled     = true
#   enable                      = true
#   sync_group_offsets_interval_seconds = 1
#   replication_factor          = 3
#   config_properties_exclude   = ["follower\\.replication\\.throttled\\.replicas", "leader\\.replication\\.throttled\\.replicas", "message\\.timestamp\\.difference\\.max\\.ms", "message\\.timestamp\\.type"]
#   topics = [
#     "rf3-set2-topic-1-mtseries"
#   ]
#   topics_blacklist = [".*[\\-\\.]internal",".*\\.replica","__.*","connect.*"]
# }


// Large suite of topics with RF=3
resource "aiven_service_integration" "mm2-primary-svc-integration-rf3-set1" {
  project                  = var.aiven_project_name
  integration_type         = "kafka_mirrormaker"
  source_endpoint_id = var.external_source_kafka_endpoint_id
  destination_service_name = var.aiven-labs-mm2-rf3-set1
  kafka_mirrormaker_user_config {
    cluster_alias = "aiven-source-kafka-rf3-set1"
    kafka_mirrormaker {
      consumer_max_poll_records = 500
      //producer_max_request_size = 66901452
      //producer_buffer_memory = 33554432
      //producer_batch_size = 32768
      //producer_linger_ms = 100
    }
  }
}

resource "aiven_service_integration" "mm2-backup-svc-integration-rf3-set1" {
  project                  = var.aiven_project_name
  integration_type         = "kafka_mirrormaker"
  destination_service_name   = var.aiven-labs-mm2-rf3-set1
  source_endpoint_id = var.destination_kafka_endpoint_id
  kafka_mirrormaker_user_config {
    cluster_alias = "aiven-destination-kafka-rf3-set1"
    kafka_mirrormaker {
      producer_max_request_size = 66901452 // default
      producer_buffer_memory = 33554432 // default
      producer_batch_size = 450000
      producer_linger_ms = 1000
    }
  }
}

resource "time_sleep" "wait_180_seconds" {
  depends_on = [
    # aiven_service_integration.mm2-primary-svc-integration-rf2,
    aiven_service_integration.mm2-primary-svc-integration-rf3-set1,
    # aiven_service_integration.mm2-primary-svc-integration-rf3-set1,
    # aiven_service_integration.mm2-backup-svc-integration-rf2,
    aiven_service_integration.mm2-backup-svc-integration-rf3-set1,
    # aiven_service_integration.mm2-backup-svc-integration-rf3-set2
  ]
  create_duration = "180s"
}

//Replication Flow - RF=3 --- This will be using Aiven Kafka Internal Service Integration as --- Check and match cluster_alias with target_cluster
resource "aiven_mirrormaker_replication_flow" "replication-flow-rf3-set1" {
  depends_on = [
    time_sleep.wait_180_seconds,
  ]
  project                     = var.aiven_project_name
  service_name                = var.aiven-labs-mm2-rf3-set1
  source_cluster              = "aiven-source-kafka-rf3-set1"
  target_cluster              = "aiven-destination-kafka-rf3-set1" 
  replication_policy_class    = "org.apache.kafka.connect.mirror.IdentityReplicationPolicy"
  sync_group_offsets_enabled  = true
  offset_syncs_topic_location = "target"
  emit_heartbeats_enabled     = true
  enable                      = true
  sync_group_offsets_interval_seconds = 1
  replication_factor          = 3
  config_properties_exclude   = ["follower\\.replication\\.throttled\\.replicas", "leader\\.replication\\.throttled\\.replicas", "message\\.timestamp\\.difference\\.max\\.ms", "message\\.timestamp\\.type"]
  topics = [
    "product"
  ]
  topics_blacklist = [".*[\\-\\.]internal",".*\\.replica","__.*","connect.*"]
}