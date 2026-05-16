data "aws_secretsmanager_secret_version" "external_kafka" {
  secret_id = var.external_kafka_credentials_secret_id
}

locals {
  example_aiven_kafka_project = coalesce(var.example_aiven_source_kafka_project_name, var.aiven_project_name)
  create_aiven_kafka_source_example = (
    var.example_aiven_source_kafka_service_name != null &&
    trimspace(var.example_aiven_source_kafka_service_name) != ""
  )

  external_kafka_creds = jsondecode(data.aws_secretsmanager_secret_version.external_kafka.secret_string)
  sasl_username = trimspace(coalesce(
    try(local.external_kafka_creds["sasl_plain_username"], null),
    try(local.external_kafka_creds["username"], null),
    "",
  ))
  sasl_password = trimspace(coalesce(
    try(local.external_kafka_creds["sasl_plain_password"], null),
    try(local.external_kafka_creds["password"], null),
    "",
  ))
  ssl_ca_cert = var.external_kafka_ssl_ca_cert != null ? var.external_kafka_ssl_ca_cert : try(local.external_kafka_creds["ssl_ca_cert"], null)
}

resource "aiven_service_integration_endpoint" "external_kafka" {
  project         = var.aiven_project_name
  endpoint_name   = var.external_kafka_endpoint_name
  endpoint_type   = "external_kafka"

  external_kafka_user_config {
    bootstrap_servers                     = var.external_kafka_bootstrap_servers
    security_protocol                     = "SASL_SSL"
    sasl_mechanism                        = "SCRAM-SHA-256"
    sasl_plain_username                   = local.sasl_username
    sasl_plain_password                   = local.sasl_password
    ssl_endpoint_identification_algorithm = "https"
    ssl_ca_cert                           = local.ssl_ca_cert
  }

  lifecycle {
    precondition {
      condition     = local.sasl_username != ""
      error_message = "The Secrets Manager JSON must set sasl_plain_username or username."
    }
    precondition {
      condition     = local.sasl_password != ""
      error_message = "The Secrets Manager JSON must set sasl_plain_password or password."
    }
  }
}

data "aiven_kafka" "example_source" {
  count = local.create_aiven_kafka_source_example ? 1 : 0

  project      = local.example_aiven_kafka_project
  service_name = var.example_aiven_source_kafka_service_name
}

data "aiven_project" "example_kafka_project" {
  count = local.create_aiven_kafka_source_example ? 1 : 0

  project = local.example_aiven_kafka_project
}

resource "aiven_service_integration_endpoint" "aiven_kafka_source_example" {
  count = local.create_aiven_kafka_source_example ? 1 : 0

  project         = var.aiven_project_name
  endpoint_name   = var.example_aiven_kafka_source_endpoint_name
  endpoint_type   = "external_kafka"

  external_kafka_user_config {
    bootstrap_servers                     = data.aiven_kafka.example_source[0].service_uri
    security_protocol                     = "SASL_SSL"
    sasl_mechanism                        = "SCRAM-SHA-256"
    sasl_plain_username                   = data.aiven_kafka.example_source[0].username
    sasl_plain_password                   = data.aiven_kafka.example_source[0].password
    ssl_ca_cert                           = data.aiven_project.example_kafka_project[0].ca_cert
    ssl_endpoint_identification_algorithm = "https"
  }
}
