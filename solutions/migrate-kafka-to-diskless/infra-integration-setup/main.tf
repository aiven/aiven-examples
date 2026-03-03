# create Kafka
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

#import diskless topics
data "local_file" "diskless_topic_names" {
  filename = var.diskless_topics_file
}

locals {
  topic_list = distinct(compact(split("\n", data.local_file.diskless_topic_names.content)))
  topic_map = toset(local.topic_list)

  # ⭐ NEW: For MirrorMaker Topics - create a list of exact-match regex strings
  # We escape the topic name to ensure it's treated as a literal match.
  mirrormaker_topic_regex_list = [
    for topic in local.topic_list : "^${replace(topic, ".", "[.]")}$"
  ]
}

#create MM2
resource "aiven_kafka_mirrormaker" "mm2-cluster2" {
  project      = var.aiven_project_name
  cloud_name   = var.cloud_name_primary
  plan         = var.mm2_plan_cluster_2
  service_name = "${var.service_prefix}-mm2-rf3-set1"
  
/*kafka_mirrormaker_user_config {
    ip_filter = ["0.0.0.0/0"]
  } */

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

# resource "aiven_kafka_mirrormaker" "mm2-cluster3" {
#   project      = var.aiven_project_name
#   cloud_name   = var.cloud_name_primary
#   plan         = var.mm2_plan_cluster_3
#   service_name = "${var.service_prefix}-mm2-rf3-set2"

#   /*kafka_mirrormaker_user_config {
#     ip_filter = ["0.0.0.0/0"]
#   } */

#   kafka_mirrormaker_user_config {
#     kafka_mirrormaker {
#       refresh_groups_enabled = true
#       refresh_groups_interval_seconds = 180 //changed from 10 to 180
#       refresh_topics_enabled          = true
#       refresh_topics_interval_seconds = 60
#       sync_group_offsets_enabled = true
#       sync_group_offsets_interval_seconds = 10
#       sync_topic_configs_enabled = true
#       tasks_max_per_cpu = 2 //changed from 2 to 4
#       emit_checkpoints_enabled = true
#       emit_checkpoints_interval_seconds = 10
#       offset_lag_max = 1
#     }
#   }
# }

#create wait
resource "time_sleep" "wait_mm2_readiness" {
  depends_on = [
    aiven_kafka.destination_kafka_1,
    aiven_kafka_mirrormaker.mm2-cluster2,
  ]
  create_duration = "120s"
}

#Diskless Kafka Topic Creation
resource "aiven_kafka_topic" "diskless_topics" {
  for_each = local.topic_map

  project = var.aiven_project_name
  service_name = "${var.service_prefix}-dest-kafka-1"

  topic_name = each.value

  partitions = 3
  replication = 1

  config {
    diskless_enable = true
  }

}

/*
// Aiven Kafka External Endpoint as a pre-req to create service integration for mm2
resource "aiven_service_integration_endpoint" "aiven_external_endpoint_1"
{
  depends_on = [time_sleep.wait_mm2_readiness]
  endpoint_name = "aiven_kafka_source_endpoint_1"
  project = var.aiven_project_name
  endpoint_type = "external_kafka"
  external_kafka_user_config {
    bootstrap_servers = var.aiven_bootstrap_url
    security_protocol = "PLAINTEXT"
  }
} */

data aiven_project source_project {
  project = var.aiven_project_name
}

//////----------
// AIVEN KAFKA EXTERNAL ENDPOINT for allowing more than 1 destination service integration for more than 1 replication flows
//// ----------
/*
resource "aiven_service_integration_endpoint" "aiven_kafka_destination_endpoint" {
  depends_on = [time_sleep.wait_mm2_readiness]
  endpoint_name = "aiven_kafka_destination_endpoint"
  project = var.aiven_project_name
  endpoint_type = "external_kafka"
    external_kafka_user_config {
    bootstrap_servers = resource.aiven_kafka.destination_kafka_1.service_uri
    security_protocol = "SSL"
    ssl_ca_cert = data.aiven_project.source_project.ca_cert
    ssl_client_key = resource.aiven_kafka.destination_kafka_1.kafka[0].access_key
    ssl_client_cert = resource.aiven_kafka.destination_kafka_1.kafka[0].access_cert
    ssl_endpoint_identification_algorithm = "https"
  }
}
*/

 
# Create integration endpoint for MSK, use Plaintext for security 
resource "aiven_service_integration_endpoint" "aiven_kafka_source_endpoint" {
  depends_on = [time_sleep.wait_mm2_readiness]
  endpoint_name = "aiven_kafka_source_endpoint"
  project = var.aiven_project_name
  endpoint_type = "external_kafka"
    external_kafka_user_config {
    bootstrap_servers = var.aiven_source_bootstrap_url
    security_protocol = "PLAINTEXT"
    //ssl_ca_cert = file("./security/ca.pem")
    //ssl_client_key = file("./security/service.key")
    //ssl_client_cert = file("./security/service.cert")
    //ssl_endpoint_identification_algorithm = "https"
  }
} 

# create source "service integration" between the msk "integration endpoint" and the MM2 "service"
resource "aiven_service_integration" "msk_kafka_source_integration_service" { 
  depends_on = [aiven_service_integration_endpoint.aiven_kafka_source_endpoint]
  project                  = var.aiven_project_name
  integration_type         = "kafka_mirrormaker"
  source_endpoint_id       = aiven_service_integration_endpoint.aiven_kafka_source_endpoint.id
  destination_service_name = aiven_kafka_mirrormaker.mm2-cluster2.service_name
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

# create destination "service integration" between two services: MM2 and Aiven Inkless Kafka Service
resource "aiven_service_integration" "mm2_to_kafka_destination_integration" {
  depends_on = [time_sleep.wait_mm2_readiness]
  project = var.aiven_project_name
  integration_type = "kafka_mirrormaker"
  source_service_name = aiven_kafka.destination_kafka_1.service_name
  destination_service_name = aiven_kafka_mirrormaker.mm2-cluster2.service_name
  kafka_mirrormaker_user_config {
    cluster_alias = "aiven-destination-kafka-rf3-set1"
    kafka_mirrormaker {
      consumer_max_poll_records = 500
      //producer_max_request_size = 66901452
      //producer_buffer_memory = 33554432
      //producer_batch_size = 32768
      //producer_linger_ms = 100
    }
  }
}

# create the replication flow between source cluster defined in source service integration and destination cluster in destination service integration 
# Replication Flow - RF=3 --- This will be using Aiven Kafka Internal Service Integration as --- Check and match cluster_alias with target_cluster
resource "aiven_mirrormaker_replication_flow" "replication-flow-rf3-set1" {
  depends_on = [
    aiven_service_integration.msk_kafka_source_integration_service,
    aiven_service_integration.mm2_to_kafka_destination_integration
  ]
  project                     = var.aiven_project_name
  service_name                = aiven_kafka_mirrormaker.mm2-cluster2.service_name
  source_cluster              = "aiven-source-kafka-rf3-set1"
  target_cluster              = "aiven-destination-kafka-rf3-set1"
  replication_policy_class    = "org.apache.kafka.connect.mirror.IdentityReplicationPolicy"
  sync_group_offsets_enabled  = true
  offset_syncs_topic_location = "target"
  emit_heartbeats_enabled     = true
  enable                      = false
  sync_group_offsets_interval_seconds = 10
  #replication_factor          = 3
  config_properties_exclude   = ["follower\\.replication\\.throttled\\.replicas", "leader\\.replication\\.throttled\\.replicas", "message\\.timestamp\\.difference\\.max\\.ms", "message\\.timestamp\\.type"]
  topics = local.mirrormaker_topic_regex_list

  topics_blacklist = [".*[\\-\\.]internal",".*\\.replica","__.*","connect.*"]
}


/*resource "aiven_service_integration_endpoint" "aiven_kafka_source_endpoint"
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