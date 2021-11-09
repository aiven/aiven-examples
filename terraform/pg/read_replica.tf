variable "replica_cloud_name" {
}

locals {
  replica_service_name = join("-", [var.service_name, "replica"])
}

resource "aiven_pg" "pg_read_replica" {
  project                 = var.aiven_project_name
  cloud_name              = var.replica_cloud_name
  service_name            = local.replica_service_name
  plan                    = "startup-8"
  maintenance_window_dow  = "saturday"
  maintenance_window_time = "07:45:00"
  termination_protection  = false

  service_integrations {
    integration_type    = "read_replica"
    source_service_name = aiven_pg.pg.service_name
  }

  pg_user_config {
    service_to_fork_from = aiven_pg.pg.service_name

    pg {
      idle_in_transaction_session_timeout = 900
    }
    pgbouncer {
      server_reset_query_always = false
    }
    pglookout {
      max_failover_replication_time_lag = 60
    }
  }

  depends_on = [
    aiven_pg.pg,
  ]
}

output "replica_service_uri" {
  value     = aiven_pg.pg_read_replica.service_uri
  sensitive = true
}

output "replica_service_name" {
  value = aiven_pg.pg_read_replica.service_name
}
