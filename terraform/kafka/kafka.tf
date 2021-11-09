terraform {
  required_providers {
    aiven = {
      source  = "aiven/aiven"
      version = ">= 2.2.1, < 3.0.0"
    }
  }
}

variable "aiven_project_name" {
}
variable "cloud_name" {
}
variable "service_name" {
}
variable "kafka_user_name" {
  description = "Kafka User"
  default     = "kafka_a"
}

resource "aiven_kafka" "kafka" {
  project                 = var.aiven_project_name
  cloud_name              = var.cloud_name
  service_name            = var.service_name
  plan                    = "business-4"
  maintenance_window_dow  = "wednesday"
  maintenance_window_time = "18:30:00"
  termination_protection  = false

  kafka {
  }

  kafka_user_config {
    kafka_version   = "2.8"
    kafka_connect   = true
    kafka_rest      = true
    schema_registry = true

    kafka {
      auto_create_topics_enable    = true
      num_partitions               = 3
      default_replication_factor   = 2
      min_insync_replicas          = 2
      message_max_bytes            = 131072
      group_max_session_timeout_ms = 70000
      log_retention_bytes          = 1000000000
    }

    kafka_authentication_methods {
      certificate = true
    }
  }
}

resource "aiven_service_user" "kafka_user" {
  project      = var.aiven_project_name
  service_name = aiven_kafka.kafka.service_name
  username     = var.kafka_user_name
}

resource "aiven_kafka_acl" "kafka_user_acl" {
  project      = var.aiven_project_name
  service_name = aiven_kafka.kafka.service_name
  #username     = "kafka_*"
  username   = var.kafka_user_name
  permission = "read"
  topic      = "*"
}

output "service_uri" {
  value     = aiven_kafka.kafka.service_uri
  sensitive = false
}
