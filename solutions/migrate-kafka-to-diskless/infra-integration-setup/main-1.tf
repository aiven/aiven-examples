resource "aiven_kafka" "destination_kafka_1" {
  project                 = var.aiven_project_name
  cloud_name              = var.cloud_name_primary
  plan                    = var.dest_kafka_plan
  service_name            = "${var.service_prefix}-dest-kafka-1"
  maintenance_window_dow  = "monday"
  maintenance_window_time = "10:00:00"

  kafka_user_config {
    kafka_rest      = true
    kafka_connect   = false
    schema_registry = false
    kafka_version   = "4.0"
    kafka_diskless {
      enabled = true
    }
    tiered_storage {
      enabled = true
    }
    kafka {
      default_replication_factor = 3
      min_insync_replicas = 2
      message_max_bytes = 100001200
    }
    kafka_authentication_methods {
      certificate = true
      sasl        = true # Enable SASL authentication
    }
    kafka_sasl_mechanisms {
      scram_sha_256 = true
      scram_sha_512 = true
    }
    public_access {
      kafka_rest    = false
      kafka_connect = false
      schema_registry = false
      prometheus = false
      kafka = false
    }
    schema_registry_config{
      leader_eligibility = false
    }
  }
}

resource "aiven_kafka_mirrormaker" "mm2-cluster2" {
  project      = var.aiven_project_name
  cloud_name   = var.cloud_name_primary
  plan         = var.mm2_plan_cluster_2
  service_name = "${var.service_prefix}-mm2-rf3-set1"

  kafka_mirrormaker_user_config {
    kafka_mirrormaker {
      refresh_groups_enabled = true
      refresh_groups_interval_seconds = 10 //changed from 10 to 180
      refresh_topics_enabled          = false
      refresh_topics_interval_seconds = 60
      sync_group_offsets_enabled = true
      sync_group_offsets_interval_seconds = 10
      sync_topic_configs_enabled = false
      tasks_max_per_cpu = 2 //changed from 2 to 4
      emit_checkpoints_enabled = true
      emit_checkpoints_interval_seconds = 10
      offset_lag_max = 1
    }
  }
}

resource "time_sleep" "wait_mm2_readiness" {
  depends_on = [
    aiven_kafka.destination_kafka_1,
    aiven_kafka_mirrormaker.mm2-cluster2,
  ]
  create_duration = "120s"
}