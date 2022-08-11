############## Kafka Primary ##############

resource "aiven_kafka" "kafka-primary" {
  project                 = var.aiven_project_name
  cloud_name              = var.cloud_name_primary
  plan                    = var.kafka_plan
  service_name            = "${var.service_prefix}-kafka-primary"
  maintenance_window_dow  = "monday"
  maintenance_window_time = "10:00:00"
  kafka_user_config {
    kafka_connect   = true
    kafka_rest      = true
    schema_registry = true
    kafka_version   = var.kafka_version
    kafka_authentication_methods {
      certificate = true
      sasl        = true
    }
    kafka {
      group_max_session_timeout_ms = 70000
      log_retention_bytes          = 1000000000
      auto_create_topics_enable    = true
    }
  }
}

resource "aiven_kafka_topic" "topic-a" {
  project      = var.aiven_project_name
  service_name = aiven_kafka.kafka-primary.service_name
  topic_name   = "topicA"
  partitions   = 3
  replication  = 2
}

resource "aiven_kafka_topic" "topic-b" {
  project      = var.aiven_project_name
  service_name = aiven_kafka.kafka-primary.service_name
  topic_name   = "topicB"
  partitions   = 3
  replication  = 2
}

resource "aiven_kafka_user" "kafka-user-a" {
  project      = var.aiven_project_name
  service_name = aiven_kafka.kafka-primary.service_name
  username     = "userA"
}

resource "aiven_kafka_user" "kafka-user-b" {
  project      = var.aiven_project_name
  service_name = aiven_kafka.kafka-primary.service_name
  username     = "userB"
}


resource "aiven_kafka_acl" "topic-a-acl" {
  project      = var.aiven_project_name
  service_name = aiven_kafka.kafka-primary.service_name
  topic        = "topicA"
  permission   = "readwrite"
  username     = "userA"
}

resource "aiven_kafka_acl" "topic-b-acl" {
  project      = var.aiven_project_name
  service_name = aiven_kafka.kafka-primary.service_name
  topic        = "topicB"
  permission   = "write"
  username     = "userB"
}


############## Kafka Backup ##############
resource "aiven_kafka" "kafka-backup" {
  project                 = var.aiven_project_name
  cloud_name              = var.cloud_name_backup
  plan                    = var.kafka_plan
  service_name            = "${var.service_prefix}-kafka-backup"
  maintenance_window_dow  = "monday"
  maintenance_window_time = "10:00:00"
  kafka_user_config {
    kafka_connect   = true
    kafka_rest      = true
    schema_registry = true
    kafka_version   = var.kafka_version
  }
}

############## MirrorMaker ##############
resource "aiven_kafka_mirrormaker" "mm2" {
  project      = var.aiven_project_name
  cloud_name   = var.cloud_name_primary
  plan         = var.mm2_plan
  service_name = "${var.service_prefix}-mm2"

  kafka_mirrormaker_user_config {
    kafka_mirrormaker {
      refresh_groups_interval_seconds = 300
      refresh_topics_enabled          = true
      refresh_topics_interval_seconds = 300
    }
  }
}

resource "aiven_service_integration" "mm2-primary-svc-integration" {
  project                  = var.aiven_project_name
  integration_type         = "kafka_mirrormaker"
  source_service_name      = aiven_kafka.kafka-primary.service_name
  destination_service_name = aiven_kafka_mirrormaker.mm2.service_name
  kafka_mirrormaker_user_config {
    cluster_alias = "primary"
  }
}

resource "aiven_service_integration" "mm2-backup-svc-integration" {
  project                  = var.aiven_project_name
  integration_type         = "kafka_mirrormaker"
  source_service_name      = aiven_kafka.kafka-backup.service_name
  destination_service_name = aiven_kafka_mirrormaker.mm2.service_name
  kafka_mirrormaker_user_config {
    cluster_alias = "backup"
  }
}

resource "aiven_mirrormaker_replication_flow" "dr-replication-flow" {
  project                    = var.aiven_project_name
  service_name               = aiven_kafka_mirrormaker.mm2.service_name
  source_cluster             = "primary"
  target_cluster             = "backup"
  replication_policy_class   = "org.apache.kafka.connect.mirror.IdentityReplicationPolicy"
  sync_group_offsets_enabled = true
  emit_heartbeats_enabled    = true
  enable                     = true

  topics = [
    ".*"
  ]
}
