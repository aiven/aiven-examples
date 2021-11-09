########
# Init #
########

terraform {
  required_providers {
    aiven = {
      source  = "aiven/aiven"
      version = ">= 2.2.1, < 3.0.0"
    }
  }
}
provider "aiven" {
  api_token = var.aiven_api_token
}

###########
# Project #
###########

data "aiven_project" "avn_proj" {
  project = var.aiven_project_name
}
output "aiven_project_balance" {
  value = data.aiven_project.avn_proj.estimated_balance
}

########
# O11Y #
########
module "aiven_for_o11y" {
  source             = "./o11y"
  aiven_project_name = data.aiven_project.avn_proj.project
  service_name       = var.o11y_service_name
  cloud_name         = var.cloud_name
}

output "aiven_for_o11y_dashboard_uri" {
  value     = module.aiven_for_o11y.grafana_service_uri
  sensitive = true
}

output "aiven_for_o11y_logs_uri" {
  value     = module.aiven_for_o11y.opensearch_service_uri
  sensitive = true
}

###########
# Storage #
###########

module "aiven_for_postgresql" {
  source             = "./pg"
  aiven_project_name = data.aiven_project.avn_proj.project
  service_name       = var.db_service_name
  cloud_name         = var.cloud_name
  replica_cloud_name = "google-europe-west3"
}

output "aiven_for_pg_service_uri" {
  value     = module.aiven_for_postgresql.service_uri
  sensitive = true
}

module "aiven_for_redis" {
  source             = "./redis"
  aiven_project_name = data.aiven_project.avn_proj.project
  service_name       = var.redis_service_name
  cloud_name         = var.cloud_name
}

output "aiven_for_redis_service_uri" {
  value     = module.aiven_for_redis.service_uri
  sensitive = true
}

#########
# Kafka #
#########

module "aiven_for_kafka" {
  source             = "./kafka"
  aiven_project_name = data.aiven_project.avn_proj.project
  service_name       = var.kafka_service_name
  cloud_name         = var.cloud_name
}

module "aiven_for_kafka_connect" {
  aiven_project_name = data.aiven_project.avn_proj.project
  service_name       = var.kafka_service_name
  cloud_name         = var.cloud_name

  kafka_service_name = var.kafka_service_name
  source             = "./kafka_connect"
  source_name        = var.db_service_name
  source_db          = module.aiven_for_postgresql.service_db
  sink_name          = var.redis_service_name

  depends_on = [
    module.aiven_for_kafka,
    module.aiven_for_postgresql,
    module.aiven_for_redis,
  ]
}

output "aiven_for_kafka_service_uri" {
  value     = module.aiven_for_kafka.service_uri
  sensitive = true
}

################
# Integrations #
################

## --- Kafka + Connect --- ##

resource "aiven_service_integration" "kafka_metrics" {
  project                  = data.aiven_project.avn_proj.project
  integration_type         = "metrics"
  source_service_name      = var.kafka_service_name
  destination_service_name = module.aiven_for_o11y.influx_service_name
}

resource "aiven_service_integration" "kafka_logs" {
  project                  = data.aiven_project.avn_proj.project
  integration_type         = "logs"
  source_service_name      = var.kafka_service_name
  destination_service_name = module.aiven_for_o11y.opensearch_service_name

  logs_user_config {
    elasticsearch_index_days_max = 3
    elasticsearch_index_prefix   = "kfk_logs"
  }
  kafka_logs_user_config {}

  depends_on = [
    module.aiven_for_kafka,
  ]
}

resource "aiven_service_integration" "kafka_connect_metrics" {
  project                  = data.aiven_project.avn_proj.project
  integration_type         = "metrics"
  source_service_name      = module.aiven_for_kafka_connect.service_name
  destination_service_name = module.aiven_for_o11y.influx_service_name
}

resource "aiven_service_integration" "kafka_connect_logs" {
  project                  = data.aiven_project.avn_proj.project
  integration_type         = "logs"
  source_service_name      = module.aiven_for_kafka_connect.service_name
  destination_service_name = module.aiven_for_o11y.opensearch_service_name

  logs_user_config {
    elasticsearch_index_days_max = 1
  }

  depends_on = [
    module.aiven_for_kafka_connect,
  ]
}

## --- Postgres --- ##

resource "aiven_service_integration" "pg_metrics" {
  project                  = data.aiven_project.avn_proj.project
  integration_type         = "metrics"
  source_service_name      = var.db_service_name
  destination_service_name = module.aiven_for_o11y.influx_service_name

  depends_on = [
    module.aiven_for_postgresql,
  ]
}

resource "aiven_service_integration" "pg_logs" {
  project                  = data.aiven_project.avn_proj.project
  integration_type         = "logs"
  source_service_name      = var.db_service_name
  destination_service_name = module.aiven_for_o11y.opensearch_service_name

  logs_user_config {
    elasticsearch_index_days_max = 7
    elasticsearch_index_prefix   = "logs"
  }

  lifecycle {
    ignore_changes = [
      logs_user_config["elasticsearch_index_days_max"],
      logs_user_config["elasticsearch_index_prefix"],
    ]
  }

  depends_on = [
    module.aiven_for_postgresql,
  ]
}

resource "aiven_service_integration" "pg_replica_metrics" {
  project                  = data.aiven_project.avn_proj.project
  integration_type         = "metrics"
  source_service_name      = module.aiven_for_postgresql.replica_service_name
  destination_service_name = module.aiven_for_o11y.influx_service_name
}

resource "aiven_service_integration" "pg_replica_logs" {
  project                  = data.aiven_project.avn_proj.project
  integration_type         = "logs"
  source_service_name      = module.aiven_for_postgresql.replica_service_name
  destination_service_name = module.aiven_for_o11y.opensearch_service_name

  logs_user_config {
    elasticsearch_index_days_max = 2
  }

  lifecycle {
    ignore_changes = [
      logs_user_config,
    ]
  }

  depends_on = [
    module.aiven_for_postgresql,
  ]
}

## --- Redis --- ##

resource "aiven_service_integration" "redis_metrics" {
  project                  = data.aiven_project.avn_proj.project
  integration_type         = "metrics"
  source_service_name      = var.redis_service_name
  destination_service_name = module.aiven_for_o11y.influx_service_name
}

resource "aiven_service_integration" "redis_logs" {
  project                  = data.aiven_project.avn_proj.project
  integration_type         = "logs"
  source_service_name      = var.redis_service_name
  destination_service_name = module.aiven_for_o11y.opensearch_service_name

  logs_user_config {
    elasticsearch_index_days_max = 5
    elasticsearch_index_prefix   = "rd_logs"
  }

  depends_on = [
    module.aiven_for_redis,
  ]
}
