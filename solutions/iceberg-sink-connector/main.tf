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



variable "service_name_prefix" {
  description = "Prefix for service names to ensure uniqueness"
  type        = string
  default     = "iceberg-sink"
}

variable "aws_region" {
  description = "AWS region for S3 operations (must match your S3 bucket region)"
  type        = string
  default     = "eu-west-1"
}

variable "s3_bucket_name" {
  description = "S3 bucket name for Iceberg warehouse storage"
  type        = string
  default     = "aiventest-systest"
}

variable "aws_access_key_id" {
  description = "AWS access key ID. Automatically populated from AWS_ACCESS_KEY_ID environment variable by tchupp/env provider, or can be set directly in terraform.tfvars"
  type        = string
  default     = ""
  sensitive   = true
}

variable "aws_secret_access_key" {
  description = "AWS secret access key. Automatically populated from AWS_SECRET_ACCESS_KEY environment variable by tchupp/env provider, or can be set directly in terraform.tfvars"
  type        = string
  default     = ""
  sensitive   = true
}

variable "aws_role_arn" {
  description = "AWS role ARN to assume for S3 access (optional)"
  type        = string
  default     = ""
}

variable "topic_name" {
  description = "Kafka topic name for the Iceberg sink connector"
  type        = string
  default     = "test_iceberg_topic"
}

variable "table_name" {
  description = "Iceberg table name that will be created automatically"
  type        = string
  default     = "systest-table"
}

variable "s3_prefix" {
  description = "S3 prefix for Iceberg warehouse organization"
  type        = string
  default     = "connect-iceberg-sink"
}

# Data sources
data "aiven_project" "project" {
  project = var.project_name
}

# Data sources for reading environment variables using tchupp/env provider
data "env_variable" "aiven_api_token" {
  name = "AIVEN_API_TOKEN"
}

data "env_variable" "aws_access_key_id" {
  name = "AWS_ACCESS_KEY_ID"
}

data "env_variable" "aws_secret_access_key" {
  name = "AWS_SECRET_ACCESS_KEY"
}

# Local values for credentials with environment variable fallbacks
locals {
  aiven_api_token       = var.aiven_api_token != "" ? var.aiven_api_token : (data.env_variable.aiven_api_token.value != "" ? data.env_variable.aiven_api_token.value : null)
  aws_access_key_id     = var.aws_access_key_id != "" ? var.aws_access_key_id : (data.env_variable.aws_access_key_id.value != "" ? data.env_variable.aws_access_key_id.value : null)
  aws_secret_access_key = var.aws_secret_access_key != "" ? var.aws_secret_access_key : (data.env_variable.aws_secret_access_key.value != "" ? data.env_variable.aws_secret_access_key.value : null)
}

# Kafka service (without Kafka Connect)
resource "aiven_kafka" "kafka" {
  project      = var.project_name
  cloud_name   = var.cloud_name
  plan         = var.plan_name
  service_name = "${var.service_name_prefix}-kafka"

  kafka_user_config {
    kafka_rest    = true
    kafka_version = "3.9"
    kafka {
      auto_create_topics_enable = true
    }
  }
}

# Dedicated Kafka Connect service
resource "aiven_kafka_connect" "kafka_connect" {
  project      = var.project_name
  cloud_name   = var.cloud_name
  plan         = var.plan_name
  service_name = "${var.service_name_prefix}-kafka-connect"
}

# Service integration to connect Kafka Connect to Kafka
resource "aiven_service_integration" "kafka_connect_kafka" {
  project                  = var.project_name
  integration_type         = "kafka_connect"
  source_service_name      = aiven_kafka.kafka.service_name
  destination_service_name = aiven_kafka_connect.kafka_connect.service_name
}

# PostgreSQL service for Iceberg JDBC catalog
resource "aiven_pg" "postgres" {
  project      = var.project_name
  cloud_name   = var.cloud_name
  plan         = var.plan_name
  service_name = "${var.service_name_prefix}-postgres"

  pg_user_config {
    pg_version = "15"
  }
}



