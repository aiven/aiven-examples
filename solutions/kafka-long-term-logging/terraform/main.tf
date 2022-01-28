terraform {
  required_providers {
    aiven = {
      source  = "aiven/aiven"
      version = "2.5.0"
    }
  }
}

provider "google" {
  project = var.google_project
  region  = "europe-west3"
}

provider "aiven" {
  api_token = var.aiven_api_token
}

data "aiven_project" "proj" {
  project = var.project
}


resource "aiven_kafka" "kf" {
  project                 = var.project
  cloud_name              = var.cloud
  plan                    = "business-4"
  service_name            = var.kafka_svc
  maintenance_window_dow  = "saturday"
  maintenance_window_time = "10:00:00"

  kafka_user_config {
    kafka_connect   = true
    kafka_rest      = true
    kafka_version   = "3.0"
    schema_registry = true

    kafka {
      group_max_session_timeout_ms = 70000
      log_retention_bytes          = 1000000000
      auto_create_topics_enable    = true
    }
  }
}

resource "aiven_opensearch" "es" {
  project                 = var.project
  cloud_name              = var.cloud
  plan                    = "hobbyist"
  service_name            = var.es_svc
  maintenance_window_dow  = "monday"
  maintenance_window_time = "10:00:00"

  opensearch_user_config {

    index_patterns {
      max_index_count   = 14
      pattern           = "logger-*"
      sorting_algorithm = "creation_date"
    }
  }
}

resource "aiven_kafka_connector" "kf-es-conn" {
  project      = var.project
  service_name = aiven_kafka.kf.service_name
  depends_on = [
    aiven_opensearch.es,
    aiven_kafka.kf
  ]
  connector_name = "kf-es-conn"

  config = {
    "name"                                = "kf-es-conn",
    "connector.class"                     = "io.aiven.connect.elasticsearch.ElasticsearchSinkConnector",
    "transforms"                          = "routeTS",
    "topics"                              = "logger",
    "errors.deadletterqueue.topic.name"   = "es-logger-errors",
    "connection.url"                      = "${aiven_opensearch.es.service_uri}",
    "batch.size"                          = "10",
    "type.name"                           = "_doc",
    "key.ignore"                          = "true",
    "schema.ignore"                       = "true",
    "format.output.fields"                = "key, value, offset, timestamp, headers",
    "format.output.type"                  = "json",
    "file.compression.type"               = "gzip",
    "transforms.routeTS.topic.format"     = "$${topic}-$${timestamp}",
    "transforms.routeTS.type"             = "org.apache.kafka.connect.transforms.TimestampRouter",
    "transforms.routeTS.timestamp.format" = "yyyy_MM_dd"
  }

}

resource "aiven_kafka_connector" "kf-gcs-conn" {
  project      = var.project
  service_name = aiven_kafka.kf.service_name
  depends_on = [
    aiven_opensearch.es,
    aiven_kafka.kf
  ]
  connector_name = "kf-gcs-conn"

  config = {
    "name"                  = "kf-gcs-conn",
    "connector.class"       = "io.aiven.kafka.connect.gcs.GcsSinkConnector",
    "topics"                = "logger",
    "gcs.credentials.json"  = "${file("${path.module}/gcreds.json")}",
    "gcs.bucket.name"       = "logging_example",
    "file.name.template"    = "{{topic}}/{{timestamp:unit=yyyy}}-{{timestamp:unit=MM}}-{{timestamp:unit=dd}}/{{partition}}-{{start_offset}}.gz",
    "file.compression.type" = "gzip",
    "file.name.prefix"      = "test_logs_json/",
    "file.max.records"      = "500",
    "format.output.type"    = "json",
    "format.output.fields"  = "key, value, offset, timestamp, headers"
  }
}

resource "aiven_service_integration" "logging" {
  project                  = var.project
  source_service_name      = aiven_kafka.kf.service_name
  integration_type         = "kafka_logs"
  destination_service_name = aiven_kafka.kf.service_name
  depends_on               = [aiven_kafka.kf]
  kafka_logs_user_config {
    kafka_topic = "logger"
  }
}


module "gcp" {
  source = "./gcp"

  os_host = aiven_opensearch.es.service_host
  os_user = aiven_opensearch.es.service_username
  os_pass = aiven_opensearch.es.service_password
  os_port = aiven_opensearch.es.service_port
  gcs_bucket = var.gcs_bucket

  depends_on = [
    aiven_opensearch.es
  ]
}
