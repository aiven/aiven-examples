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

variable "plan_name" {
  description = "Plan name for the services (e.g., startup-4, business-8)"
  type        = string
  default     = "startup-4"
}

variable "kafka_plan_name" {
  description = "Kafka plan name for the services (e.g., business-4, business-8)"
  type        = string
  default     = "business-16-inkless"
}

variable "service_name_prefix" {
  description = "Prefix for service names to ensure uniqueness"
  type        = string
  default     = "debezium-diskless-"
}

variable "table_name" {
  description = "Postgres table name to read from"
  type        = string
  default     = "diskless_test"
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
    kafka_version = "4.0"
    kafka_rest = true
    tiered_storage {
      enabled = true
    }
    kafka {
      auto_create_topics_enable = true
    }
    kafka_diskless {
      enabled = true
    }
  }
}

resource "aiven_pg" "postgres" {
  project      = var.project_name
  cloud_name   = var.cloud_name
  plan         = var.plan_name
  service_name = "${var.service_name_prefix}postgres"

  provisioner "local-exec" {
    command = "psql -U ${self.service_username} -h ${self.service_host} -p ${self.service_port} -d defaultdb -f ${path.module}/publication.sql"
    environment = {
      PGPASSWORD = aiven_pg.postgres.service_password
      PGSSLMODE  = "require"
    }
  }
}

resource "aiven_kafka_connect" "kafka_connect" {
  project      = var.project_name
  cloud_name   = var.cloud_name
  plan         = var.plan_name
  service_name = "${var.service_name_prefix}kafka-connect"
}

resource "aiven_service_integration" "kafka_connect_integration" {
  project                  = var.project_name
  integration_type         = "kafka_connect"
  source_service_name      = aiven_kafka.kafka.service_name
  destination_service_name = aiven_kafka_connect.kafka_connect.service_name
}

resource "aiven_kafka_topic" "diskless_debezium_topic" {
  project      = var.project_name
  service_name = aiven_kafka.kafka.service_name
  topic_name   = "inkless.public.${var.table_name}"
  partitions   = 3
  replication  = 1

  config {
    diskless_enable = true
  }
}

resource "aiven_kafka_connector" "kafka-pg-debezium-source-connector" {
  depends_on     = [aiven_service_integration.kafka_connect_integration, aiven_kafka_topic.diskless_debezium_topic]
  project        = var.project_name
  service_name   = aiven_kafka_connect.kafka_connect.service_name
  connector_name = "debezium-connector"

  config = {
    "name"                        = "debezium-connector"
    "connector.class"             = "io.debezium.connector.postgresql.PostgresConnector"
    "database.server.name"        = "avn_pg_db"
    "database.hostname"           = aiven_pg.postgres.service_host
    "database.port"               = aiven_pg.postgres.service_port
    "database.user"               = aiven_pg.postgres.service_username
    "database.password"           = aiven_pg.postgres.service_password
    "database.dbname"             = "defaultdb"
    "database.sslmode"            = "require"
    "plugin.name"                 = "pgoutput"
    "publication.name"            = "dbz_publication"
    "publication.autocreate.mode" = "all_tables"
    "_aiven.restart.on.failure"   = "true"
    "topic.prefix"          = "inkless"
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

output "postgres_service_uri" {
  description = "URI of the PostgreSQL service"
  value       = aiven_pg.postgres.service_uri
  sensitive   = true
}

output "topic_name" {
  description = "Name of the Kafka topic"
  value       = aiven_kafka_topic.diskless_debezium_topic.topic_name
}

output "table_name" {
  description = "Name of the table to read from"
  value       = var.table_name
}
