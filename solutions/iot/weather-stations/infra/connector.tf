data "aiven_service_component" "schema_registry" {
  project = var.avn_project_id
  service_name = aiven_kafka.tms-demo-kafka.service_name
  component = "schema_registry"
  route = "dynamic"
}

data "aiven_service_component" "tms_pg" {
    project = var.avn_project_id
    service_name = aiven_pg.tms-demo-pg.service_name
    component = "pg"
    route = "dynamic"
}

locals {
  schema_registry_uri = "https://${data.aiven_service_user.kafka_admin.username}:${data.aiven_service_user.kafka_admin.password}@${data.aiven_service_component.schema_registry.host}:${data.aiven_service_component.schema_registry.port}"
}

resource "aiven_kafka_connector" "kafka-pg-cdc-stations" {
  project = var.avn_project_id
  service_name = aiven_kafka_connect.tms-demo-kafka-connect1.service_name
  connector_name = "kafka-pg-cdc-stations"

  config = {  
    "_aiven.restart.on.failure": "true",
    "key.converter" : "org.apache.kafka.connect.storage.StringConverter",
    "key.converter.schemas.enable": "false",
    "value.converter": "io.confluent.connect.avro.AvroConverter",
    "value.converter.schema.registry.url": local.schema_registry_uri,
    "value.converter.basic.auth.credentials.source": "URL",
    "value.converter.schemas.enable": "true",
    "connector.class": "io.debezium.connector.postgresql.PostgresConnector",    
    "name": "kafka-pg-cdc-stations",
    "slot.name": "weatherstations",
    "database.hostname": data.aiven_service_component.tms_pg.host,
    "database.port": data.aiven_service_component.tms_pg.port,
    "database.user": data.aiven_service_user.pg_admin.username,
    "database.password": data.aiven_service_user.pg_admin.password,
    "database.dbname": "defaultdb",
    "database.server.name": "tms-demo-pg",
    "table.whitelist": "public.weather_stations",
    "plugin.name": "wal2json",
    "database.sslmode": "require",
    "transforms": "unwrap,insertKey,extractKey",
    "transforms.unwrap.type":"io.debezium.transforms.UnwrapFromEnvelope",
    "transforms.unwrap.drop.tombstones":"false",
    "transforms.insertKey.type":"org.apache.kafka.connect.transforms.ValueToKey",
    "transforms.insertKey.fields":"roadstationid",
    "transforms.extractKey.type":"org.apache.kafka.connect.transforms.ExtractField$Key",
    "transforms.extractKey.field":"roadstationid",
    "include.schema.changes": "false"
  }
}

resource "aiven_kafka_connector" "kafka-pg-cdc-stations-2" {
  project = var.avn_project_id
  service_name = aiven_kafka_connect.tms-demo-kafka-connect1.service_name
  connector_name = "kafka-pg-cdc-stations-2"

  config = {  
    "_aiven.restart.on.failure": "true",
    "key.converter" : "io.confluent.connect.avro.AvroConverter",
    "key.converter.schema.registry.url": local.schema_registry_uri,
    "key.converter.basic.auth.credentials.source": "URL",
    "key.converter.schemas.enable": "true",
    "value.converter": "io.confluent.connect.avro.AvroConverter",
    "value.converter.schema.registry.url": local.schema_registry_uri,
    "value.converter.basic.auth.credentials.source": "URL",
    "value.converter.schemas.enable": "true",
    "connector.class": "io.debezium.connector.postgresql.PostgresConnector",    
    "name": "kafka-pg-cdc-stations-2",
    "slot.name": "weatherstations2",
    "database.hostname": data.aiven_service_component.tms_pg.host,
    "database.port": data.aiven_service_component.tms_pg.port,
    "database.user": data.aiven_service_user.pg_admin.username,
    "database.password": data.aiven_service_user.pg_admin.password,
    "database.dbname": "defaultdb",
    "database.server.name": "tms-demo-pg",
    "table.whitelist": "public.weather_stations_2",
    "plugin.name": "wal2json",
    "database.sslmode": "require",
    "transforms":"route",
    "transforms.route.regex": "tms-demo-pg.public.weather_stations_2",
    "transforms.route.replacement": "weather_stations",
    "transforms.route.type": "org.apache.kafka.connect.transforms.RegexRouter",
    "include.schema.changes": "false"
  }
}

