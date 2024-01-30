resource "aiven_pg" "pg" {
  project      = var.aiven_project
  cloud_name   = var.cloud_name
  plan         = var.pg_plan
  service_name = "cdc-pg"
}

resource "aiven_pg_database" "pgdb" {
  depends_on = [aiven_pg.pg]
  project       = var.aiven_project
  service_name  = "cdc-pg"
  database_name = "middleearth"
}

resource "aiven_kafka" "kafka" {
  project      = var.aiven_project
  cloud_name   = var.cloud_name
  plan         = var.kafka_plan
  service_name = "cdc-kafka"
  kafka_user_config {
    kafka_rest      = true
    kafka_connect   = true
    schema_registry = true
    kafka_version = "3.6"
    kafka {
      auto_create_topics_enable = true
      num_partitions             = 3
      default_replication_factor = 2
      min_insync_replicas        = 2
    }
  }
}

resource "aiven_kafka_connector" "kafka-pg-source" {
  depends_on = [aiven_pg_database.pgdb]
  project        = var.aiven_project
  service_name   = aiven_kafka.kafka.service_name
  connector_name = "kafka-pg-source"

  config = {
    "name"                        = "kafka-pg-source"
    "connector.class"             = "io.debezium.connector.postgresql.PostgresConnector"
    "snapshot.mode"               = "initial"
    "database.hostname"           = sensitive(aiven_pg.pg.service_host)
    "database.port"               = sensitive(aiven_pg.pg.service_port)
    "database.password"           = sensitive(aiven_pg.pg.service_password)
    "database.user"               = sensitive(aiven_pg.pg.service_username)
    "database.dbname"             = "middleearth"
    "database.server.name"        = "middleearth-replicator"
    "database.ssl.mode"           = "require"
    "include.schema.changes"      = true
    "include.query"               = true
    # "plugin.name"                 = "wal2json"
    # tables needs to be specified for pgoutput plugin
    # see details https://docs.aiven.io/docs/products/kafka/kafka-connect/howto/debezium-source-connector-pg#
    "plugin.name"                 = "pgoutput"
    "publication.autocreate.mode" = "filtered"
    "table.include.list"          = "public.population,public.weather"
    "slot.name"                   = "dbz"
    "decimal.handling.mode"       = "double"
    "_aiven.restart.on.failure"   = "true"
    "transforms"                  = "flatten"
    "transforms.flatten.type"     = "org.apache.kafka.connect.transforms.Flatten$Value"
  }
}

resource "aiven_clickhouse" "clickhouse" {
  project      = var.aiven_project
  cloud_name   = var.cloud_name
  plan         = var.clickhouse_plan
  service_name = "cdc-clickhouse"
}

resource "aiven_service_integration" "clickhouse_kafka_source" {
  depends_on = [aiven_kafka_connector.kafka-pg-source]
  project                  = var.aiven_project
  integration_type         = "clickhouse_kafka"
  source_service_name      = aiven_kafka.kafka.service_name
  destination_service_name = aiven_clickhouse.clickhouse.service_name
  clickhouse_kafka_user_config {
    tables {
      name        = "population_cdc"
      group_name  = "clickhouse-ingestion"
      data_format = "JSONEachRow"
      columns {
        name = "before.id"
        type = "UInt64"
      }
      columns {
        name = "before.region"
        type = "UInt64"
      }
      columns {
        name = "before.total"
        type = "UInt64"
      }
      columns {
        name = "after.id"
        type = "UInt64"
      }
      columns {
        name = "after.region"
        type = "UInt64"
      }
      columns {
        name = "after.total"
        type = "UInt64"
      }
      columns {
        name = "op"
        type = "LowCardinality(String)"
      }
      columns {
        name = "ts_ms"
        type = "UInt64"
      }
      columns {
        name = "source.sequence"
        type = "String"
      }
      columns {
        name = "source.lsn"
        type = "UInt64"
      }

      topics {
        name = "middleearth-replicator.public.population"
      }
    }
    tables {
      name        = "weather_cdc"
      group_name  = "clickhouse-ingestion"
      data_format = "JSONEachRow"
      columns {
        name = "before.id"
        type = "UInt64"
      }
      columns {
        name = "before.region"
        type = "UInt64"
      }
      columns {
        name = "before.temperature"
        type = "Float64"
      }
      columns {
        name = "after.id"
        type = "UInt64"
      }
      columns {
        name = "after.region"
        type = "UInt64"
      }
      columns {
        name = "after.temperature"
        type = "Float64"
      }
      columns {
        name = "op"
        type = "LowCardinality(String)"
      }
      columns {
        name = "ts_ms"
        type = "UInt64"
      }
      columns {
        name = "source.sequence"
        type = "String"
      }
      columns {
        name = "source.lsn"
        type = "UInt64"
      }

      topics {
        name = "middleearth-replicator.public.weather"
      }
    }
  }
}
