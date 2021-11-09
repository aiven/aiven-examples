terraform {
  required_providers {
    aiven = {
      source  = "aiven/aiven"
      version = ">= 2.2.1, < 3.0.0"
    }
    time = {
      source  = "hashicorp/time"
      version = "0.7.2"
    }
  }
}

variable "aiven_project_name" {
}
variable "cloud_name" {
}
variable "service_name" {
}

variable "kafka_service_name" {
}
variable "source_name" {
}
variable "source_db" {
}
variable "sink_name" {
}

locals {
  kafka_connect_service_name = join("-", [var.service_name, "connect"])
}

resource "aiven_kafka_connect" "kafka_connect" {
  project                 = var.aiven_project_name
  cloud_name              = var.cloud_name
  service_name            = local.kafka_connect_service_name
  plan                    = "business-4"
  maintenance_window_dow  = "friday"
  maintenance_window_time = "20:30:00"
  termination_protection  = false

  kafka_connect_user_config {
    kafka_connect {
      consumer_isolation_level = "read_committed"
    }

    public_access {
      kafka_connect = true
    }
  }
}

resource "aiven_service_integration" "kafka_connect_integration" {
  project                  = var.aiven_project_name
  integration_type         = "kafka_connect"
  source_service_name      = var.kafka_service_name
  destination_service_name = aiven_kafka_connect.kafka_connect.service_name
}

output "service_name" {
  value = aiven_kafka_connect.kafka_connect.service_name
}