resource "aiven_mysql" "mysql" {
  project      = var.project_name
  cloud_name   = var.cloud_name
  plan         = var.mysql_plan
  service_name = var.mysql_service
}

resource "aiven_service_integration_endpoint" "datadog" {
  project       = var.project_name
  endpoint_name = var.endpoint_name
  endpoint_type = "datadog"

  datadog_user_config {
    datadog_api_key = var.datadog_api_key
    datadog_tags {
      tag = var.tag
    }
    site = var.datadog_site
  }
}

resource "aiven_service_integration" "mysql_to_datadog" {
  project                  = var.project_name
  integration_type         = "datadog"
  destination_endpoint_id = aiven_service_integration_endpoint.datadog.id
  source_service_name      = aiven_mysql.mysql.service_name
}

