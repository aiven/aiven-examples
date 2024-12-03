resource "aiven_clickhouse" "clickhouse" {
  project                 = var.aiven_project_name
  cloud_name              = var.cloud_name_primary
  plan                    = var.clickhouse_plan
  service_name            = "${var.service_prefix}-clickhouse"
  maintenance_window_dow  = "sunday"
  maintenance_window_time = "22:00:00"
  termination_protection  = true

  clickhouse_user_config {
    service_log = true
  }
}

resource "time_sleep" "wait_clickhouse_readiness" {
  depends_on = [
    aiven_clickhouse.clickhouse
  ]
  create_duration = "600s"
}