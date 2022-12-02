resource "aiven_kafka" "kafka" {
  project      = var.aiven_project
  cloud_name   = var.cloud_name
  plan         = var.kafka_plan
  service_name = "kafka-streams"
  kafka_user_config {
    kafka_rest = true
    schema_registry = true
  }
}

resource "aiven_kafka_topic" "song-feed" {
  project      = aiven_kafka.kafka.project
  service_name = aiven_kafka.kafka.service_name
  partitions   = 3
  replication  = 3
  topic_name   = "song-feed"
}

resource "aiven_kafka_topic" "play-events" {
  project      = aiven_kafka.kafka.project
  service_name = aiven_kafka.kafka.service_name
  partitions   = 3
  replication  = 3
  topic_name   = "play-events"
}
