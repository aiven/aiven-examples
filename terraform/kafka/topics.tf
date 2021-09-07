variable "topic_names" {
  type = set(string)
  default = [
    "sample_topic",
    "translations",
  ]
}

resource "aiven_kafka_topic" "topic" {
  for_each     = toset(var.topic_names)
  project      = var.aiven_project_name
  service_name = aiven_service.kafka.service_name
  topic_name   = each.value
  replication  = 2
  partitions   = 2
  #partitions   = -1
  #log_retention_bytes = var.log_retention_bytes

  depends_on = [
    aiven_service.kafka,
  ]
}

output "all_topics" {
  value = aiven_kafka_topic.topic
}

resource "aiven_kafka_schema_configuration" "kafka_schema_config" {
  project             = var.aiven_project_name
  service_name        = aiven_service.kafka.service_name
  compatibility_level = "BACKWARD"

  depends_on = [
    aiven_service.kafka,
  ]
}

resource "aiven_kafka_schema" "kafka-schema-translations" {
  project      = var.aiven_project_name
  service_name = aiven_service.kafka.service_name
  subject_name = "translations-value"

  schema = file("${path.module}/translations_schema.avsc")

  depends_on = [
    aiven_service.kafka,
  ]
}