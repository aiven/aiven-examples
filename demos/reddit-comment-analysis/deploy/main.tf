terraform {
  required_providers {
    aiven = {
      source  = "aiven/aiven"
      version = "2.0.6"
    }
  }
}

provider "aiven" {
  api_token = var.aiven_api_token
}

data "aiven_project" "bd" {
  project = var.project
}


resource "aiven_service" "kf" {
  project                 = data.aiven_project.bd.project
  cloud_name              = "google-europe-west1"
  plan                    = "business-4"
  service_name            = var.kafka_svc
  service_type            = "kafka"
  maintenance_window_dow  = "monday"
  maintenance_window_time = "10:00:00"
  kafka_user_config {
    kafka_rest      = true
    kafka_connect   = true
    schema_registry = true
    kafka_version   = "2.6"
    ip_filter       = ["0.0.0.0/0", "80.242.179.94", "188.166.141.226"]
    kafka {
      group_max_session_timeout_ms = 70000
      log_retention_bytes          = 1000000000
    }
    public_access {
      kafka_rest    = true
      kafka_connect = true
      prometheus    = true
    }
  }
}

resource "aiven_service" "es" {
  project                 = data.aiven_project.bd.project
  cloud_name              = "google-europe-north1"
  plan                    = "business-4"
  service_name            = var.es_svc
  service_type            = "elasticsearch"
  maintenance_window_dow  = "monday"
  maintenance_window_time = "10:00:00"

  elasticsearch_user_config {
    elasticsearch_version = "7"
    
    kibana {
      enabled = true
      elasticsearch_request_timeout = 30000
    }
    public_access {
      elasticsearch = true
      kibana = true
    }
    index_patterns {
      pattern = "logs_kf*"
      max_index_count = 3
    }
  }
}

resource "aiven_kafka_connector" "kf-es-conn" {
  project      = data.aiven_project.bd.project
  service_name = aiven_service.kf.service_name
  depends_on = [
    aiven_service.es,
    aiven_service.kf
  ]
  connector_name = "kf-es-conn"

  config = {
    "topics" = "reddit_comments"
    "connector.class" : "io.aiven.connect.elasticsearch.ElasticsearchSinkConnector"
    "type.name"                      = "es-connector"
    "name"                           = "kf-es-conn"
    "connection.url"                 = aiven_service.es.service_uri
    "key.converter"                  = "org.apache.kafka.connect.json.JsonConverter",
    "value.converter"                = "org.apache.kafka.connect.json.JsonConverter",
    "key.ignore"                     = "true",
    "schema.ignore"                  = "true",
    "value.converter.schemas.enable" = "false",
    "key.converter.schemas.enable"   = "false"
  }
}

resource "aiven_service_integration" "kf_logs" {
  project = data.aiven_project.bd.project
  integration_type = "logs"
  source_service_name = aiven_service.kf.service_name
  destination_service_name = aiven_service.es.service_name
  depends_on = [
    aiven_service.es,
    aiven_service.kf
  ]
  
  logs_user_config {
    elasticsearch_index_prefix = "logs_kf-"
  }
}

resource "aiven_service_user" "es_user" {
  service_name = aiven_service.es.service_name
  project = data.aiven_project.bd.project
  username = "es-user"
  depends_on = [
    aiven_service.es,
    aiven_service.kf
  ]
}

resource "aiven_service_user" "kf_user" {
  service_name = aiven_service.kf.service_name
  project = data.aiven_project.bd.project
  username = "kf-user"
  depends_on = [
    aiven_service.es,
    aiven_service.kf
  ]
}

resource "aiven_elasticsearch_acl" "es_acl" {
  project = data.aiven_project.bd.project
  service_name = aiven_service.es.service_name
  enabled = true
  extended_acl = false
  depends_on = [
    aiven_service_user.es_user
  ]
  acl {
    username = aiven_service_user.es_user.username
    rule {
      index = "_*"
      permission = "admin"
    }

    rule {
      index = "reddit*"
      permission = "admin"
    }
    
    rule {
      index = "logs_kf*"
      permission = "read"
    }
  }
}



