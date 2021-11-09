locals {
  acl_rules = [
    {
      index      = "_*"
      permission = "admin"
    },
    {
      index      = "*"
      permission = "admin"
    }
  ]
}

resource "aiven_opensearch" "opensearch" {
  project                 = var.aiven_project_name
  cloud_name              = var.cloud_name
  service_name            = local.opensearch_service_name
  plan                    = "startup-8"
  maintenance_window_dow  = "thursday"
  maintenance_window_time = "07:30:00"
  termination_protection  = false

  opensearch_user_config {
    opensearch_version = 1

    opensearch_dashboards {
      enabled                    = true
      opensearch_request_timeout = 30000
    }

    public_access {
      opensearch            = true
      opensearch_dashboards = true
    }

    ip_filter = ["0.0.0.0/0"]

    opensearch {
      action_auto_create_index_enabled = true
    }
  }
}

resource "aiven_service_user" "search_user" {
  project      = var.aiven_project_name
  service_name = aiven_opensearch.opensearch.service_name
  username     = "os_user"
}

resource "aiven_opensearch_acl_config" "os_acls_config" {
  project      = var.aiven_project_name
  service_name = aiven_opensearch.opensearch.service_name
  enabled      = true
  extended_acl = false
}

resource "aiven_opensearch_acl_rule" "search_acl" {
  for_each = { for i, v in local.acl_rules : i => v }

  project      = var.aiven_project_name
  service_name = aiven_opensearch_acl_config.os_acls_config.service_name
  username     = aiven_service_user.search_user.username
  index        = each.value.index
  permission   = each.value.permission
}

output "opensearch_service_uri" {
  value     = aiven_opensearch.opensearch.opensearch[0].opensearch_dashboards_uri
  sensitive = true
}

output "opensearch_service_name" {
  value = aiven_opensearch.opensearch.service_name
}