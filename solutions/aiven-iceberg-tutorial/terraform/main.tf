terraform {
  required_providers {
    aiven = {
      source  = "aiven/aiven"
      version = "~> 4.0.0"
    }
  }
}

provider "aiven" {
  api_token = var.aiven_api_token
}

# Kafka Service
resource "aiven_kafka" "iceberg_kafka" {
  project      = var.aiven_project_name
  cloud_name   = "aws-us-west-2"
  plan         = "startup-2"
  service_name = "iceberg-kafka"

  kafka_user_config {
    kafka_version = "3.5"
  }
}

# Kafka Topics
resource "aiven_kafka_topic" "product_topic" {
  project      = var.aiven_project_name
  service_name = aiven_kafka.iceberg_kafka.service_name
  topic_name   = "product"
  partitions   = 3
  replication  = 2
}

resource "aiven_kafka_topic" "control_topic" {
  project      = var.aiven_project_name
  service_name = aiven_kafka.iceberg_kafka.service_name
  topic_name   = "iceberg-control"
  partitions   = 3
  replication  = 2
}

# Kafka Connect Service
resource "aiven_kafka_connect" "iceberg_connect" {
  project      = var.aiven_project_name
  cloud_name   = "aws-us-west-2"
  plan         = "startup-4"
  service_name = "iceberg-connect"

  kafka_connect_user_config {
    kafka_connect_version = "3.5"
  }
}

# Kafka Connect Integration
resource "aiven_service_integration" "kafka_connect_integration" {
  project                  = var.aiven_project_name
  integration_type         = "kafka_connect"
  source_service_name      = aiven_kafka.iceberg_kafka.service_name
  destination_service_name = aiven_kafka_connect.iceberg_connect.service_name
}

# Iceberg Sink Connector
resource "aiven_kafka_connector" "iceberg_sink" {
  project        = var.aiven_project_name
  service_name   = aiven_kafka_connect.iceberg_connect.service_name
  connector_name = "iceberg-sink"

  config = {
    "connector.class"                           = "org.apache.iceberg.kafka.connect.IcebergSinkConnector"
    "tasks.max"                                 = "1"
    "topics"                                    = aiven_kafka_topic.product_topic.topic_name
    "iceberg.tables.warehouse.location"         = var.s3_warehouse_location
    "iceberg.tables.catalog"                    = "snowflake"
    "iceberg.tables.catalog.snowflake.uri"      = var.snowflake_uri
    "iceberg.tables.catalog.snowflake.warehouse" = var.snowflake_warehouse
    "iceberg.tables.catalog.snowflake.database" = var.snowflake_database
  }
} 