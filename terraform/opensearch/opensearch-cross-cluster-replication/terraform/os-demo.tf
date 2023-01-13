resource "aiven_opensearch" "leader" {
  project                 = var.project
  cloud_name              = var.cloud_name_os_leader
  plan                    = var.os_leader_plan
  service_name            = "os-leader"
  maintenance_window_dow  = var.maint_dow
  maintenance_window_time = var.maint_time

  # depends_on = [aiven_account_team_project.account_team_project]
}

resource "aiven_opensearch" "follower" {
  project                 = var.project
  cloud_name              = var.cloud_name_os_follower
  plan                    = var.os_follower_plan
  service_name            = "os-follower"
  maintenance_window_dow  = var.maint_dow
  maintenance_window_time = var.maint_time
  service_integrations {
    integration_type    = "opensearch_cross_cluster_replication"
    source_service_name = aiven_opensearch.leader.service_name
  }

  # depends_on = [aiven_account_team_project.account_team_project]
}

/*resource "aiven_service_integration" "replica" {
  project                  = var.project
  source_service_name      = aiven_opensearch.leader.service_name
  integration_type         = "opensearch_cross_cluster_replication"
  destination_service_name = aiven_opensearch.follower.service_name

  logs_user_config {
    elasticsearch_index_days_max = "3"
  }
}*/