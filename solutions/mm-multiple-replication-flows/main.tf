
## INFRA ##

resource "aiven_kafka" "kafka_source_external" {
  project      = var.aiven_project
  cloud_name   = var.cloud_name
  plan         = var.kafka_plan
  service_name = "${var.service_prefix}kafka-source-external"
  kafka_user_config {
    kafka_rest      = "true"
    kafka_authentication_methods {
      sasl = true
    }
  }
}

resource "aiven_kafka" "kafka_target_aiven" {
  project      = var.aiven_project
  cloud_name   = var.cloud_name
  plan         = var.kafka_plan
  service_name = "${var.service_prefix}kafka-target"
  kafka_user_config {
    kafka_rest      = "true"
    kafka_authentication_methods {
      sasl = true
    }
  }
}

resource "aiven_kafka_topic" "test_rf_1_topic" {
  project      = var.aiven_project
  service_name = aiven_kafka.kafka_source_external.service_name
  topic_name   = "test_rf_1"
  partitions = 100
  replication = 2  # Can't set to replication 1 -> API won't allow it
  config {
    min_insync_replicas = "1"
  }
}

resource "aiven_kafka_topic" "test_rf_2_topic" {
  project      = var.aiven_project
  service_name = aiven_kafka.kafka_source_external.service_name
  topic_name   = "test_rf_2"
  partitions = 100
  replication = 2
  config {
    min_insync_replicas = "2"
  }
}

resource "aiven_kafka_topic" "test_rf_3_topic" {
  project      = var.aiven_project
  service_name = aiven_kafka.kafka_source_external.service_name
  topic_name   = "test_rf_3"
  partitions = 100
  replication = 3
  config {
    min_insync_replicas = "3"
  }
}

resource "aiven_kafka_mirrormaker" "mm2" {
  project      = var.aiven_project
  cloud_name   = var.cloud_name
  plan         = var.mm2_plan
  service_name = "${var.service_prefix}mm2"

  kafka_mirrormaker_user_config {
    kafka_mirrormaker {
      refresh_groups_enabled = true
      refresh_groups_interval_seconds = 10
      refresh_topics_enabled          = true
      refresh_topics_interval_seconds = 60
      sync_group_offsets_enabled = true
      sync_group_offsets_interval_seconds = 10
      sync_topic_configs_enabled = true
      tasks_max_per_cpu = 2
      emit_checkpoints_enabled = true
      emit_checkpoints_interval_seconds = 10
      offset_lag_max = 0
    }
  }
}

data "aiven_project" "project" {
  project = var.aiven_project
}

data "aiven_kafka" "external_kafka" {
  project      = var.aiven_project
  service_name = aiven_kafka.kafka_source_external.service_name
}


data "aiven_kafka" "internal_kafka" {
  project      = var.aiven_project
  service_name = aiven_kafka.kafka_target_aiven.service_name
}


## ENDPOINTS ##

resource "aiven_service_integration_endpoint" "source_external_endpoint_1" {
  depends_on = [aiven_kafka_mirrormaker.mm2, aiven_kafka.kafka_source_external, aiven_kafka.kafka_target_aiven]
  endpoint_name = "external_1"
  project = var.aiven_project
  endpoint_type = "external_kafka"
  external_kafka_user_config {
    bootstrap_servers = aiven_kafka.kafka_source_external.service_uri
    security_protocol = "SSL"
    ssl_ca_cert = data.aiven_project.project.ca_cert
    ssl_client_key = data.aiven_kafka.external_kafka.kafka[0].access_key
    ssl_client_cert = data.aiven_kafka.external_kafka.kafka[0].access_cert
    ssl_endpoint_identification_algorithm = "https"
  }
}

resource "aiven_service_integration_endpoint" "target_endpoint_1" {
  depends_on = [aiven_kafka_mirrormaker.mm2, aiven_kafka.kafka_source_external, aiven_kafka.kafka_target_aiven]
  endpoint_name = "target_1"
  project = var.aiven_project
  endpoint_type = "external_kafka"
  external_kafka_user_config {
    bootstrap_servers = aiven_kafka.kafka_target_aiven.service_uri
    security_protocol = "SSL"
    ssl_ca_cert = data.aiven_project.project.ca_cert
    ssl_client_key = data.aiven_kafka.internal_kafka.kafka[0].access_key
    ssl_client_cert = data.aiven_kafka.internal_kafka.kafka[0].access_cert
    ssl_endpoint_identification_algorithm = "https"
  }
}


