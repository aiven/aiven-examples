resource "aiven_pg" "primary_pg" {
  project = var.aiven_project_name
  cloud_name = var.cloud_name_primary
  plan = var.pg_plan
  service_name = "${var.service_prefix}-primary-pg"
  maintenance_window_dow = "monday"
  maintenance_window_time = "10:00:00"

  pg_user_config {
    pg_version = var.pg_version

    public_access {
      pg = false
      prometheus = false
    }

    pg {
      idle_in_transaction_session_timeout = 900
      log_min_duration_statement = -1
    }
  }

  timeouts {
    create = "20m"
    update = "15m"
  }
}

resource "time_sleep" "wait_pg_primary_readiness" {
  depends_on = [
    aiven_pg.primary_pg
  ]
  create_duration = "1200s"
}