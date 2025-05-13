variable "aiven_api_token" {
  description = "Aiven API token"
  type        = string
}
variable "aiven_project_name" {
  type = string
}
variable "service_prefix" {
  type = string
}
variable "cloud_name_primary" {
  type = string
}
variable "cloud_name_dr"{
  type = string
}
variable "mysql_plan"{
  type = string
}
variable "mysql_dr_plan"{
  type = string
}
variable "mysql_version"{
    type = string
}
variable "backup_regions"{
  type = string
}