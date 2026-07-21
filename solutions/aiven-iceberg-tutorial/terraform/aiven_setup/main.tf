terraform {
  required_providers {
    aiven = {
      source  = "aiven/aiven"
      version = ">= 4.38.0"
    }
  }
}

provider "aiven" {
  api_token = var.aiven_api_token
}

# The Kafka Service for the Iceberg use case
resource "aiven_kafka" "iceberg_kafka" {
  project      = var.aiven_project_name
  cloud_name   = var.cloud_name
  plan         = "business-4"
  service_name = var.aiven_kafka_name

  kafka_user_config {
    kafka_version = "3.9"

    # Enable both cert (mTLS, used by the connector + Go producer) and SASL.
    # SASL must be enabled for the Let's Encrypt public CA cert below.
    kafka_authentication_methods {
      certificate = true
      sasl        = true
    }

    # Serve a publicly-trusted Let's Encrypt CA certificate on the SASL listener,
    # so SASL_SSL clients can validate the broker without the Aiven project CA.
    letsencrypt_sasl = true
  }
}

# Create Kafka Topics (1 for use case and 1 for control).
# The data topic is the Debezium CDC output topic (<topic.prefix>.<schema>.<table>
# from the Debezium Postgres source connector) — pre-created here so the sink can
# subscribe immediately, regardless of the source connector's topic.creation settings.
resource "aiven_kafka_topic" "cdc_orders_topic" {
  project      = var.aiven_project_name
  service_name = aiven_kafka.iceberg_kafka.service_name
  topic_name   = var.cdc_orders_topic
  partitions   = 3
  replication  = 2
}

resource "aiven_kafka_topic" "control_topic" {
  project      = var.aiven_project_name
  service_name = aiven_kafka.iceberg_kafka.service_name
  topic_name   = var.iceberg_control_topic
  partitions   = 3
  replication  = 2
}

# Create the Kafka Connect Service that will be used to connect to the Kafka topics and connect to apache iceberg sink connector
resource "aiven_kafka_connect" "iceberg_kafka_connect" {
  project                 = var.aiven_project_name
  cloud_name              = var.cloud_name
  service_name            = "${aiven_kafka.iceberg_kafka.service_name}-connect"
  plan                    = "business-4"

  kafka_connect_user_config {
    public_access {
      kafka_connect = true
    }
  }
}

# Kafka Connect Integration that actually connects the Kafka service to the Kafka Connect Service
resource "aiven_service_integration" "kafka_connect_integration" {
  project                  = var.aiven_project_name
  integration_type         = "kafka_connect"
  source_service_name      = aiven_kafka.iceberg_kafka.service_name
  destination_service_name = aiven_kafka_connect.iceberg_kafka_connect.service_name
}

# Iceberg Sink Connector (CDC change log).
# Consumes the Debezium CDC topic (envelope already unwrapped by the source
# connector's ExtractNewRecordState transform) and APPENDS every change event
# to the Iceberg table: one row per insert/update, so an order_id appears once
# per status transition and the table is a full order-history log. Current
# state = latest row per order_id (row_number() OVER ... ORDER BY updated_at
# DESC). NOTE: the Apache Iceberg Kafka Connect sink has no upsert/delta-write
# mode (that was a Tabular-connector feature not carried into the donation) —
# append is the only write path.
resource "aiven_kafka_connector" "iceberg_sink" {
  project        = var.aiven_project_name
  service_name   = aiven_kafka_connect.iceberg_kafka_connect.service_name
  connector_name = "${aiven_kafka.iceberg_kafka.service_name}-iceberg-sink"
  config = {
    "name": "${aiven_kafka.iceberg_kafka.service_name}-iceberg-sink"
    "iceberg.tables" = var.iceberg_catalog_tables_config
    "iceberg.tables.auto-create-enabled" = "true"
    "iceberg.tables.evolve-schema-enabled" = "true"
    "iceberg.tables.default-id-columns" = var.iceberg_table_id_columns
    "iceberg.control.topic" = var.iceberg_control_topic
    "iceberg.control.commit.interval-ms" = "5000"
    "iceberg.control.commit.timeout-ms" = "20000"
    "connector.class" = "org.apache.iceberg.connect.IcebergSinkConnector"
    "tasks.max" = "1"
    "key.converter" = "org.apache.kafka.connect.json.JsonConverter"
    "value.converter" = "org.apache.kafka.connect.json.JsonConverter"
    "topics" = aiven_kafka_topic.cdc_orders_topic.topic_name
    "iceberg.catalog.credential" = "${var.snowflake_client_id}:${var.snowflake_client_secret}"
    "iceberg.catalog.io-impl" = "org.apache.iceberg.aws.s3.S3FileIO"
    "iceberg.catalog.scope" = var.iceberg_catalog_scope
    "iceberg.catalog.type" = "rest"
    "iceberg.catalog.uri" = var.iceberg_catalog_uri
    "iceberg.catalog.warehouse" = var.iceberg_catalog_name
    "iceberg.kafka.bootstrap.servers" = aiven_kafka.iceberg_kafka.service_uri
    "key.converter.schemas.enable" = "false"
    "iceberg.catalog.client.region" = var.iceberg_catalog_region
    "iceberg.kafka.security.protocol" = "SSL"
    "iceberg.kafka.ssl.key.password" = "password"
    "iceberg.kafka.ssl.keystore.location"=  "/run/aiven/keys/public.keystore.p12"
    "iceberg.kafka.ssl.keystore.password" = "password"
    "iceberg.kafka.ssl.keystore.type" =  "PKCS12"
    "iceberg.kafka.ssl.truststore.location" = "/run/aiven/keys/public.truststore.jks"
    "iceberg.kafka.ssl.truststore.password" ="password"
    "iceberg.catalog.s3.path-style-access" = "true"
    "consumer.override.auto.offset.reset" = "earliest"
    "iceberg.kafka.auto.offset.reset" = "earliest"
    "iceberg.catalog.s3.access-key-id" = var.aws_access_key_id
    "iceberg.catalog.s3.secret-access-key" = var.aws_secret_access_key
    "value.converter.schemas.enable" = "false"
  } 
} 