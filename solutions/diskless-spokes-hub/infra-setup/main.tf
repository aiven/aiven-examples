# create Hub Kafka
resource "aiven_kafka" "hub_kafka" {
  project                 = var.aiven_project_name
  cloud_name              = var.cloud_name_hub
  plan                    = var.hub_kafka_plan
  service_name            = "${var.service_prefix}-hub-kafka-1"
  maintenance_window_dow  = "monday"
  maintenance_window_time = "10:00:00"
  
  kafka_user_config {
    kafka_rest      = true
    kafka_connect   = false
    kafka_version   = "4.0"
    kafka_diskless {
      enabled = true
    }
    tiered_storage {
      enabled = true
    }

    kafka {
      auto_create_topics_enable = true
      default_replication_factor = 3
      min_insync_replicas = 2
      message_max_bytes = 100001200
    }

    public_access {
      kafka_rest    = false
      kafka_connect = false
      schema_registry = false
      prometheus = false
      kafka = false
    }

    schema_registry_config{
      leader_eligibility = true
    }
  }
}

# create spoke kafka
resource "aiven_kafka" "spoke_kafka_1" {
  project                 = var.aiven_project_name
  cloud_name              = var.cloud_name_spoke_1
  plan                    = var.spoke_kafka_plan
  service_name            = "${var.service_prefix}-spoke-kafka-1"
  maintenance_window_dow  = "monday"
  maintenance_window_time = "10:00:00"
  
  kafka_user_config {
    kafka_rest      = true
    kafka_connect   = false
    kafka_version   = "4.0"
    kafka_diskless {
      enabled = true
    }
    tiered_storage {
      enabled = true
    }

    kafka {
      auto_create_topics_enable = true
      default_replication_factor = 3
      min_insync_replicas = 2
      message_max_bytes = 100001200
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


#create MM2 for Hub to Spoke Schema Replication
resource "aiven_kafka_mirrormaker" "mm2_schema_replication_1" {
  project      = var.aiven_project_name
  cloud_name   = var.cloud_name_hub
  plan         = var.mm2_plan_hub_cluster
  service_name = "${var.service_prefix}-mm2-spoke-1-schema-replication"

  kafka_mirrormaker_user_config {
    kafka_mirrormaker {
      refresh_groups_enabled = true
      refresh_groups_interval_seconds = 10 //changed from 10 to 180
      refresh_topics_enabled          = true // just sync schema topics
      refresh_topics_interval_seconds = 60
      sync_group_offsets_enabled = true
      sync_group_offsets_interval_seconds = 10
      sync_topic_configs_enabled = true // just sync schema topics
      tasks_max_per_cpu = 2 //changed from 2 to 4
      emit_checkpoints_enabled = true
      emit_checkpoints_interval_seconds = 10
      offset_lag_max = 1
    }
  }
}

#create MM2 for Spoke to Hub Schema Replication
resource "aiven_kafka_mirrormaker" "mm2_data_replication_spoke_1" {
  project      = var.aiven_project_name
  cloud_name   = var.cloud_name_hub
  plan         = var.mm2_plan_spoke_cluster
  service_name = "${var.service_prefix}-mm2-data-replication-spoke-1"

  kafka_mirrormaker_user_config {
    kafka_mirrormaker {
      refresh_groups_enabled = true
      refresh_groups_interval_seconds = 10 //changed from 10 to 180
      refresh_topics_enabled          = false // just sync schema topics
      refresh_topics_interval_seconds = 60
      sync_group_offsets_enabled = true
      sync_group_offsets_interval_seconds = 10
      sync_topic_configs_enabled = false // just sync schema topics
      tasks_max_per_cpu = 2 //changed from 2 to 4
      emit_checkpoints_enabled = true
      emit_checkpoints_interval_seconds = 10
      offset_lag_max = 1
    }
  }
}


#create wait
resource "time_sleep" "wait_mm2_readiness" {
  depends_on = [
    aiven_kafka.hub_kafka,
    aiven_kafka.spoke_kafka_1,
    aiven_kafka_mirrormaker.mm2_schema_replication_1,
    aiven_kafka_mirrormaker.mm2_data_replication_spoke_1
  ]
  create_duration = "600s"
}

# // MM2 Hub service integration for Schema Replication
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

# // MM2 spoke service integration for Schema Replication
resource "aiven_service_integration" "mm2-spoke-svc-integration-schema-destination" {
project                  = var.aiven_project_name
integration_type         = "kafka_mirrormaker"
source_service_name      = aiven_kafka.spoke_kafka_1.service_name
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

# // MM2 Hub service integration for Data Replication
resource "aiven_service_integration" "mm2-hub-svc-integration-data-destination" {
project                  = var.aiven_project_name
integration_type         = "kafka_mirrormaker"
source_service_name      = aiven_kafka.hub_kafka.service_name
destination_service_name = aiven_kafka_mirrormaker.mm2_data_replication_spoke_1.service_name
kafka_mirrormaker_user_config {
    cluster_alias = "aiven-hub-data-destination-cluster" // could suffix with region name
    kafka_mirrormaker {
        producer_max_request_size = 66901452 // default
        producer_buffer_memory = 33554432 // default, required size is that producer batch fits to buffer memory.
        producer_batch_size = 12000
        producer_linger_ms = 100
    }
    }
}

# // MM2 spoke service integration for Data Replication
resource "aiven_service_integration" "mm2-spoke-svc-integration-data-source-1" {
project                  = var.aiven_project_name
integration_type         = "kafka_mirrormaker"
source_service_name      = aiven_kafka.spoke_kafka_1.service_name
destination_service_name = aiven_kafka_mirrormaker.mm2_data_replication_spoke_1.service_name
kafka_mirrormaker_user_config {
    cluster_alias = "aiven-spoke-data-source-cluster-1" //could use name suffix with region name 
    kafka_mirrormaker {
        producer_max_request_size = 66901452 // default
        producer_buffer_memory = 33554432 // default, required size is that producer batch fits to buffer memory.
        producer_batch_size = 12000 
        producer_linger_ms = 100
    }
    }
}