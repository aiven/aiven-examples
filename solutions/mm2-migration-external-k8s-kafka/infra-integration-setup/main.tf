resource "aiven_kafka_mirrormaker" "mm2-cluster1" {
  project      = var.aiven_project_name
  cloud_name   = var.cloud_name_primary
  plan         = var.mm2_plan_cluster_1
  service_name = "${var.service_prefix}-mm2"

  /*kafka_mirrormaker_user_config {
    ip_filter = ["0.0.0.0/0"]
  } */

  kafka_mirrormaker_user_config {
    kafka_mirrormaker {
      refresh_groups_enabled = true
      refresh_groups_interval_seconds = 180 //changed from 10 to 180
      refresh_topics_enabled          = true
      refresh_topics_interval_seconds = 60
      sync_group_offsets_enabled = true
      sync_group_offsets_interval_seconds = 10
      sync_topic_configs_enabled = true
      tasks_max_per_cpu = 4 //changed from 2 to 4
      emit_checkpoints_enabled = true
      emit_checkpoints_interval_seconds = 10
      offset_lag_max = 1
    }
  }
}

resource "aiven_kafka_mirrormaker" "mm2-cluster2" {
  project      = var.aiven_project_name
  cloud_name   = var.cloud_name_primary
  plan         = var.mm2_plan_cluster_2
  service_name = "${var.service_prefix}-mm2"

  /*kafka_mirrormaker_user_config {
    ip_filter = ["0.0.0.0/0"]
  } */

  kafka_mirrormaker_user_config {
    kafka_mirrormaker {
      refresh_groups_enabled = true
      refresh_groups_interval_seconds = 180 //changed from 10 to 180
      refresh_topics_enabled          = true
      refresh_topics_interval_seconds = 60
      sync_group_offsets_enabled = true
      sync_group_offsets_interval_seconds = 10
      sync_topic_configs_enabled = true
      tasks_max_per_cpu = 4 //changed from 2 to 4
      emit_checkpoints_enabled = true
      emit_checkpoints_interval_seconds = 10
      offset_lag_max = 1
    }
  }
}

resource "aiven_kafka_mirrormaker" "mm2-cluster3" {
  project      = var.aiven_project_name
  cloud_name   = var.cloud_name_primary
  plan         = var.mm2_plan_cluster_3
  service_name = "${var.service_prefix}-mm2"

  /*kafka_mirrormaker_user_config {
    ip_filter = ["0.0.0.0/0"]
  } */

  kafka_mirrormaker_user_config {
    kafka_mirrormaker {
      refresh_groups_enabled = true
      refresh_groups_interval_seconds = 180 //changed from 10 to 180
      refresh_topics_enabled          = true
      refresh_topics_interval_seconds = 60
      sync_group_offsets_enabled = true
      sync_group_offsets_interval_seconds = 10
      sync_topic_configs_enabled = true
      tasks_max_per_cpu = 4 //changed from 2 to 4
      emit_checkpoints_enabled = true
      emit_checkpoints_interval_seconds = 10
      offset_lag_max = 1
    }
  }
}
resource "time_sleep" "wait_mm2_readiness" {
  depends_on = [
    aiven_kafka_mirrormaker.mm2-cluster1,
    aiven_kafka_mirrormaker.mm2-cluster2,
    aiven_kafka_mirrormaker.mm2-cluster3
  ]
  create_duration = "600s"
}

// Strimzi Kafka External Endpoint as a pre-req to create service integration for mm2
resource "aiven_service_integration_endpoint" "strimzi_external_endpoint"
{
  depends_on = [time_sleep.wait_mm2_readiness]
  endpoint_name = "strimzi_kafka_source_endpoint"
  project = var.aiven_project_name
  endpoint_type = "external_kafka"
  external_kafka_user_config {
    bootstrap_servers = var.strimzi_bootstrap_url
    security_protocol = "PLAINTEXT"
  }
}
/*
//////----------
// AIVEN KAFKA EXTERNAL ENDPOINT for allowing more than 1 destination service integration for more than 1 replication flows
//// ----------
resource "aiven_service_integration_endpoint" "aiven_kafka_destination_endpoint"
{
  depends_on = [time_sleep.wait_mm2_readiness]
  endpoint_name = "aiven_kafka_destination_endpoint"
  project = var.aiven_project_name
  endpoint_type = "external_kafka"
    external_kafka_user_config {
    bootstrap_servers = data.aiven_kafka.kafka_source.service_uri
    security_protocol = "SSL"
    ssl_ca_cert = data.aiven_project.source_project.ca_cert
    ssl_client_key = data.aiven_kafka.kafka_source.kafka[0].access_key
    ssl_client_cert = data.aiven_kafka.kafka_source.kafka[0].access_cert
    ssl_endpoint_identification_algorithm = "https"
  }
}
 */