resource "aiven_grafana" "grafana" {
  project                = var.aiven_project_name
  cloud_name             = var.cloud_name
  service_name           = local.grafana_service_name
  plan                   = "startup-4"
  termination_protection = false

  grafana_user_config {
    ip_filter = ["0.0.0.0/0"]
  }
}

output "grafana_service_name" {
  value = aiven_grafana.grafana.service_name
}

output "grafana_service_uri" {
  value = aiven_grafana.grafana.service_uri
}

output "grafana_service_username" {
  value = aiven_grafana.grafana.service_username
}

output "grafana_service_password" {
  value     = aiven_grafana.grafana.service_password
  sensitive = true
}