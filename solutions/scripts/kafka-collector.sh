KAFKA_HOST="service-project.a.aivencloud.com"
KAFKA_PORT="24949"
KAFKA_URI="${KAFKA_HOST}:${KAFKA_PORT}"
KAFKA_CONF="./client.properties"
KAFKA_HOME="/opt/kafka"
KAFKA_INFO="${KAFKA_HOST}.txt"

# get cluster configuration
get_cluster_config() {
  echo "----------========== Kafka Cluster Configuration ==========----------"
  ${KAFKA_HOME}/bin/kafka-configs.sh --bootstrap-server ${KAFKA_URI} --describe --all --command-config ${KAFKA_CONF} --entity-type brokers
  ${KAFKA_HOME}/bin/kafka-configs.sh --bootstrap-server ${KAFKA_URI} --describe --all --command-config ${KAFKA_CONF} --entity-type topics
}

# get list of topics
get_topics() {
  echo "----------========== Topics  ==========----------"
  ${KAFKA_HOME}/bin/kafka-topics.sh --bootstrap-server ${KAFKA_URI} --describe --command-config ${KAFKA_CONF}
}

# get all consumer groups
get_consumer_groups() {
    echo "----------========== Consumers  ==========----------"
    ${KAFKA_HOME}/bin/kafka-consumer-groups.sh --bootstrap-server ${KAFKA_URI} --describe --all-groups --command-config ${KAFKA_CONF}
}

get_cluster_config > ${KAFKA_INFO}
get_topics >> ${KAFKA_INFO}
get_consumer_groups >> ${KAFKA_INFO}