## INTEGRATIONS ##

 resource "aiven_service_integration" "source_external_integration_1" {
  project                  = var.aiven_project
  integration_type         = "kafka_mirrormaker"
  source_endpoint_id = aiven_service_integration_endpoint.source_external_endpoint_1.id
  destination_service_name = aiven_kafka_mirrormaker.mm2.service_name
  kafka_mirrormaker_user_config {
    cluster_alias = "source-external-1"
  }
}

 resource "aiven_service_integration" "source_external_integration_2" {
  project                  = var.aiven_project
  integration_type         = "kafka_mirrormaker"
  source_endpoint_id = aiven_service_integration_endpoint.source_external_endpoint_1.id
  destination_service_name = aiven_kafka_mirrormaker.mm2.service_name
  kafka_mirrormaker_user_config {
    cluster_alias = "source-external-2"
  }
}

 resource "aiven_service_integration" "source_external_integration_3" {
  project                  = var.aiven_project
  integration_type         = "kafka_mirrormaker"
  source_endpoint_id = aiven_service_integration_endpoint.source_external_endpoint_1.id
  destination_service_name = aiven_kafka_mirrormaker.mm2.service_name
  kafka_mirrormaker_user_config {
    cluster_alias = "source-external-3"
  }
}

 resource "aiven_service_integration" "target_aiven_integration" {
  depends_on = [aiven_kafka_mirrormaker.mm2, aiven_kafka.kafka_target_aiven]
  project                  = var.aiven_project
  integration_type         = "kafka_mirrormaker"
  source_service_name = aiven_kafka.kafka_target_aiven.service_name
  destination_service_name = aiven_kafka_mirrormaker.mm2.service_name
  kafka_mirrormaker_user_config {
    cluster_alias = "target-aiven"
  }
}

resource "aiven_service_integration" "target_aiven_endpoint_integration_1" {
  depends_on = [aiven_kafka_mirrormaker.mm2, aiven_kafka.kafka_target_aiven]
  project                  = var.aiven_project
  integration_type         = "kafka_mirrormaker"
  source_endpoint_id = aiven_service_integration_endpoint.target_endpoint_1.id
  destination_service_name = aiven_kafka_mirrormaker.mm2.service_name
  kafka_mirrormaker_user_config {
    cluster_alias = "target-aiven-1"
  }
}

resource "aiven_service_integration" "target_aiven_endpoint_integration_2" {
  depends_on = [aiven_kafka_mirrormaker.mm2, aiven_kafka.kafka_target_aiven]
  project                  = var.aiven_project
  integration_type         = "kafka_mirrormaker"
  source_endpoint_id = aiven_service_integration_endpoint.target_endpoint_1.id
  destination_service_name = aiven_kafka_mirrormaker.mm2.service_name
  kafka_mirrormaker_user_config {
    cluster_alias = "target-aiven-2"
  }
}

resource "aiven_service_integration" "target_aiven_endpoint_integration_3" {
  depends_on = [aiven_kafka_mirrormaker.mm2, aiven_kafka.kafka_target_aiven]
  project                  = var.aiven_project
  integration_type         = "kafka_mirrormaker"
  source_endpoint_id = aiven_service_integration_endpoint.target_endpoint_1.id
  destination_service_name = aiven_kafka_mirrormaker.mm2.service_name
  kafka_mirrormaker_user_config {
    cluster_alias = "target-aiven-3"
  }
}


## REPLICATION FLOWS ##

resource "aiven_mirrormaker_replication_flow" "replication-flow-1" {
  depends_on = [
    aiven_service_integration.target_aiven_integration,
    aiven_service_integration.source_external_integration_1
  ]
  project                    = var.aiven_project
  service_name               = aiven_kafka_mirrormaker.mm2.service_name
  source_cluster             = "source-external-1"
  target_cluster             = "target-aiven-1"
  replication_policy_class   = "org.apache.kafka.connect.mirror.IdentityReplicationPolicy"
  sync_group_offsets_enabled = true
  emit_heartbeats_enabled = false
  emit_backward_heartbeats_enabled = false
  offset_syncs_topic_location = "target"
  enable                     = true
  sync_group_offsets_interval_seconds = 1
  replication_factor = 1
  config_properties_exclude = ["follower\\.replication\\.throttled\\.replicas", "leader\\.replication\\.throttled\\.replicas", "message\\.timestamp\\.difference\\.max\\.ms", "message\\.timestamp\\.type"]
  topics = [
    "test_rf_1"
  ]
}


resource "aiven_mirrormaker_replication_flow" "replication-flow-2" {
  depends_on = [
    aiven_service_integration.target_aiven_integration,
    aiven_service_integration.source_external_integration_2
  ]
  project                    = var.aiven_project
  service_name               = aiven_kafka_mirrormaker.mm2.service_name
  source_cluster             = "source-external-2"
  target_cluster             = "target-aiven-2"
  replication_policy_class   = "org.apache.kafka.connect.mirror.IdentityReplicationPolicy"
  sync_group_offsets_enabled = true
  emit_heartbeats_enabled = false
  emit_backward_heartbeats_enabled = false
  offset_syncs_topic_location = "target"
  enable                     = true
  sync_group_offsets_interval_seconds = 1
  replication_factor = 2
  config_properties_exclude = ["follower\\.replication\\.throttled\\.replicas", "leader\\.replication\\.throttled\\.replicas", "message\\.timestamp\\.difference\\.max\\.ms", "message\\.timestamp\\.type"]
  topics = [
    "test_rf_2"
  ]
}

