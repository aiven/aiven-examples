resource "aiven_opensearch" "os" {
  project      = var.aiven_project_name
  cloud_name   = var.cloud_name
  plan         = var.os_plan
  service_name = "os-demo"
}

resource "aiven_kafka" "kafka" {
  project      = var.aiven_project_name
  cloud_name   = var.cloud_name
  plan         = var.kafka_plan
  service_name = "os-kafka"
  kafka_user_config {
    kafka_rest      = "true"
  }
}

resource "aiven_kafka_topic" "source" {
  project      = var.aiven_project_name
  service_name = aiven_kafka.kafka.service_name
  partitions   = 2
  replication  = 3
  topic_name   = "products"
}