# Kafka topic
resource "aiven_kafka_topic" "iceberg_topic" {
  project      = var.project_name
  service_name = aiven_kafka.kafka.service_name
  topic_name   = var.topic_name
  partitions   = 3
  replication  = 2
}

# Database user for PostgreSQL
resource "aiven_pg_user" "iceberg_user" {
  project      = var.project_name
  service_name = aiven_pg.postgres.service_name
  username     = "iceberg_user"
}

# PostgreSQL database for Iceberg catalog
resource "aiven_pg_database" "iceberg_db" {
  project       = var.project_name
  service_name  = aiven_pg.postgres.service_name
  database_name = "iceberg_catalog"

  depends_on = [
    aiven_pg_user.iceberg_user
  ]
}

# Grant permissions to the Iceberg user
resource "null_resource" "iceberg_user_permissions" {
  triggers = {
    user_id     = aiven_pg_user.iceberg_user.id
    database_id = aiven_pg_database.iceberg_db.id
  }

  provisioner "local-exec" {
    command = <<-EOT
      PGPASSWORD='${aiven_pg.postgres.service_password}' psql -h ${aiven_pg.postgres.service_host} -p ${aiven_pg.postgres.service_port} -U avnadmin -d ${aiven_pg_database.iceberg_db.database_name} -c "
        GRANT ALL PRIVILEGES ON DATABASE ${aiven_pg_database.iceberg_db.database_name} TO ${aiven_pg_user.iceberg_user.username};
        GRANT ALL PRIVILEGES ON SCHEMA public TO ${aiven_pg_user.iceberg_user.username};
        GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO ${aiven_pg_user.iceberg_user.username};
        GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO ${aiven_pg_user.iceberg_user.username};
        ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO ${aiven_pg_user.iceberg_user.username};
        ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON SEQUENCES TO ${aiven_pg_user.iceberg_user.username};
      "
    EOT
  }

  depends_on = [
    aiven_pg_database.iceberg_db,
    aiven_pg_user.iceberg_user
  ]
}

# Kafka Connect connector for Iceberg sink
resource "aiven_kafka_connector" "iceberg_sink" {
  project        = var.project_name
  service_name   = aiven_kafka_connect.kafka_connect.service_name
  connector_name = "iceberg-sink-connector"

  config = merge({
    "name"                                 = "iceberg-sink-connector"
    "connector.class"                      = "org.apache.iceberg.connect.IcebergSinkConnector"
    "topics"                               = var.topic_name
    "iceberg.tables"                       = var.table_name
    "iceberg.tables.auto-create-enabled"   = "true"
    "iceberg.tables.evolve-schema-enabled" = "true"
    "iceberg.control.commit.interval-ms"   = "15000"
    "flush.size" : "10"
    "flush.interval.ms"                            = "1000"
    "iceberg.control.commit.timeout-ms"            = "5000"
    "tasks.max"                                    = "1"
    "key.converter"                                = "org.apache.kafka.connect.json.JsonConverter"
    "value.converter"                              = "org.apache.kafka.connect.json.JsonConverter"
    "consumer.override.auto.offset.reset"          = "earliest"
    "iceberg.catalog.client.region"                = var.aws_region
    "iceberg.catalog.io-impl"                      = "org.apache.iceberg.aws.s3.S3FileIO"
    "iceberg.catalog.jdbc.useSSL"                  = "true"
    "iceberg.catalog.jdbc.verifyServerCertificate" = "true"
    "iceberg.catalog.s3.path-style-access"         = "true"
    "iceberg.catalog.type"                         = "jdbc"
    "iceberg.catalog.uri"                          = "jdbc:postgresql://${aiven_pg.postgres.service_host}:${aiven_pg.postgres.service_port}/${aiven_pg_database.iceberg_db.database_name}?user=${aiven_pg_user.iceberg_user.username}&password=${aiven_pg_user.iceberg_user.password}&ssl=require"
    "iceberg.catalog.warehouse"                    = "s3://${var.s3_bucket_name}/${var.s3_prefix}/"
    "iceberg.kafka.auto.offset.reset"              = "earliest"
    "iceberg.kafka.bootstrap.servers"              = aiven_kafka.kafka.service_uri
    "iceberg.kafka.security.protocol"              = "SSL"
    "iceberg.kafka.ssl.key.password"               = "password"
    "iceberg.kafka.ssl.keystore.location"          = "/run/aiven/keys/public.keystore.p12"
    "iceberg.kafka.ssl.keystore.password"          = "password"
    "iceberg.kafka.ssl.keystore.type"              = "PKCS12"
    "iceberg.kafka.ssl.truststore.location"        = "/run/aiven/keys/public.truststore.jks"
    "iceberg.kafka.ssl.truststore.password"        = "password"
    "key.converter.schemas.enable"                 = "false"
    "value.converter.schemas.enable"               = "false"
    }, var.aws_role_arn != "" ? {
    "iceberg.catalog.client.assume-role.arn"    = var.aws_role_arn
    "iceberg.catalog.client.assume-role.region" = var.aws_region
    "iceberg.catalog.client.factory"            = "org.apache.iceberg.aws.AssumeRoleAwsClientFactory"
    } : local.aws_access_key_id != null ? {
    "iceberg.catalog.s3.access-key-id"     = local.aws_access_key_id
    "iceberg.catalog.s3.secret-access-key" = local.aws_secret_access_key
  } : {})

  depends_on = [
    aiven_kafka_topic.iceberg_topic,
    aiven_pg_user.iceberg_user,
    aiven_pg_database.iceberg_db,
    null_resource.iceberg_user_permissions,
    aiven_service_integration.kafka_connect_kafka
  ]
}

