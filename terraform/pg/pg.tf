terraform {
  required_providers {
    aiven = {
      source  = "aiven/aiven"
      version = ">= 2.2.1, < 3.0.0"
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.1"
    }
  }
}

variable "aiven_project_name" {
}
variable "cloud_name" {
}
variable "service_name" {
}

locals {
  anv_pg_username = "pguser"
  avn_pg_dbname   = "avn_db"
  avn_pg_poolname = "pgpool"
}

resource "aiven_pg" "pg" {
  project                 = var.aiven_project_name
  cloud_name              = var.cloud_name
  service_name            = var.service_name
  plan                    = "business-4"
  maintenance_window_dow  = "friday"
  maintenance_window_time = "20:00:00"
  termination_protection  = false

  pg_user_config {
    pg_version = "13"

    pg {
      idle_in_transaction_session_timeout = 900
    }
    pgbouncer {
      autodb_max_db_connections = 200
      min_pool_size             = 50
      server_reset_query_always = false
    }
  }
}

resource "aiven_database" "pg_db" {
  project       = var.aiven_project_name
  service_name  = aiven_pg.pg.service_name
  database_name = local.avn_pg_dbname
}

resource "aiven_service_user" "pg_user" {
  project      = var.aiven_project_name
  service_name = aiven_pg.pg.service_name
  username     = local.anv_pg_username
}

resource "aiven_connection_pool" "pg_conn_pool" {
  project       = var.aiven_project_name
  service_name  = aiven_pg.pg.service_name
  database_name = aiven_database.pg_db.database_name
  pool_name     = local.avn_pg_poolname
  username      = aiven_service_user.pg_user.username

  depends_on = [
    aiven_database.pg_db,
  ]
}

output "service_uri" {
  value     = aiven_pg.pg.service_uri
  sensitive = true
}

output "service_db" {
  value = local.avn_pg_dbname
}