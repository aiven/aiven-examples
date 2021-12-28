resource "aiven_flink" "flink" {
  project      = var.aiven_project
  cloud_name   = var.cloud_name
  plan         = var.flink_plan
  service_name = "flinkdemo-flink"
}

resource "aiven_kafka" "kafka" {
  project      = var.aiven_project
  cloud_name   = var.cloud_name
  plan         = var.kafka_plan
  service_name = "flinkdemo-kafka"
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

resource "aiven_flink_table" "source" {
  project        = aiven_flink.flink.project
  service_name   = aiven_flink.flink.service_name
  integration_id = aiven_service_integration.flink_to_kafka.integration_id
  table_name     = "stock_exchange"
  kafka_topic    = aiven_kafka_topic.source.topic_name
  schema_sql     = <<EOF
    `symbol` VARCHAR,
    `bid_price` DECIMAL(10,2),
    `ask_price` DECIMAL(10,2),
    `time_stamp` BIGINT,
    `ts_ltz` AS TO_TIMESTAMP_LTZ(time_stamp, 3),
    WATERMARK FOR `ts_ltz` AS `ts_ltz` - INTERVAL '3' SECOND 
    EOF
}

resource "aiven_flink_table" "sink" {
  project        = aiven_flink.flink.project
  service_name   = aiven_flink.flink.service_name
  integration_id = aiven_service_integration.flink_to_kafka.integration_id
  table_name     = "stock_data"
  # kafka_connector_type = "upsert-kafka"  
  kafka_topic    = aiven_kafka_topic.sink.topic_name
  schema_sql     = <<EOF
    `symbol` VARCHAR,
    `change_bid_price` DECIMAL(10,2),
    `change_ask_price` DECIMAL(10,2),
    `min_bid_price` DECIMAL(10,2),
    `max_bid_price` DECIMAL(10,2),
    `min_ask_price` DECIMAL(10,2),
    `max_ask_price` DECIMAL(10,2),
    `time_interval` BIGINT,
    `time_stamp` TIMESTAMP(3)
    EOF
}

resource "aiven_flink_job" "flink_job" {
  project      = aiven_flink.flink.project
  service_name = aiven_flink.flink.service_name
  job_name     = "stock_demo_job"
  table_ids = [
    aiven_flink_table.source.table_id,
    aiven_flink_table.sink.table_id,
  ]
  statement = <<EOF
    INSERT INTO ${aiven_flink_table.sink.table_name} 
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
    FROM ${aiven_flink_table.source.table_name}
    GROUP BY symbol, TUMBLE(ts_ltz, INTERVAL '9' SECOND)
    EOF
}
