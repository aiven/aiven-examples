resource "aiven_kafka" "destination_kafka_1" {
  project                 = var.aiven_destination_project_name
  cloud_name              = var.cloud_name_primary
  plan                    = var.dest_kafka_plan
  service_name            = "${var.service_prefix}-dest-kafka-1"
  maintenance_window_dow  = "monday"
  maintenance_window_time = "10:00:00"

  kafka_user_config {
    kafka_rest      = true
    kafka_connect   = false
    schema_registry = true
    kafka_version   = "3.8"

    kafka {
      default_replication_factor = 3
      min_insync_replicas = 2
      message_max_bytes = 100001200
    }

    public_access {
      kafka_rest    = false
      kafka_connect = false
      schema_registry = false
      prometheus = true
      kafka = false
    }

    schema_registry_config{
      leader_eligibility = false
    }
  }
  
}

data "aiven_kafka" "destination_kafka_1" {
  project = aiven_kafka.destination_kafka_1.project
  service_name = "${var.service_prefix}-dest-kafka-1"
}

resource "aiven_kafka_mirrormaker" "mm2-cluster2" {
  project      = var.aiven_destination_project_name
  cloud_name   = var.cloud_name_primary
  plan         = var.mm2_plan_cluster_2
  service_name = "${var.service_prefix}-mm2-rf2"

  /*kafka_mirrormaker_user_config {
    ip_filter = ["0.0.0.0/0"]
  } */

  kafka_mirrormaker_user_config {
    kafka_mirrormaker {
      refresh_groups_enabled = true
      refresh_groups_interval_seconds = 10 //changed from 10 to 180
      refresh_topics_enabled          = true
      refresh_topics_interval_seconds = 60
      sync_group_offsets_enabled = true
      sync_group_offsets_interval_seconds = 10
      sync_topic_configs_enabled = true
      tasks_max_per_cpu = 2 //changed from 2 to 4
      emit_checkpoints_enabled = true
      emit_checkpoints_interval_seconds = 10
      offset_lag_max = 1
    }
  }
}

/*resource "aiven_kafka_mirrormaker" "mm2-cluster3" {
  project      = var.aiven_project_name
  cloud_name   = var.cloud_name_primary
  plan         = var.mm2_plan_cluster_3
  service_name = "${var.service_prefix}-mm2-rf3-set2"

  /*kafka_mirrormaker_user_config {
    ip_filter = ["0.0.0.0/0"]
  } 

  kafka_mirrormaker_user_config {
    kafka_mirrormaker {
      refresh_groups_enabled = true
      refresh_groups_interval_seconds = 180 //changed from 10 to 180
      refresh_topics_enabled          = true
      refresh_topics_interval_seconds = 60
      sync_group_offsets_enabled = true
      sync_group_offsets_interval_seconds = 10
      sync_topic_configs_enabled = true
      tasks_max_per_cpu = 2 //changed from 2 to 4
      emit_checkpoints_enabled = true
      emit_checkpoints_interval_seconds = 10
      offset_lag_max = 1
    }
  }
}*/

resource "time_sleep" "wait_mm2_readiness" {
  depends_on = [
    aiven_kafka.destination_kafka_1,
    aiven_kafka_mirrormaker.mm2-cluster2,
    #aiven_kafka_mirrormaker.mm2-cluster3
  ]
  create_duration = "60s"
}

// Aiven Kafka External Endpoint as a pre-req to create service integration for mm2: source
resource "aiven_service_integration_endpoint" "aiven_external_endpoint_source" {
  depends_on = [time_sleep.wait_mm2_readiness]
  endpoint_name = "aiven_kafka_source_endpoint_1"
  project = var.aiven_destination_project_name
  endpoint_type = "external_kafka"
  external_kafka_user_config {
    bootstrap_servers = var.aiven_source_bootstrap_url
    security_protocol = "PLAINTEXT"
  }
} 

