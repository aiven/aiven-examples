terraform {
  required_version = ">= 1.0"

  required_providers {
    aiven = {
      source  = "aiven/aiven"
      version = "~> 4.0"
    }
    env = {
      source  = "tchupp/env"
      version = "0.0.2"
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.0"
    }
  }
}

# Configure the Aiven Provider
provider "aiven" {
  api_token = local.aiven_api_token
}

# Variables
variable "aiven_api_token" {
  description = "Aiven API token. Automatically populated from AIVEN_API_TOKEN environment variable by tchupp/env provider, or can be set directly in terraform.tfvars"
  type        = string
  default     = ""
  sensitive   = true
}

variable "project_name" {
  description = "Aiven project name where services will be created"
  type        = string
}

variable "cloud_name" {
  description = "Cloud name for the services (e.g., google-europe-west1, aws-us-east-1)"
  type        = string
  default     = "google-europe-west1"
}

variable "kafka_plan_name" {
  description = "Kafka plan name for the services (e.g., business-4, business-8)"
  type        = string
  default     = "business-16-inkless"
}

variable "service_name_prefix" {
  description = "Prefix for service names to ensure uniqueness"
  type        = string
  default     = "demo-diskless-"
}

# Data sources
data "aiven_project" "project" {
  project = var.project_name
}

# Data sources for reading environment variables using tchupp/env provider
data "env_variable" "aiven_api_token" {
  name = "AIVEN_API_TOKEN"
}


# Local values for credentials with environment variable fallbacks
locals {
  aiven_api_token = var.aiven_api_token != "" ? var.aiven_api_token : (data.env_variable.aiven_api_token.value != "" ? data.env_variable.aiven_api_token.value : null)
}

resource "aiven_kafka" "kafka" {
  project      = var.project_name
  cloud_name   = var.cloud_name
  plan         = var.kafka_plan_name
  service_name = "${var.service_name_prefix}kafka"
  kafka_user_config {
    kafka_connect   = false
    schema_registry = true
    kafka_version = "4.0"
    kafka_rest = true
    tiered_storage {
      enabled = true
    }
    follower_fetching{
      enabled = true
    }
    kafka {
      auto_create_topics_enable = true
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
    kafka_diskless {
      enabled = true
    }
  }
}

resource "aiven_kafka_topic" "diskless_example_topic" {
  project      = var.project_name
  service_name = aiven_kafka.kafka.service_name
  topic_name   = "diskless_test_1"
  partitions   = 3
  replication  = 1

  config {
    diskless_enable = true
  }
}

# Outputs
output "kafka_service_uri" {
  description = "URI of the Kafka service"
  value       = aiven_kafka.kafka.service_uri
  sensitive   = true
}

output "kafka_certificate" {
  description = "Certificate of the Kafka service"
  value       = aiven_kafka.kafka.kafka[0].access_cert
  sensitive   = true
}

output "kafka_access_key" {
  description = "Access key (private key) of the Kafka service"
  value       = aiven_kafka.kafka.kafka[0].access_key
  sensitive   = true
}

output "kafka_ca_cert" {
  description = "CA certificate of the project"
  value       = data.aiven_project.project.ca_cert
  sensitive   = true
}

output "topic_name" {
  description = "Name of the Kafka topic"
  value       = aiven_kafka_topic.diskless_example_topic.topic_name
}
