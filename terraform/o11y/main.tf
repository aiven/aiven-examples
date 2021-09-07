variable "aiven_project_name" {
}
variable "cloud_name" {
}
variable "service_name" {
}

locals {
  influx_service_name     = join("-", [var.service_name, "influxdb"])
  grafana_service_name    = join("-", [var.service_name, "grafana"])
  opensearch_service_name = join("-", [var.service_name, "os"])
}

resource "aiven_service_integration" "grafana_dashboards" {
  project                  = var.aiven_project_name
  integration_type         = "dashboard"
  source_service_name      = aiven_service.grafana.service_name
  destination_service_name = aiven_service.influx.service_name

  depends_on = [
    aiven_service.grafana,
    aiven_service.influx,
  ]
}

resource "aiven_service_integration" "os_metrics" {
  project                  = var.aiven_project_name
  integration_type         = "metrics"
  source_service_name      = local.opensearch_service_name
  destination_service_name = local.influx_service_name

  depends_on = [
    aiven_service.opensearch,
    aiven_service.influx,
  ]
}