// Aiven Kafka External Endpoint as a pre-req to create service integration for mm2: destination
resource "aiven_service_integration_endpoint" "aiven_external_endpoint_destination" {
  depends_on = [time_sleep.wait_mm2_readiness]
  endpoint_name = "aiven_kafka_destination_endpoint_1"
  project = var.aiven_destination_project_name
  endpoint_type = "external_kafka"
  external_kafka_user_config {
    bootstrap_servers = aiven_kafka.destination_kafka_1.service_uri
    security_protocol = "PLAINTEXT"
  }
} 

 data "aiven_project" "project" {
  project = var.aiven_destination_project_name
 }

 data "aiven_kafka" "source_kafka" {
  project = var.aiven_source_project_name
  service_name = var.kafka_source_name
 }
//////----------
// AIVEN KAFKA EXTERNAL ENDPOINT for allowing more than 1 destination service integration for more than 1 replication flows
//// ----------
resource "aiven_service_integration_endpoint" "kafka_destination_endpoint"{
  depends_on = [time_sleep.wait_mm2_readiness]
  endpoint_name = "kafka_destination_endpoint"
  project = var.aiven_destination_project_name
  endpoint_type = "external_kafka"
    external_kafka_user_config {
    bootstrap_servers = aiven_kafka.destination_kafka_1.service_uri 
    security_protocol = "SSL"
    ssl_ca_cert = data.aiven_project.project.ca_cert
    ssl_client_key = data.aiven_kafka.destination_kafka_1.kafka[0].access_key
    ssl_client_cert = data.aiven_kafka.destination_kafka_1.kafka[0].access_cert
    ssl_endpoint_identification_algorithm = "https"
  }
}

//Use this if source Kafka cluster is hosted in Aiven
resource "aiven_service_integration_endpoint" "kafka_source_endpoint" {
  depends_on = [time_sleep.wait_mm2_readiness]
  endpoint_name = "kafka_source_endpoint"
  project = var.aiven_destination_project_name
  endpoint_type = "external_kafka"
    external_kafka_user_config {
    bootstrap_servers = var.aiven_source_bootstrap_url
    security_protocol = "SSL"
    ssl_ca_cert = data.aiven_project.project.ca_cert
    ssl_client_key = data.aiven_kafka.source_kafka.kafka[0].access_key
    ssl_client_cert = data.aiven_kafka.source_kafka.kafka[0].access_cert
    ssl_endpoint_identification_algorithm = "https"
  }
} 

/*//Use this if source Kafka cluster is hosted outside of Aiven
resource "aiven_service_integration_endpoint" "kafka_source_endpoint" {
  depends_on = [time_sleep.wait_mm2_readiness]
  endpoint_name = "kafka_source_endpoint"
  project = var.aiven_destination_project_name
  endpoint_type = "external_kafka"
    external_kafka_user_config {
    bootstrap_servers = var.aiven_source_bootstrap_url
    security_protocol = "SSL"
    //TODO: how to pass in these from files
    # ssl_ca_cert = data.aiven_project.project.ca_cert
    # ssl_client_key = data.aiven_kafka.source_kafka.kafka[0].access_key
    # ssl_client_cert = data.aiven_kafka.source_kafka.kafka[0].access_cert
    ssl_endpoint_identification_algorithm = "https"
  }
} */

//For SASL_SSL protocol
/*resource "aiven_service_integration_endpoint" "kafka_source_endpoint"
{
  depends_on = [time_sleep.wait_mm2_readiness]
  endpoint_name = "aiven_kafka_source_endpoint"
  project = var.aiven_project_name
  endpoint_type = "external_kafka"
    external_kafka_user_config {
    bootstrap_servers = data.aiven_kafka.kafka_source.service_uri
    security_protocol = "SASL_SSL"
    sasl_mechanism = "SCRAM-SHA-512"
    sasl_plain_username = data.aiven_kafka.kafka_source.username
    sasl_plain_password = data.aiven_kafka.kafka_source.password
    ssl_ca_cert = data.aiven_project.source_project.ca_cert
    ssl_endpoint_identification_algorithm = "https"
  }
}*/