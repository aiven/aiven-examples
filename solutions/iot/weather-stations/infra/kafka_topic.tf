# Kafka topics

resource "aiven_kafka_topic" "observations-weather-raw" {
  project = var.avn_project_id
  service_name = aiven_kafka.tms-demo-kafka.service_name
  topic_name = "observations.weather.raw"
  partitions = 20
  replication = 2
  config {
    retention_ms = 259200000
    cleanup_policy = "delete"
    min_insync_replicas = 1
  }
  depends_on = [
    aiven_kafka.tms-demo-kafka
  ]

}

resource "aiven_kafka_topic" "observations-weather-processed" {
  project = var.avn_project_id
  service_name = aiven_kafka.tms-demo-kafka.service_name
  topic_name = "observations.weather.processed"
  partitions = 20
  replication = 2
  config {
    retention_ms = 259200000
    cleanup_policy = "delete"
    min_insync_replicas = 1
  }
  depends_on = [
    aiven_kafka.tms-demo-kafka
  ]
}

resource "aiven_kafka_topic" "observations-weather-multivariate" {
  project = var.avn_project_id
  service_name = aiven_kafka.tms-demo-kafka.service_name
  topic_name = "observations.weather.multivariate"
  partitions = 20
  replication = 2
  config {
    retention_ms = 259200000
    cleanup_policy = "delete"
    min_insync_replicas = 1
  }
  depends_on = [
    aiven_kafka.tms-demo-kafka
  ]
}

resource "aiven_kafka_topic" "observations-weather-municipality" {
  project = var.avn_project_id
  service_name = aiven_kafka.tms-demo-kafka.service_name
  topic_name = "observations.weather.municipality"
  partitions = 20
  replication = 2
  config {
    retention_ms = 1814400000
    cleanup_policy = "delete"
    min_insync_replicas = 1
  }
  depends_on = [
    aiven_kafka.tms-demo-kafka
  ]
}

resource "aiven_kafka_topic" "observations-weather-avg-air-temperature" {
  project = var.avn_project_id
  service_name = aiven_kafka.tms-demo-kafka.service_name
  topic_name = "observations.weather.avg-air-temperature"
  partitions = 20
  replication = 2
  config {
    retention_ms = 1814400000
    cleanup_policy = "delete"
    min_insync_replicas = 1
  }
  depends_on = [
    aiven_kafka.tms-demo-kafka
  ]
}

resource "aiven_kafka_topic" "stations-weather" {
  project = var.avn_project_id
  service_name = aiven_kafka.tms-demo-kafka.service_name
  topic_name = "tms-demo-pg.public.weather_stations"
  partitions = 20
  replication = 2
  config {
    cleanup_policy = "compact"
    min_insync_replicas = 1
  }
  depends_on = [
    aiven_kafka.tms-demo-kafka
  ]
}

resource "aiven_kafka_topic" "stations-weather-2" {
  project = var.avn_project_id
  service_name = aiven_kafka.tms-demo-kafka.service_name
  topic_name = "weather_stations"
  partitions = 20
  replication = 2
  config {
    cleanup_policy = "compact"
    min_insync_replicas = 1
  }
  depends_on = [
    aiven_kafka.tms-demo-kafka
  ]
}

resource "aiven_kafka_topic" "sensors-weather" {
  project = var.avn_project_id
  service_name = aiven_kafka.tms-demo-kafka.service_name
  topic_name = "tms-demo-pg.public.weather_sensors"
  partitions = 20
  replication = 2
  config {
    cleanup_policy = "compact"
    min_insync_replicas = 1
  }
  depends_on = [
    aiven_kafka.tms-demo-kafka
  ]
}

