terraform {
  required_providers {
    aiven = {
      source  = "aiven/aiven"
      version = "2.5.0"
    }
  }
}

provider "google" {
  project = var.google_project
  region  = "europe-west3"
}

provider "aiven" {
  api_token = var.aiven_api_token
}

data "aiven_project" "proj" {
  project = var.project
}

resource "aiven_pg" "pg-primary" {
 project      = var.project
 cloud_name   = var.primary_cloud
 plan         = "startup-4"
 service_name = "pg-jakarta"
 pg_user_config {
   pg_version = 14
   public_access {
     pg         = true
   }
 }
 
}
# remote replica
resource "aiven_pg" "pg_remote" {
 project                 = var.project
 cloud_name              = var.remote_cloud
 service_name            = "pg-remote"
 plan                    = "startup-4"
 maintenance_window_dow  = "saturday"
 maintenance_window_time = "07:45:00"
 termination_protection  = false
 
 service_integrations {
   integration_type    = "read_replica"
   source_service_name = aiven_pg.pg-primary.service_name
 }
 depends_on = [
   aiven_pg.pg-primary,
 ]
}
# service integration with primary
resource "aiven_service_integration" "pg_readreplica" {
 project = var.project
 integration_type = "read_replica"
 source_service_name =  aiven_pg.pg-primary.service_name
 destination_service_name =  aiven_pg.pg_remote.service_name
}
 
# grafana service
resource "aiven_grafana" "grafana" {
 project      = var.project
 cloud_name   = "google-asia-southeast1"
 plan         = "startup-4"
 service_name = "grafana-jakarta"
 grafana_user_config {
   ip_filter = ["0.0.0.0/0"]
 }
}
# # gcp module 
module "gcp" {
  source = "./gcp"

  project = var.project
  aiven_api_token = var.aiven_api_token
  integration_id = aiven_service_integration.pg_readreplica.id
  gcs_bucket = var.gcs_bucket

  depends_on = [
    aiven_service_integration.pg_readreplica
  ]
}
# m3 service
resource "aiven_m3db" "m3-jakarta" {
    project = var.project
    cloud_name = "google-asia-southeast1"
    plan = "business-8"
    service_name = "m3-jakarta"

    m3db_user_config {
      m3db_version = 1.2
    }
}

# service integration from M3 to Grafana
resource "aiven_service_integration" "grafana-jakarta" {
  project                  = var.project
  integration_type         = "dashboard"
  source_service_name      = aiven_grafana.grafana.service_name
  destination_service_name = aiven_m3db.m3-jakarta.service_name
}
# service integration from primary to m3 
resource "aiven_service_integration" "int-m3db-pg-primary" {
  project                  = var.project
  integration_type         = "metrics"
  source_service_name      =  aiven_pg.pg-primary.service_name
  destination_service_name = aiven_m3db.m3-jakarta.service_name
}
# service integration from replica to m3
resource "aiven_service_integration" "int-m3db-pg-replica" {
  project                  = var.project
  integration_type         = "metrics"
  source_service_name      =  aiven_pg.pg_remote.service_name
  destination_service_name = aiven_m3db.m3-jakarta.service_name
}