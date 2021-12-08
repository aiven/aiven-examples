resource "aiven_pg" "tms-demo-pg" {
    project = var.avn_project_id
    cloud_name = var.cloud_name
    plan = "startup-4"
    service_name = "tms-demo-pg"    
}

data "aiven_service_user" "pg_admin" {
  project = var.avn_project_id
  service_name = aiven_pg.tms-demo-pg.service_name

  # default admin user that is automatically created each Aiven service
  username = "avnadmin"

  depends_on = [
    aiven_pg.tms-demo-pg
  ]
}