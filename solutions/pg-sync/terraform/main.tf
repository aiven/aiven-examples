resource "aiven_kafka" "kafka" {
  project = var.aiven_project_name
  cloud_name = var.cloud_name_primary
  plan = var.kafka_plan
  service_name = "${var.service_prefix}-kafka"
  maintenance_window_dow = "monday"
  maintenance_window_time = "10:00:00"
  kafka_user_config {
    kafka_connect = true
    kafka_rest = true
    kafka_version = "3.0"
    kafka {
      group_min_session_timeout_ms = 5000
      group_max_session_timeout_ms = 300000
      log_retention_bytes = 1000000000
      auto_create_topics_enable = true
    }
  }
}

resource "aiven_kafka_connect" "kafka-connect" {
  project = var.aiven_project_name
  cloud_name = var.cloud_name_primary
  plan = "startup-4"
  service_name = "${var.service_prefix}-kafka-connect"
  maintenance_window_dow = "monday"
  maintenance_window_time = "10:00:00"

  kafka_connect_user_config {
    kafka_connect {
      consumer_isolation_level = "read_committed"
    }

    public_access {
      kafka_connect = true
    }
  }
}

resource "aiven_pg" "source-pg" {
  project = var.aiven_project_name
  cloud_name = var.cloud_name_primary
  plan = "startup-4"
  service_name = "${var.service_prefix}-source-pg"
  maintenance_window_dow = "monday"
  maintenance_window_time = "10:00:00"

  pg_user_config {
    pg_version = 14

    public_access {
      pg = true
      prometheus = false
    }
  }
}

resource "aiven_pg" "sink-pg" {
  project = var.aiven_project_name
  cloud_name = var.cloud_name_primary
  plan = "startup-4"
  service_name = "${var.service_prefix}-sink-pg"
  maintenance_window_dow = "monday"
  maintenance_window_time = "10:00:00"

  pg_user_config {
    pg_version = 14

    public_access {
      pg = true
      prometheus = false
    }
  }
}

resource "aiven_service_integration" "dbz-pg" {
  project = var.aiven_project_name
  integration_type = "kafka_connect"
  source_service_name = aiven_kafka.kafka.service_name
  destination_service_name = aiven_kafka_connect.kafka-connect.service_name
}

resource "time_sleep" "wait_60_seconds" {
  depends_on = [
    aiven_pg.source-pg,
    aiven_kafka_connect.kafka-connect,
    aiven_service_integration.dbz-pg
  ]
  create_duration = "60s"
}

resource "aiven_kafka_connector" "cdc-kc-connector" {
  depends_on = [
    time_sleep.wait_60_seconds,
  ]
  project = var.aiven_project_name
  service_name = aiven_kafka_connect.kafka-connect.service_name
  connector_name = "kafka-pg-source"

  config = {
    "name" = "kafka-pg-source"
    "connector.class" = "io.debezium.connector.postgresql.PostgresConnector",
    "snapshot.mode" = "initial"
    "database.hostname": aiven_pg.source-pg.service_host
    "database.port": aiven_pg.source-pg.service_port
    "database.password": aiven_pg.source-pg.service_password
    "database.user": aiven_pg.source-pg.service_username
    "database.dbname" = "defaultdb"
    "database.server.name" = "replicator"
    "database.ssl.mode" = "require"
    "include.schema.changes" = true
    "include.query" = true
    "table.include.list" = "public.all_datatypes"
    "plugin.name" = "wal2json"
    "decimal.handling.mode" = "double"
    "_aiven.restart.on.failure" = "true"
  }
}


