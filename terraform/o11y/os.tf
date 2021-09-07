resource "aiven_service" "opensearch" {
  service_type            = "elasticsearch"
  project                 = var.aiven_project_name
  cloud_name              = var.cloud_name
  service_name            = local.opensearch_service_name
  plan                    = "startup-8"
  maintenance_window_dow  = "thursday"
  maintenance_window_time = "07:30:00"
  termination_protection  = false

  elasticsearch_user_config {
    elasticsearch_version = "7"
    ip_filter             = ["0.0.0.0/0"]

    elasticsearch {
      action_auto_create_index_enabled = true
    }
  }
}

resource "aiven_service_user" "search_user" {
  project      = var.aiven_project_name
  service_name = aiven_service.opensearch.service_name
  username     = "os_user"
}

resource "aiven_elasticsearch_acl" "search_acl" {
  project      = var.aiven_project_name
  service_name = aiven_service.opensearch.service_name
  enabled      = true
  acl {
    username = aiven_service_user.search_user.username
    rule {
      index      = "_*"
      permission = "admin"
    }
    rule {
      index      = "*"
      permission = "admin"
    }
  }
}

output "opensearch_service_uri" {
  value     = aiven_service.opensearch.elasticsearch[0].kibana_uri
  sensitive = true
}

output "opensearch_service_name" {
  value = aiven_service.opensearch.service_name
}