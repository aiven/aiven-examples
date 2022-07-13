resource "aiven_kafka" "kafka-data" {
  project = var.aiven_project_name
  cloud_name = var.cloud
  plan = var.kafka_plan
  service_name = "${var.service_prefix}-kafka-data"
  maintenance_window_dow = "monday"
  maintenance_window_time = "10:00:00"
  kafka_user_config {
    kafka_connect = true
    kafka_rest = true
    schema_registry = true
    kafka_version = "3.1"
    kafka {
      auto_create_topics_enable = true
    }
  }
}

resource "aiven_kafka" "kafka-logs" {
  project = var.aiven_project_name
  cloud_name = var.cloud
  plan = var.kafka_plan
  service_name = "${var.service_prefix}-kafka-logs"
  maintenance_window_dow = "monday"
  maintenance_window_time = "10:00:00"
  kafka_user_config {
    kafka_connect = true
    kafka_rest = true
    schema_registry = true
    kafka_version = "3.1"
    kafka {
      auto_create_topics_enable = true
    }
  }
}

resource "aiven_kafka_connect" "kafka-connect" {
  project = var.aiven_project_name
  cloud_name = var.cloud
  plan = "startup-4"
  service_name = "${var.service_prefix}-kafka-connect"
  maintenance_window_dow = "monday"
  maintenance_window_time = "10:00:00"

  kafka_connect_user_config {
    kafka_connect {
      consumer_isolation_level = "read_committed"
    }

    public_access {
      kafka_connect = true
    }
  }
}

resource "aiven_service_integration" "kafka-logs" {
  project = var.aiven_project_name
  integration_type = "kafka_logs"
  source_service_name = aiven_kafka.kafka-data.service_name
  destination_service_name = aiven_kafka.kafka-logs.service_name
  kafka_logs_user_config {
    kafka_topic = "logs"
  }

}

resource "aiven_service_integration" "kafka-splunk" {
  project = var.aiven_project_name
  integration_type = "kafka_connect"
  source_service_name = aiven_kafka.kafka-logs.service_name
  destination_service_name = aiven_kafka_connect.kafka-connect.service_name
}

resource "time_sleep" "wait_60_seconds" {
  depends_on = [
    aiven_kafka.kafka-logs,
    aiven_kafka_connect.kafka-connect,
    aiven_service_integration.kafka-splunk
  ]
  create_duration = "60s"
}

resource "aiven_kafka_connector" "splunk" {
  depends_on = [
    time_sleep.wait_60_seconds,
  ]
  project = var.aiven_project_name
  service_name = aiven_kafka_connect.kafka-connect.service_name
  connector_name = "kafka-splunk-logs"

  config = {
    "name" = "kafka-splunk-logs"
    "connector.class" = "com.splunk.kafka.connect.SplunkSinkConnector"
    "splunk.hec.uri" = var.splunk_hec_uri
    "splunk.hec.token" = var.splunk_hec_token
    "tasks.max" = 1
    "topics" = "logs"
    "splunk.hec.ssl.validate.certs" = false
    "config.splunk.hec.json.event.formatted" = false
    "splunk.hec.raw" = false
    "splunk.hec.ack.enabled" = false
  }
}
