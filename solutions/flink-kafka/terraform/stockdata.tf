resource "aiven_flink" "flink" {
  project      = var.aiven_project
  cloud_name   = var.cloud_name
  plan         = var.flink_plan
  service_name = "stockdata-flink"
}

resource "aiven_kafka" "kafka" {
  project      = var.aiven_project
  cloud_name   = var.cloud_name
  plan         = var.kafka_plan
  service_name = "stockdata-kafka"
  kafka_user_config {
    kafka_rest      = "true"
  }
}

resource "aiven_service_integration" "flink_to_kafka" {
  project                  = var.aiven_project
  integration_type         = "flink"
  destination_service_name = aiven_flink.flink.service_name
  source_service_name      = aiven_kafka.kafka.service_name
}

resource "aiven_kafka_topic" "source" {
  project      = aiven_kafka.kafka.project
  service_name = aiven_kafka.kafka.service_name
  partitions   = 2
  replication  = 3
  topic_name   = "source_topic"
}

resource "aiven_kafka_topic" "sink" {
  project      = aiven_kafka.kafka.project
  service_name = aiven_kafka.kafka.service_name
  partitions   = 2
  replication  = 3
  topic_name   = "sink_topic"
}

resource "aiven_flink_application" "stock-data" {
  project      = var.aiven_project
  service_name = aiven_flink.flink.service_name
  name         = "stock-data"
}

resource "aiven_flink_application_version" "stock-data-version" {
  project      = aiven_flink.flink.project
  service_name = aiven_flink.flink.service_name
  application_id = aiven_flink_application.stock-data.application_id
  statement = <<EOT
    INSERT INTO stock_sink 
    SELECT
      symbol,
      max(bid_price)-min(bid_price),
      max(ask_price)-min(ask_price),
      min(bid_price),
      max(bid_price),
      min(ask_price),
      max(ask_price),
      TIMESTAMPDIFF(SECOND, min(ts_ltz),max(ts_ltz)),
      CURRENT_TIMESTAMP
    FROM stock_source
    GROUP BY symbol, TUMBLE(ts_ltz, INTERVAL '9' SECOND)
  EOT
  sink {
    create_table   = <<EOT
      CREATE TABLE stock_sink (
        symbol VARCHAR,
        change_bid_price DECIMAL(10,2),
        change_ask_price DECIMAL(10,2),
        min_bid_price DECIMAL(10,2),
        max_bid_price DECIMAL(10,2),
        min_ask_price DECIMAL(10,2),
        max_ask_price DECIMAL(10,2),
        time_interval BIGINT,
        time_stamp TIMESTAMP(3)
    ) WITH (
        'connector' = 'kafka',
        'properties.bootstrap.servers' = '',
        'scan.startup.mode' = 'earliest-offset',
        'topic' = 'sink_topic',
        'value.format' = 'json'
    )
    EOT
    integration_id = aiven_service_integration.flink_to_kafka.integration_id
  }
  source {
    create_table   = <<EOT
      CREATE TABLE stock_source (
        symbol VARCHAR,
        bid_price DECIMAL(10,2),
        ask_price DECIMAL(10,2),
        time_stamp BIGINT,
        ts_ltz AS NOW(),
        WATERMARK FOR ts_ltz AS ts_ltz
    ) WITH (
        'connector' = 'kafka',
        'properties.bootstrap.servers' = '',
        'scan.startup.mode' = 'earliest-offset',
        'topic' = 'source_topic',
        'value.format' = 'json'
    )
    EOT
    integration_id = aiven_service_integration.flink_to_kafka.integration_id
  }
}

resource "aiven_flink_application_deployment" "stock-data-version" {
  project      = aiven_flink.flink.project
  service_name = aiven_flink.flink.service_name
  application_id = aiven_flink_application.stock-data.application_id
  version_id = aiven_flink_application_version.stock-data-version.application_version_id
}
