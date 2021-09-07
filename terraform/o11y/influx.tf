resource "aiven_service" "influx" {
  service_type            = "influxdb"
  project                 = var.aiven_project_name
  cloud_name              = var.cloud_name
  service_name            = local.influx_service_name
  plan                    = "startup-4"
  maintenance_window_dow  = "monday"
  maintenance_window_time = "11:00:00"
  termination_protection  = false

  influxdb_user_config {
    ip_filter = ["0.0.0.0/0"]
  }
}

output "influx_service_uri" {
  value = aiven_service.influx.service_uri
}

output "influx_service_name" {
  value = aiven_service.influx.service_name
}