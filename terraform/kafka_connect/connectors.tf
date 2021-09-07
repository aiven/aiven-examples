locals {
  pg_debezium_name = "pg-import"
  redis_sink_name  = "redis-export"
}

data "aiven_service" "pg" {
  project      = var.aiven_project_name
  service_name = var.source_name

  depends_on = [
    time_sleep.hack_tf012_module_depends_on,
  ]
}

data "aiven_service" "redis" {
  project      = var.aiven_project_name
  service_name = var.sink_name

  depends_on = [
    time_sleep.hack_tf012_module_depends_on,
  ]
}

resource "time_sleep" "hack_tf012_module_depends_on" {
  create_duration = "90s"
}

resource "time_sleep" "wait_for_kafka_connect" {
  # it seems like with current config it takes 4-5m to get kafka + connect up and running
  # and be ready to setup connectors
  create_duration  = "300s"
  destroy_duration = "30s"

  depends_on = [
    aiven_service.kafka_connect,
  ]
}

resource "aiven_kafka_connector" "kafka-pg-debezium-source-connector" {
  project        = var.aiven_project_name
  service_name   = local.kafka_connect_service_name
  connector_name = local.pg_debezium_name

  config = {
    "name"                        = local.pg_debezium_name
    "connector.class"             = "io.debezium.connector.postgresql.PostgresConnector"
    "database.server.name"        = "avn_pg_db"
    "database.hostname"           = data.aiven_service.pg.service_host
    "database.port"               = data.aiven_service.pg.service_port
    "database.user"               = data.aiven_service.pg.service_username
    "database.password"           = data.aiven_service.pg.service_password
    "database.dbname"             = var.source_db
    "database.sslmode"            = "require" #data.aiven_service.pg.pg[0].sslmode
    "plugin.name"                 = "pgoutput"
    "publication.name"            = "dbz_publication"
    "publication.autocreate.mode" = "ALL_TABLES"
    "_aiven.restart.on.failure"   = "true"
  }

  depends_on = [
    time_sleep.wait_for_kafka_connect,
  ]
}

resource "aiven_kafka_connector" "kafka-redis-sink-connector" {
  project        = var.aiven_project_name
  service_name   = local.kafka_connect_service_name
  connector_name = local.redis_sink_name

  config = {
    "name"                                            = local.redis_sink_name
    "connector.class"                                 = "com.datamountaineer.streamreactor.connect.redis.sink.RedisSinkConnector"
    "topics"                                          = "translations" # TODO look it up from topics.tf somehow
    "errors.deadletterqueue.topic.name"               = "dead_translations"
    "errors.deadletterqueue.topic.replication.factor" = "2"
    "connect.redis.host"                              = data.aiven_service.redis.service_host
    "connect.redis.port"                              = data.aiven_service.redis.service_port
    "connect.redis.password"                          = data.aiven_service.redis.service_password
    "connect.redis.ssl.enabled"                       = "true"
    "connect.redis.kcql"                              = "INSERT INTO TRANS- SELECT * from translations PK key"
    "connect.redis.error.policy"                      = "RETRY"
    "connect.redis.retry.interval"                    = "200"
    "connect.redis.max.retries"                       = "10"
    "connect.progress.enabled"                        = "true"
    "_aiven.restart.on.failure"                       = "true"
  }

  depends_on = [
    time_sleep.wait_for_kafka_connect,
  ]
}
