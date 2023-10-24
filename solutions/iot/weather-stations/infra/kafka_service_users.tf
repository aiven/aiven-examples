data "aiven_service_user" "kafka_admin" {
  project = var.avn_project_id
  service_name = aiven_kafka.tms-demo-kafka.service_name

  # default admin user that is automatically created each Aiven service
  username = "avnadmin"

  depends_on = [
    aiven_kafka.tms-demo-kafka
  ]
}

resource "aiven_service_user" "tms-ingest-user" {
  project = var.avn_project_id
  service_name = aiven_kafka.tms-demo-kafka.service_name

  username = "tms-ingest-user"

  depends_on = [
    aiven_kafka.tms-demo-kafka
  ]
}

resource "aiven_service_user" "tms-processing-user" {
  project = var.avn_project_id
  service_name = aiven_kafka.tms-demo-kafka.service_name

  username = "tms-processing-user"

  depends_on = [
    aiven_kafka.tms-demo-kafka
  ]
}

resource "aiven_service_user" "tms-sink-user" {
  project = var.avn_project_id
  service_name = aiven_kafka.tms-demo-kafka.service_name

  username = "tms-sink-user"

  depends_on = [
    aiven_kafka.tms-demo-kafka
  ]
}

resource "aiven_kafka_acl" "tms-ingest-acl" {
  project = var.avn_project_id
  service_name = aiven_kafka.tms-demo-kafka.service_name
  permission = "write"
  username = aiven_service_user.tms-ingest-user.username
  topic = aiven_kafka_topic.observations-weather-raw.topic_name
  depends_on = [
    aiven_kafka.tms-demo-kafka
  ]
}

# read-write access for Kafka Streams topologies
resource "aiven_kafka_acl" "tms-processing-acl" {
  project = var.avn_project_id
  service_name = aiven_kafka.tms-demo-kafka.service_name
  permission = "readwrite"
  username = aiven_service_user.tms-processing-user.username
  topic = "observations.*"
  depends_on = [
    aiven_kafka.tms-demo-kafka
  ]
}

# read access to PostgeSQL CDC topics
resource "aiven_kafka_acl" "tms-processing-read-acl" {
  project = var.avn_project_id
  service_name = aiven_kafka.tms-demo-kafka.service_name
  permission = "read"
  username = aiven_service_user.tms-processing-user.username
  topic = "tms-demo-pg.public.*"
  depends_on = [
    aiven_kafka.tms-demo-kafka
  ]
}

# adming access for intermediate Kafka Streams topics (changelog)
resource "aiven_kafka_acl" "tms-processing-admin-acl" {
  project = var.avn_project_id
  service_name = aiven_kafka.tms-demo-kafka.service_name
  permission = "admin"
  username = aiven_service_user.tms-processing-user.username
  topic = "tms-streams-demo-*"
  depends_on = [
    aiven_kafka.tms-demo-kafka
  ]
}

# adming access for intermediate Kafka Streams topics (changelog)
resource "aiven_kafka_acl" "tms-processing-admin-acl-2" {
  project = var.avn_project_id
  service_name = aiven_kafka.tms-demo-kafka.service_name
  permission = "admin"
  username = aiven_service_user.tms-processing-user.username
  topic = "tms-microservice-demo-*"
  depends_on = [
    aiven_kafka.tms-demo-kafka
  ]
}

# adming access for KSQLDB topics
resource "aiven_kafka_acl" "tms-processing-ksql-acl" {
  project = var.avn_project_id
  service_name = aiven_kafka.tms-demo-kafka.service_name
  permission = "admin"
  username = aiven_service_user.tms-processing-user.username
  topic = "_confluent-ksql-tms_demo_ksqldb_*"
  depends_on = [
    aiven_kafka.tms-demo-kafka
  ]
}

#read access for M3 sink service
resource "aiven_kafka_acl" "tms-sink-acl" {
  project = var.avn_project_id
  service_name = aiven_kafka.tms-demo-kafka.service_name
  permission = "read"
  username = aiven_service_user.tms-sink-user.username
  topic = "observations.weather.*"
  depends_on = [
    aiven_kafka.tms-demo-kafka
  ]
}
