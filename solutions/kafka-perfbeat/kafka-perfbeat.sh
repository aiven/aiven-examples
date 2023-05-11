#!/bin/bash

source kafka-perfbeat.env

perfbeat_init() {

    rm -f client.properties client.truststore.jks client.keystore.p12

    avn service user-kafka-java-creds ${SERVICE_KAFKA} --username avnadmin -d .
    REPLICATION_FACTOR=$(expr $(avn service get ${SERVICE_KAFKA} --json | jq '.node_count') - 1)
    avn service topic-create ${SERVICE_KAFKA} perfbeat --partitions 1 --replication ${REPLICATION_FACTOR} --retention-bytes ${RETENTION_BYTES}
    avn service wait ${SERVICE_KAFKA}

    KAFKA_SERVICE_URI=$(avn service list --json ${SERVICE_KAFKA} | jq -r '.[].service_uri')
    echo ${KAFKA_SERVICE_URI}
}

perfbeat_producer() {
    perfbeat_init

    while [ 1 ];
    do
        metrics="$(${KAFKA_HOME}/bin/kafka-producer-perf-test.sh --topic ${TOPIC} --throughput ${MAX_RECORDS} --num-records ${MAX_RECORDS} --record-size ${RECORD_SIZE} --producer-props acks=all bootstrap.servers=${KAFKA_SERVICE_URI} --producer.config ./client.properties --print-metrics | grep ^producer- | sed 's/[[:space:]]//g')"
        for line in ${metrics};
        do
            KEY="${METRIC_PREFIX}."$(echo "$line" | cut -d'{' -f1 | sed 's/.$//; s/:/./;')
            VAL=$(echo "$line" | awk -F':' {'print $NF'})

            [[ $VAL == "NaN" ]] && VAL="0"

            echo "$KEY--$VAL"
            ../scripts/dd-custom-metric.sh $KEY $VAL &
        done
        sleep ${SLEEP}
    done
}

perfbeat_consumer() {
    perfbeat_init

    while [ 1 ];
    do
        metrics="$(${KAFKA_HOME}/bin/kafka-consumer-perf-test.sh --topic ${TOPIC} --messages ${MAX_RECORDS} --consumer.config ./client.properties --bootstrap-server=${KAFKA_SERVICE_URI} --print-metrics --show-detailed-stats | grep ^consumer- | sed 's/[[:space:]]//g')"
        for line in ${metrics};
        do

            KEY="${METRIC_PREFIX}."$(echo "$line" | cut -d'{' -f1 | sed 's/.$//; s/:/./;')
            VAL=$(echo "$line" | awk -F':' {'print $NF'})

            [[ $VAL == "NaN" ]] && VAL="0"

            echo "$KEY--$VAL"
            ../scripts/dd-custom-metric.sh $KEY $VAL &
        done
        sleep ${SLEEP}
    done
}

case $1 in
    producer)
        perfbeat_producer ;;
    consumer)
        perfbeat_consumer ;;
    *)
       printf "Usage: ./kafka-perfbeat.sh [producer|consumer]\n" ;;
esac
