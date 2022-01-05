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
  name   = "functions/restore.zip"
  bucket = data.google_storage_bucket.bucket.name
  source = "./gcp/cloud_function/restore.zip"
}

# This may fail on the first run, solution is to wait and reapply: https://github.com/terraform-google-modules/terraform-google-scheduled-function/issues/25
resource "google_cloudfunctions_function" "function" {
  name        = "restore"
  description = "restore logs to an Aiven for OpenSearch cluster"
  runtime     = "python39"

  available_memory_mb   = 256
  source_archive_bucket = data.google_storage_bucket.bucket.name
  source_archive_object = google_storage_bucket_object.archive.name
  
  trigger_http          = true
  entry_point           = "restore_logs"

  environment_variables = {
    OS_HOST = "${var.os_host}"
    OS_USER = "${var.os_user}"
    OS_PWD = "${var.os_pass}"
    OS_PORT = var.os_port
  }

}