resource "aiven_mirrormaker_replication_flow" "replication-flow-3" {
  depends_on = [
    aiven_service_integration.target_aiven_integration,
    aiven_service_integration.source_external_integration_3
  ]
  project                    = var.aiven_project
  service_name               = aiven_kafka_mirrormaker.mm2.service_name
  source_cluster             = "source-external-3"
  target_cluster             = "target-aiven-3"
  replication_policy_class   = "org.apache.kafka.connect.mirror.IdentityReplicationPolicy"
  sync_group_offsets_enabled = true
  emit_heartbeats_enabled = false
  emit_backward_heartbeats_enabled = false
  offset_syncs_topic_location = "target"
  enable                     = true
  sync_group_offsets_interval_seconds = 1
  replication_factor = 3
  config_properties_exclude = ["follower\\.replication\\.throttled\\.replicas", "leader\\.replication\\.throttled\\.replicas", "message\\.timestamp\\.difference\\.max\\.ms", "message\\.timestamp\\.type"]
  topics = [
    "test_rf_3"
  ]
}


/*

## TEST DESTINATION ENDPOINT ##

resource "aiven_kafka_topic" "test_target_endpoint" {
  project      = var.aiven_project
  service_name = aiven_kafka.kafka_source_external.service_name
  topic_name   = "test_target_endpoint"
  partitions = 100
  replication = 3
  config {
    min_insync_replicas = "3"
  }
}

resource "aiven_service_integration_endpoint" "target_endpoint_1" {
  depends_on = [aiven_kafka_mirrormaker.mm2, aiven_kafka.kafka_source_external, aiven_kafka.kafka_target_aiven]
  endpoint_name = "target_1"
  project = var.aiven_project
  endpoint_type = "external_kafka"
  external_kafka_user_config {
    bootstrap_servers = aiven_kafka.kafka_target_aiven.service_uri
    security_protocol = "SSL"
    ssl_ca_cert = data.aiven_project.project.ca_cert
    ssl_client_key = data.aiven_kafka.internal_kafka.kafka[0].access_key
    ssl_client_cert = data.aiven_kafka.internal_kafka.kafka[0].access_cert
    ssl_endpoint_identification_algorithm = "https"
  }
}

 resource "aiven_service_integration" "source_external_integration_4" {
  depends_on = [aiven_service_integration_endpoint.source_external_endpoint_1]
  project                  = var.aiven_project
  integration_type         = "kafka_mirrormaker"
  source_endpoint_id = aiven_service_integration_endpoint.source_external_endpoint_1.id
  destination_service_name = aiven_kafka_mirrormaker.mm2.service_name
  kafka_mirrormaker_user_config {
    cluster_alias = "source-external-4"
  }
}

resource "aiven_service_integration" "target_aiven_endpoint_integration" {
  depends_on = [aiven_kafka_mirrormaker.mm2, aiven_kafka.kafka_target_aiven]
  project                  = var.aiven_project
  integration_type         = "kafka_mirrormaker"
  source_endpoint_id = aiven_service_integration_endpoint.target_endpoint_1.id
  destination_service_name = aiven_kafka_mirrormaker.mm2.service_name
  kafka_mirrormaker_user_config {
    cluster_alias = "target-aiven-endpoint"
  }
}

resource "aiven_mirrormaker_replication_flow" "replication-flow-target-endpoint" {
  depends_on = [
    aiven_service_integration.target_aiven_integration,
    aiven_service_integration.source_external_integration_3
  ]
  project                    = var.aiven_project
  service_name               = aiven_kafka_mirrormaker.mm2.service_name
  source_cluster             = "source-external-4"
  target_cluster             = "target-aiven-endpoint"
  replication_policy_class   = "org.apache.kafka.connect.mirror.IdentityReplicationPolicy"
  sync_group_offsets_enabled = true
  offset_syncs_topic_location = "target"
  emit_heartbeats_enabled    = false
  enable                     = true
  sync_group_offsets_interval_seconds = 1
  replication_factor = 3
  config_properties_exclude = ["follower\\.replication\\.throttled\\.replicas", "leader\\.replication\\.throttled\\.replicas", "message\\.timestamp\\.difference\\.max\\.ms", "message\\.timestamp\\.type"]
  topics = [
    "test_target_endpoint"
  ]
}
*/