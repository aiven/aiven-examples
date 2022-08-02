terraform {
  required_providers {
    aiven = {
      source  = "aiven/aiven"
      version = "3.4.0"
    }
  }
}

provider "aiven" {
  api_token = var.aiven_api_token
}

# Use the following data and resource object
#  to create a new project if required

# data "aiven_account" "acct" {
#   name = var.account
# }

# resource "aiven_project" "prj" {
#   project = var.project
#   account_id = data.aiven_account.acct.account_id
#   billing_group = data.aiven_account.acct.primary_billing_group_id
# }

resource "aiven_project_vpc" "project_vpc" {
  project      = var.project
  cloud_name   = var.cloud_name
  network_cidr = var.vpc_cidr_range

  timeouts {
    create = "5m"
  }

}

resource "aiven_gcp_vpc_peering_connection" "gcp_peer" {
  vpc_id = aiven_project_vpc.project_vpc.id
  # this will be your Google cloud project ID and network ID
  gcp_project_id = var.external_account_id
  peer_vpc       = var.external_vpc_id
}


# Example of creating read only user
# resource "aiven_project_user" "mytestuser" {
#   project = aiven_project.prj.project
#   email = var.email
#   member_type = "read_only"
# }

module "stack" {
  source                     = "./modules/stack"
  prefix                     = var.prefix
  project                    = var.project
  cloud_name                 = var.cloud_name
  kafka_plan_size            = var.kafka_plan_size
  os_log_analytics_plan      = var.os_log_analytics_plan
  os_log_internal_plan       = var.os_log_internal_plan
  opensearch_logs_total_disk = var.os_disk_space
  ip_filter                  = ["0.0.0.0"]
  vpc_id                     = aiven_project_vpc.project_vpc.id
}

module "metrics-and-logs" {
  source = "./modules/metrics-logs"
  svcs = [
    module.stack.kafka_service_name,
    module.stack.os_la_service_name,
    module.stack.os_logs_1_service_name,
    module.stack.os_logs_2_service_name,
    module.stack.os_logs_3_service_name,
    module.stack.os_logs_4_service_name
  ]
  prefix        = var.prefix
  project       = var.project
  cloud_name    = var.cloud_name
  vpc_id        = aiven_project_vpc.project_vpc.id
  prom_name     = var.prom_name
  prom_username = var.prom_username
  prom_password = var.prom_password
}