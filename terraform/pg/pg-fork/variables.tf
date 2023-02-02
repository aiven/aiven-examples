variable "aiven_api_token" {}
variable "avn_project" {}
variable "cloud_name" {
   type    =  string
   default =  "google-us-west2"
  }
variable "pg_plan" {
   type    =  string
   default =  "business-64"
  }
variable "service_name" {
   type    =  string
   default =  "pg-forked"
  }
variable "pg_service_to_fork_from" {}
