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
variable "pg_plan"{
    type = string
}
variable "pg_version"{
    type = string
}
variable "pg_shared_memory_buffer_percentage"{
  type = number
}
variable "pg_max_parallel_workers"{
  type = number
}
variable "pg_max_parallel_workers_per_gather"{
  type = number
}
