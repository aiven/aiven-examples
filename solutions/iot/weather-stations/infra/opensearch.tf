# Opensearch service
resource "aiven_opensearch" "tms-demo-os" {
  project = var.avn_project_id
  cloud_name = var.cloud_name
  plan = "startup-4"
  service_name = "tms-demo-os"
  maintenance_window_dow = "monday"
  maintenance_window_time = "10:00:00"
}

# Opensearch user
resource "aiven_service_user" "os-user" {
  project = var.avn_project_id
  service_name = aiven_opensearch.tms-demo-os.service_name
  username = "test-user1"
}
