# Forked service
resource "aiven_pg" "postgres-fork" {
  project      = var.avn_project
  cloud_name   = var.cloud_name
  plan         = var.pg_plan
  service_name = var.service_name
  pg_user_config {
    pg_service_to_fork_from = var.pg_service_to_fork_from
  }
}
