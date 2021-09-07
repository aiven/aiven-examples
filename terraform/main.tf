########
# Init #
########

terraform {
  # go install github.com/aiven/terraform-provider-aiven@v1.3.5
  # mkdir -p $PWD/terraform.d/plugins/linux_amd64/
  # cp $GOPATH/bin/terraform-provider-aiven $PWD/terraform.d/plugins/linux_amd64/terraform-provider-aiven_v1.3.5
  required_providers {
    aiven = "1.3.5"
    null  = "~> 3.1"
    time  = "0.7.2"
    #postgresql = "1.7.2"
    # sql = {
    #   source  = "paultyng/sql"
    #   version = "0.4.0"
    # }
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
  #value = data.aiven_project.avn_proj.estimated_balance
  value = "n/a"
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
  value = module.aiven_for_o11y.grafana_service_uri
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

  # not supported in 0.12
  # depends_on = [
  #   module.aiven_for_kafka,
  #   module.aiven_for_postgresql,
  #   module.aiven_for_redis,
  # ]
}

output "aiven_for_kafka_service_uri" {
  value = module.aiven_for_kafka.service_uri
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
  # It was added as "default" after creation and it tries to set these values
  # to "null" on a second run
  # this causes 400 error, so I am adding it here *shrug*
  logs_user_config {
    elasticsearch_index_days_max = "3"
    elasticsearch_index_prefix   = "logs"
  }
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
    elasticsearch_index_days_max = "3"
    elasticsearch_index_prefix   = "logs"
  }
}

## --- Postgres --- ##

resource "aiven_service_integration" "pg_metrics" {
  project                  = data.aiven_project.avn_proj.project
  integration_type         = "metrics"
  source_service_name      = var.db_service_name
  destination_service_name = module.aiven_for_o11y.influx_service_name
}

resource "aiven_service_integration" "pg_logs" {
  project                  = data.aiven_project.avn_proj.project
  integration_type         = "logs"
  source_service_name      = var.db_service_name
  destination_service_name = module.aiven_for_o11y.opensearch_service_name
  logs_user_config {
    elasticsearch_index_days_max = "3"
    elasticsearch_index_prefix   = "logs"
  }
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
    elasticsearch_index_days_max = "3"
    elasticsearch_index_prefix   = "logs"
  }
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
    elasticsearch_index_days_max = "3"
    elasticsearch_index_prefix   = "logs"
  }
}
