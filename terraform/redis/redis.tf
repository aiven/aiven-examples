variable "aiven_project_name" {
}
variable "cloud_name" {
}
variable "service_name" {
}

resource "aiven_service" "redis" {
  service_type            = "redis"
  project                 = var.aiven_project_name
  cloud_name              = var.cloud_name
  service_name            = var.service_name
  plan                    = "business-1"
  maintenance_window_dow  = "tuesday"
  maintenance_window_time = "12:00:00"
  termination_protection  = false

  redis_user_config {
    ip_filter = ["0.0.0.0/0"]
  }
}

resource "aiven_service_user" "redis_user" {
  project      = var.aiven_project_name
  service_name = aiven_service.redis.service_name
  username     = "rd_user"
}

output "service_uri" {
  value     = aiven_service.redis.service_uri
  sensitive = true
}
