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
 
resource "aiven_pg" "pg_remote" {
 project                 = data.aiven_project.sample.project
 cloud_name              = var.remote_cloud
 service_name            = "pg-remote"
 plan                    = "startup-4"
 maintenance_window_dow  = "saturday"
 maintenance_window_time = "07:45:00"
 termination_protection  = false
 
 service_integrations {
   integration_type    = "read_replica"
   source_service_name = aiven_pg.pg-jakarta.service_name
 }
 
 pg_user_config {
   service_to_fork_from = aiven_pg.pg-jakarta.service_name
 }
 
 depends_on = [
   aiven_pg.pg-jakarta,
 ]
}

resource "aiven_service_integration" "pg_readreplica" {
 project = data.aiven_project.sample.project
 integration_type = "read_replica"
 source_service_name = aiven_pg.pg-jakarta.service_name
 destination_service_name = aiven_pg.pg-aws.service_name
}
 

resource "aiven_grafana" "grafana" {
 project      = data.aiven_project.sample.project
 cloud_name   = "google-asia-southeast1"
 plan         = "startup-4"
 service_name = "grafana-jakarta"
 grafana_user_config {
   ip_filter = ["0.0.0.0/0"]
 }
}

module "gcp" {
  source = "./gcp"

  project = var.project
  aiven_api_token = var.aiven_api_token
  integration_id = aiven_service_integration.pg_readreplica.id
  gcs_bucket = var.gcs_bucket

  depends_on = [
    aiven_opensearch.es
  ]
}