# Outputs
output "kafka_service_name" {
  description = "Name of the Kafka service"
  value       = aiven_kafka.kafka.service_name
}

output "kafka_service_uri" {
  description = "URI of the Kafka service"
  value       = aiven_kafka.kafka.service_uri
  sensitive   = true
}

output "kafka_service_password" {
  description = "Password of the Kafka service"
  value       = aiven_kafka.kafka.service_password
  sensitive   = true
}

output "kafka_rest_uri" {
  description = "REST API URI of the Kafka service"
  value       = aiven_kafka.kafka.kafka[0].rest_uri
  sensitive   = true
}

output "kafka_connect_service_name" {
  description = "Name of the Kafka Connect service"
  value       = aiven_kafka_connect.kafka_connect.service_name
}

output "kafka_connect_uri" {
  description = "URI of the Kafka Connect service"
  value       = aiven_kafka_connect.kafka_connect.service_uri
  sensitive   = true
}

output "postgres_service_name" {
  description = "Name of the PostgreSQL service"
  value       = aiven_pg.postgres.service_name
}

output "postgres_service_uri" {
  description = "URI of the PostgreSQL service"
  value       = aiven_pg.postgres.service_uri
  sensitive   = true
}

output "postgres_host" {
  description = "Host of the PostgreSQL service"
  value       = aiven_pg.postgres.service_host
}

output "postgres_port" {
  description = "Port of the PostgreSQL service"
  value       = aiven_pg.postgres.service_port
}

output "topic_name" {
  description = "Name of the Kafka topic"
  value       = aiven_kafka_topic.iceberg_topic.topic_name
}

output "connector_name" {
  description = "Name of the Kafka Connect connector"
  value       = aiven_kafka_connector.iceberg_sink.connector_name
}

output "iceberg_user_username" {
  description = "Username of the PostgreSQL user for Iceberg"
  value       = aiven_pg_user.iceberg_user.username
}

output "iceberg_user_password" {
  description = "Password of the PostgreSQL user for Iceberg"
  value       = aiven_pg_user.iceberg_user.password
  sensitive   = true
}

output "project_id" {
  description = "Aiven project ID"
  value       = data.aiven_project.project.id
}

output "s3_warehouse_path" {
  description = "S3 warehouse path for Iceberg"
  value       = "s3://${var.s3_bucket_name}/${var.s3_prefix}/"
}

output "table_name" {
  description = "Iceberg table name"
  value       = var.table_name
}

output "aws_region" {
  description = "AWS region for S3 operations"
  value       = var.aws_region
}
