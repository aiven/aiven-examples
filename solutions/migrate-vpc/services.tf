resource "aiven_project_vpc" "vpc0" {
  project      = var.aiven_project
  cloud_name   = var.cloud_name
  network_cidr = "10.168.90.0/24"

  timeouts {
    create = "5m"
  }
}

resource "aiven_project_vpc" "vpc1" {
  project      = var.aiven_project
  cloud_name   = var.cloud_name
  network_cidr = "10.1.0.0/20"

  timeouts {
    create = "5m"
  }
}

resource "aiven_kafka" "kafka" {
  project      = var.aiven_project
  cloud_name   = var.cloud_name
  plan         = var.kafka_plan
  project_vpc_id = aiven_project_vpc.vpc1.id
  service_name = "kafka-vpc-tf"
  kafka_user_config {
    kafka_rest = "true"
  }
}

resource "aiven_kafka_topic" "source" {
  project      = aiven_kafka.kafka.project
  service_name = aiven_kafka.kafka.service_name
  partitions   = 3
  replication  = 3
  topic_name   = "topic_a"
}

resource "aiven_kafka_topic" "sink" {
  project      = aiven_kafka.kafka.project
  service_name = aiven_kafka.kafka.service_name
  partitions   = 3
  replication  = 3
  topic_name   = "topic_b"
}
