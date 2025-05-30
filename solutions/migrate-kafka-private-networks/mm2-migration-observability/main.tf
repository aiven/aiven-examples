resource "aiven_opensearch" "os" {
  project                 = var.project
  cloud_name              = var.cloud_name
  plan                    = var.os_log_integration_plan
  service_name            = "os-logs"
  maintenance_window_dow  = var.maint_dow
  maintenance_window_time = var.maint_time

  # depends_on = [aiven_account_team_project.account_team_project]
}

resource "aiven_grafana" "gr" {
  project                 = var.project
  cloud_name              = var.cloud_name
  // project_vpc_id          = var.vpc_id  //Not reuqired for BYOC
  plan                    = var.grafana_integration_plan
  service_name            = "metrics-dashboard"
  maintenance_window_dow  = var.maint_dow
  maintenance_window_time = var.maint_time

  grafana_user_config {
    alerting_enabled = true

    public_access {
      grafana = false
    }
  }
}

resource "aiven_thanos" "thanos_metrics" {
  project                 = var.project
  cloud_name              = var.cloud_name
  //project_vpc_id          = var.vpc_id //Not required for BYOC
  plan                    = var.thanos_plan
  service_name            = "thanos-metrics-demo"
  maintenance_window_dow  = var.maint_dow
  maintenance_window_time = var.maint_time

  thanos_user_config {
    compactor {
      retention_days = "90"
    }
    object_storage_usage_alert_threshold_gb = "100"
    query{
      query_timeout = "3m"
    }
  }
}
resource "aiven_service_integration" "logging" {
  //for_each                 = toset(var.svcs)
  project                  = var.project
  source_service_name      = var.source_service_name
  integration_type         = "logs"
  destination_service_name = aiven_opensearch.os.service_name

  logs_user_config {
    elasticsearch_index_days_max = "3"
    elasticsearch_index_prefix   = "logs"
  }
}


resource "aiven_service_integration" "metrics" {
  //for_each                 = toset(var.svcs)
  project                  = var.project
  destination_service_name = aiven_thanos.thanos_metrics.service_name
  integration_type         = "metrics"
  //source_service_name      = each.key
  source_service_name      = var.source_service_name
}


resource "aiven_service_integration" "metricsdash" {
  project                  = var.project
  source_service_name      = aiven_grafana.gr.service_name
  integration_type         = "dashboard"
  destination_service_name = aiven_thanos.thanos_metrics.service_name
}

resource "aiven_service_integration_endpoint" "prom" {
  project       = var.project
  endpoint_name = var.prom_name
  endpoint_type = "prometheus"
  prometheus_user_config {
    basic_auth_username = var.prom_username
    basic_auth_password = var.prom_password
  }
}

resource "aiven_service_integration" "rsys_int" {
  //for_each                = toset(var.svcs)
  project                 = var.project
  destination_endpoint_id = aiven_service_integration_endpoint.prom.id
  integration_type        = "prometheus"
  //source_service_name     = each.key
  source_service_name     = var.source_service_name

}