resource "aiven_kafka_connector" "bq-sink" {
  count = "${var.bq_project != "" ? 1 : 0}"
  project = var.avn_project_id
  service_name = aiven_kafka_connect.tms-demo-kafka-connect1.service_name
  connector_name = "bq-sink"
  config = {  
    "_aiven.restart.on.failure": "true",
    "name": "bq-sink",
    "connector.class": "com.wepay.kafka.connect.bigquery.BigQuerySinkConnector",
    "key.converter" : "io.confluent.connect.avro.AvroConverter",
    "key.converter.schema.registry.url": local.schema_registry_uri,
    "key.converter.basic.auth.credentials.source": "URL",
    "key.converter.schemas.enable": "true",
    "value.converter": "io.confluent.connect.avro.AvroConverter",
    "value.converter.schema.registry.url": local.schema_registry_uri,
    "value.converter.basic.auth.credentials.source": "URL",
    "value.converter.schemas.enable": "true",
    "topics": "weather_stations",    
    "project": var.bq_project,
    "keySource": "JSON",
    "keyfile": var.bq_key,
    "defaultDataset": "weather_stations",    
    "kafkaKeyFieldName": "kafkakey",
    "kafkaDataFieldName": "kafkavalue",
    "allowNewBigQueryFields": "true",
    "allowBigQueryRequiredFieldRelaxation": "true",
    "allowSchemaUnionization": "true",
    "deleteEnabled": "true",
    "mergeIntervalMs": "5000",
    "transforms": "unwrap,ReplaceField",
    "transforms.unwrap.type": "io.debezium.transforms.UnwrapFromEnvelope",
    "transforms.unwrap.drop.tombstones": "false",
    "transforms.unwrap.delete.handling.mode": "none",
    "transforms.ReplaceField.type": "org.apache.kafka.connect.transforms.ReplaceField$Value",
    "transforms.ReplaceField.blacklist": "roadstationid"
  } 
}

resource "aiven_kafka_connector" "kafka-pg-cdc-sensors" {
  project = var.avn_project_id
  service_name = aiven_kafka_connect.tms-demo-kafka-connect1.service_name
  connector_name = "kafka-pg-cdc-sensors"

  config = {  
    "_aiven.restart.on.failure": "true",
    "key.converter" : "org.apache.kafka.connect.storage.StringConverter",
    "key.converter.schemas.enable": "false",
    "value.converter": "io.confluent.connect.avro.AvroConverter",
    "value.converter.schema.registry.url": local.schema_registry_uri,
    "value.converter.basic.auth.credentials.source": "URL",
    "value.converter.schemas.enable": "true",
    "connector.class": "io.debezium.connector.postgresql.PostgresConnector",    
    "name": "kafka-pg-cdc-sensors",
    "slot.name": "weathersensors",
    "database.hostname": data.aiven_service_component.tms_pg.host,
    "database.port": data.aiven_service_component.tms_pg.port,
    "database.user": data.aiven_service_user.pg_admin.username,
    "database.password": data.aiven_service_user.pg_admin.password,
    "database.dbname": "defaultdb",
    "database.server.name": "tms-demo-pg",
    "table.whitelist": "public.weather_sensors",
    "plugin.name": "wal2json",
    "database.sslmode": "require",
    "transforms": "unwrap,insertKey,extractKey",
    "transforms.unwrap.type":"io.debezium.transforms.UnwrapFromEnvelope",
    "transforms.unwrap.drop.tombstones":"false",
    "transforms.insertKey.type":"org.apache.kafka.connect.transforms.ValueToKey",
    "transforms.insertKey.fields":"sensorid",
    "transforms.extractKey.type":"org.apache.kafka.connect.transforms.ExtractField$Key",
    "transforms.extractKey.field":"sensorid",
    "include.schema.changes": "false"
  }  
}