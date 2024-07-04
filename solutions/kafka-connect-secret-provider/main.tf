data "aws_secretsmanager_secret" "secret" {
  name = var.secret_name
}

data "aws_secretsmanager_secret_version" "secret-version" {
  secret_id = data.aws_secretsmanager_secret.secret.id
}

locals {
  db_password = jsondecode(data.aws_secretsmanager_secret_version.secret-version.secret_string)[var.secret_key]
}

resource "aiven_kafka" "kafka" {
  project      = var.aiven_project
  cloud_name   = var.cloud_name
  plan         = var.kafka_plan
  service_name = "${var.service_prefix}kafka"
  kafka_user_config {
    kafka_rest = true
    kafka_authentication_methods {
      sasl = true
    }
    kafka {
      auto_create_topics_enable = true
    }
  }
}

resource "aiven_pg" "postgres" {
  project      = var.aiven_project
  cloud_name   = var.cloud_name
  plan         = var.postgres_plan
  service_name = "${var.service_prefix}postgres"

  pg_user_config {
    admin_username = "dbuser"
    admin_password = local.db_password
  }

  provisioner "local-exec" {
    command = "psql -U ${self.service_username} -h ${self.service_host} -p ${self.service_port} -d defaultdb -f ${path.module}/publication.sql"
    environment = {
      PGPASSWORD = self.service_password
      PGSSLMODE  = "require"
    }
  }
}

resource "aiven_kafka_connect" "kafka_connect" {
  project      = var.aiven_project
  cloud_name   = var.cloud_name
  plan         = var.kafka_connect_plan
  service_name = "${var.service_prefix}kafka-connect"

  kafka_connect_user_config {
    kafka_connect {
      consumer_isolation_level = "read_committed"
    }

    public_access {
      kafka_connect = true
    }

    secret_providers {
      name = "aws"
      aws {
        auth_method = "credentials"
        region      = var.aws_region
        access_key  = local.aws_access_key
        secret_key  = local.aws_secret_access_key
      }
    }
  }
}

resource "aiven_service_integration" "kafka_connect_integration" {
  project                  = var.aiven_project
  integration_type         = "kafka_connect"
  source_service_name      = aiven_kafka.kafka.service_name
  destination_service_name = aiven_kafka_connect.kafka_connect.service_name
}

resource "aiven_kafka_connector" "kafka-pg-debezium-source-connector" {
  depends_on     = [aiven_service_integration.kafka_connect_integration]
  project        = var.aiven_project
  service_name   = aiven_kafka_connect.kafka_connect.service_name
  connector_name = "debezium-connector"

  config = {
    "name"                 = "debezium-connector"
    "connector.class"      = "io.debezium.connector.postgresql.PostgresConnector"
    "database.server.name" = "avn_pg_db"
    "database.hostname"    = aiven_pg.postgres.service_host
    "database.port"        = aiven_pg.postgres.service_port
    "database.user"        = aiven_pg.postgres.service_username
    "topic.prefix"         = "topic"

    # Reference to the secret resolved by the secret-provider
    "database.password" = "$${aws:${var.secret_name}:${var.secret_key}}"

    "database.dbname"             = "defaultdb"
    "database.sslmode"            = "require"
    "plugin.name"                 = "pgoutput"
    "publication.name"            = "dbz_publication"
    "publication.autocreate.mode" = "all_tables"
    "_aiven.restart.on.failure"   = "true"
  }
}

data "aiven_kafka" "kafka" {
  project      = var.aiven_project
  service_name = aiven_kafka.kafka.service_name
}

output "kafka_rest_uri" {
  value     = data.aiven_kafka.kafka.kafka[0].rest_uri
  sensitive = true
}

output "kafka_rest_username" {
  value     = data.aiven_kafka.kafka.service_username
  sensitive = true
}

output "kafka_rest_password" {
  value     = data.aiven_kafka.kafka.service_password
  sensitive = true
}

output "pg_uri" {
  value     = aiven_pg.postgres.service_uri
  sensitive = true
}
