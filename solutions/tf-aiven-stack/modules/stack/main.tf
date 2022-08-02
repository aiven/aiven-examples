terraform {
  required_providers {
    aiven = {
      source  = "aiven/aiven"
      version = "3.4.0"
    }
  }
}

resource "aiven_kafka" "kafka" {
  project        = var.project
  cloud_name     = var.cloud_name
  plan           = var.kafka_plan_size
  service_name   = "${var.prefix}kafka"
  project_vpc_id = var.vpc_id

  maintenance_window_dow  = var.maint_dow
  maintenance_window_time = var.maint_time

  kafka_user_config {
    kafka_connect   = true
    kafka_rest      = true
    schema_registry = true
    kafka_version   = var.kafka_version

    # example of setting advanced parameters
    # kafka {
    #       group_max_session_timeout_ms = 70000
    #       log_retention_bytes = 1000000000
    #       auto_create_topics_enable = true
    #     }

  }

}

resource "aiven_opensearch" "opensearch_log_analytics" {
  project        = var.project
  cloud_name     = var.cloud_name
  project_vpc_id = var.vpc_id
  plan           = var.os_log_analytics_plan
  service_name   = "${var.prefix}os-log-analytics"

  maintenance_window_dow  = var.maint_dow
  maintenance_window_time = var.maint_time

  opensearch_user_config {
    opensearch_version = var.os_version

    ip_filter = var.ip_filter

    opensearch_dashboards {
      enabled                    = true
      opensearch_request_timeout = 30000
    }

    public_access {
      opensearch            = true
      opensearch_dashboards = true
    }
  }
}

resource "aiven_opensearch" "opensearch_logs_1" {
  project        = var.project
  cloud_name     = var.cloud_name
  project_vpc_id = var.vpc_id
  plan           = var.os_log_internal_plan
  service_name   = "${var.prefix}os-log-1"
  disk_space     = var.opensearch_logs_total_disk

  maintenance_window_dow  = var.maint_dow
  maintenance_window_time = var.maint_time

  opensearch_user_config {
    opensearch_version = var.os_version

    ip_filter = var.ip_filter

    opensearch_dashboards {
      enabled                    = true
      opensearch_request_timeout = 30000
    }

    public_access {
      opensearch            = false
      opensearch_dashboards = false
    }
  }
}

resource "aiven_opensearch" "opensearch_logs_2" {
  project        = var.project
  cloud_name     = var.cloud_name
  project_vpc_id = var.vpc_id
  plan           = var.os_log_internal_plan
  service_name   = "${var.prefix}os-log-2"

  maintenance_window_dow  = var.maint_dow
  maintenance_window_time = var.maint_time

  opensearch_user_config {
    opensearch_version = var.os_version

    ip_filter = var.ip_filter

    opensearch_dashboards {
      enabled                    = true
      opensearch_request_timeout = 30000
    }

    public_access {
      opensearch            = false
      opensearch_dashboards = false
    }
  }
}

resource "aiven_opensearch" "opensearch_logs_3" {
  project        = var.project
  cloud_name     = var.cloud_name
  project_vpc_id = var.vpc_id
  plan           = var.os_log_internal_plan
  service_name   = "${var.prefix}os-log-3"

  maintenance_window_dow  = var.maint_dow
  maintenance_window_time = var.maint_time

  opensearch_user_config {
    opensearch_version = var.os_version

    ip_filter = var.ip_filter

    opensearch_dashboards {
      enabled                    = true
      opensearch_request_timeout = 30000
    }

    public_access {
      opensearch            = false
      opensearch_dashboards = false
    }
  }
}

resource "aiven_opensearch" "opensearch_logs_4" {
  project        = var.project
  cloud_name     = var.cloud_name
  project_vpc_id = var.vpc_id
  plan           = var.os_log_internal_plan
  service_name   = "${var.prefix}os-log-4"

  maintenance_window_dow  = var.maint_dow
  maintenance_window_time = var.maint_time

  opensearch_user_config {
    opensearch_version = var.os_version

    ip_filter = var.ip_filter

    opensearch_dashboards {
      enabled                    = true
      opensearch_request_timeout = 30000
    }

    public_access {
      opensearch            = false
      opensearch_dashboards = false
    }
  }
}

output "kafka_service_name" {
  value = aiven_kafka.kafka.service_name
}

output "os_la_service_name" {
  value = aiven_opensearch.opensearch_log_analytics.service_name
}

output "os_logs_1_service_name" {
  value = aiven_opensearch.opensearch_logs_1.service_name
}

output "os_logs_2_service_name" {
  value = aiven_opensearch.opensearch_logs_2.service_name
}

output "os_logs_3_service_name" {
  value = aiven_opensearch.opensearch_logs_3.service_name
}

output "os_logs_4_service_name" {
  value = aiven_opensearch.opensearch_logs_4.service_name
}
