#!/bin/bash
source ./ccexample.env

ccexample_setup() {
    avn service create ${SERVICE} -t kafka -p startup-2 --project ${PROJECT}
    avn service wait ${SERVICE}
    avn service topic-create ${SERVICE} ${KAFKA_TOPIC} --partitions 1 --replication 2
    avn service user-creds-download --username avnadmin ${SERVICE}
    URI=$(avn service get ${SERVICE} --format "{service_uri_params[host]}:{service_uri_params[port]}")
    sed -i '' 's/KAFKA_BROKER_LIST=.*/KAFKA_BROKER_LIST="'"${URI}"'"/' ccexample.env
    ccexample_build
}

ccexample_build() {
    mkdir -p build && cd build
    cmake ..
    make
    cd ..
}

ccexample_teardown() {
    echo ${SERVICE} | avn service terminate ${SERVICE}
}

ccexample_producer() {
    ./build/avn_KafkaProducer_Simple
}

ccexample_consumer() {
    ./build/avn_KafkaConsumer_Simple
}

case $1 in
    setup)
        ccexample_setup ;;
    build)
        ccexample_build ;;
    producer)
        ccexample_producer ;;
    consumer)
        ccexample_consumer ;;
    teardown)
        ccexample_teardown ;;
    *)
        printf "Usage: ./ccexample.sh [ setup | build | producer | consumer | teardown ]\n" ;;
esac

