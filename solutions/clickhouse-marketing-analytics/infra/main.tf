# Aiven infra for the demo: ClickHouse (analytics store) + Valkey (ingestion
# buffer / shared config store).
#
# IMPORTANT (Aiven limitation): databases cannot be created via plain SQL on
# Aiven ClickHouse - campaign_analytics MUST be created through the provider
# (aiven_clickhouse_database below), not a migration script.
#
# Apply manually with your Aiven token:
#   terraform init && terraform apply -var="aiven_api_token=..." -var="project=..."

terraform {
  required_version = ">= 1.5"
  required_providers {
    aiven = {
      source  = "aiven/aiven"
      version = ">= 4.0"
    }
  }
}

provider "aiven" {
  api_token = var.aiven_api_token
}

resource "aiven_clickhouse" "campaign_analytics" {
  project      = var.project
  cloud_name   = var.cloud_name # any Aiven region works; pick one close to where the app runs
  plan         = var.clickhouse_plan
  service_name = var.clickhouse_service_name

  clickhouse_user_config {
    clickhouse_version = var.clickhouse_version
    service_log        = true
  }
}

resource "aiven_clickhouse_database" "campaign_analytics" {
  project      = var.project
  service_name = aiven_clickhouse.campaign_analytics.service_name
  name         = "campaign_analytics"
}

# Dedicated demo user so the app never runs as avnadmin.
resource "aiven_clickhouse_user" "demo" {
  project      = var.project
  service_name = aiven_clickhouse.campaign_analytics.service_name
  username     = "demo_ingest"
}

resource "aiven_clickhouse_grant" "demo" {
  project      = var.project
  service_name = aiven_clickhouse.campaign_analytics.service_name
  user         = aiven_clickhouse_user.demo.username

  privilege_grant {
    privilege = "ALL"
    database  = aiven_clickhouse_database.campaign_analytics.name
    table     = "*"
  }
  privilege_grant {
    privilege = "SELECT"
    database  = "system"
  }
}

# Valkey: centralized ingestion buffer (Valkey Streams) + shared runtime
# config store for the flusher (batch size / flush interval hash).
resource "aiven_valkey" "ingest_buffer" {
  project      = var.project
  cloud_name   = var.cloud_name # same region as ClickHouse: the flusher path should never be WAN-bound
  plan         = var.valkey_plan
  service_name = var.valkey_service_name

  valkey_user_config {
    valkey_version = var.valkey_version
  }
}
