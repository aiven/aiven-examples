terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "4.7.0"
    }
  }
}


data "google_storage_bucket" "bucket" {
  name     = var.gcs_bucket
}

resource "google_storage_bucket_object" "archive" {
  name   = "functions/promote.zip"
  bucket = data.google_storage_bucket.bucket.name
  source = "./gcp/cloud_function/promote.zip"
}

# This may fail on the first run, solution is to wait and reapply: https://github.com/terraform-google-modules/terraform-google-scheduled-function/issues/25
resource "google_cloudfunctions_function" "function" {
  name        = "promote_remote"
  description = "promote read replica Aiven service to Primary in case of failure"
  runtime     = "python39"

  available_memory_mb   = 256
  source_archive_bucket = data.google_storage_bucket.bucket.name
  source_archive_object = google_storage_bucket_object.archive.name
  
  trigger_http          = true
  entry_point           = "promote_remote"

  environment_variables = {
    PROJ = var.project
    INTEGRATION_ID = var.integration_id
    AVN_TOKEN = var.aiven_api_token
  }

}