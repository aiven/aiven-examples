terraform {
  required_providers {
    aiven = {
      source  = "aiven/aiven"
      version = ">= 2.2.1, < 3.0.0"
    }
  }
}

variable "aiven_project_name" {
}
variable "cloud_name" {
}
variable "service_name" {
}

resource "aiven_redis" "redis" {
  project                 = var.aiven_project_name
  cloud_name              = var.cloud_name
  service_name            = var.service_name
  plan                    = "business-1"
  maintenance_window_dow  = "tuesday"
  maintenance_window_time = "12:00:00"
  termination_protection  = false

  redis_user_config {
    ip_filter = ["0.0.0.0/0"]

    redis_maxmemory_policy = "allkeys-random"
    public_access {
      redis = true
    }
  }
}

resource "aiven_service_user" "redis_user" {
  project      = var.aiven_project_name
  service_name = aiven_redis.redis.service_name
  username     = "rd_user"

  lifecycle {
    ignore_changes = [
      redis_acl_categories,
      redis_acl_commands,
      redis_acl_keys,
    ]
  }
}

output "service_uri" {
  value     = aiven_redis.redis.service_uri
  sensitive = true
}
