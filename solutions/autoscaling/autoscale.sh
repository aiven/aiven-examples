#!/bin/bash
source ./autoscale.env

autoscale_setup() {
    # create prometheus endpoint
    avn service integration-endpoint-create -d ${PROMETHEUS_NAME} -t prometheus -c basic_auth_username=${PROMETHEUS_USER} -c basic_auth_password=${PROMETHEUS_PASS}
    avn service create ${SERVICE} -t ${AUTOSCALE_PLAN_TYPE} -p ${AUTOSCALE_CURRENT_PLAN} --project ${PROJECT}
    avn service wait ${SERVICE}

    # create prometheus integration
    PROMETHEUS_ENDPOINT_ID=$(avn service integration-endpoint-list --json | jq -r --arg PROMETHEUS_NAME ${PROMETHEUS_NAME} '.[] | select(.endpoint_name == $PROMETHEUS_NAME) | .endpoint_id')
    avn service integration-create -s ${SERVICE} -D ${PROMETHEUS_ENDPOINT_ID} -t prometheus
    printf "${SERVICE} environment is ready! run [./autoscale.sh demo] to start the demo.\n"
}

autoscale_teardown() {
    PROMETHEUS_ENDPOINT_ID=$(avn service integration-endpoint-list --json | jq -r --arg PROMETHEUS_NAME ${PROMETHEUS_NAME} '.[] | select(.endpoint_name == $PROMETHEUS_NAME) | .endpoint_id')
    avn service integration-endpoint-delete ${PROMETHEUS_ENDPOINT_ID}
    echo "Deleted ${PROMETHEUS_NAME} ID: ${PROMETHEUS_ENDPOINT_ID}"
    echo ${SERVICE} | avn service terminate ${SERVICE}
}

autoscale_demo() {
    PROMETHEUS_PORT=$(avn service integration-endpoint-list --json | jq -r --arg PROMETHEUS_NAME ${PROMETHEUS_NAME} '.[] | select(.endpoint_name == $PROMETHEUS_NAME) | .endpoint_config.client_port')
    PROMETHEUS_HOST=$(avn service get ${SERVICE} --json | jq -r '.service_uri_params.host')
    PROMETHEUS_URL="https://${PROMETHEUS_USER}:${PROMETHEUS_PASS}@${PROMETHEUS_HOST}:${PROMETHEUS_PORT}/metrics"
    printf "Prometheus URL: ${PROMETHEUS_URL}\n"

    printf "Waiting for metrics to be available..."
    while [ -z "${CPU_IDLE}" ]; do
        CPU_IDLE=$(curl -sk ${PROMETHEUS_URL} | grep cpu_usage_idle{ | awk -F '[{},] *' '/cpu="cpu-total"/ {print $(NF)}')
        printf "."
    done

    while [ 1 ]; do
        # parse out total cpu idle %
        CPU_IDLE=$(curl -sk ${PROMETHEUS_URL} | grep cpu_usage_idle{ | awk -F '[{},] *' '/cpu="cpu-total"/ {print $(NF)}')

        if [ -z "${CPU_IDLE}" ]; then
            printf "Unable to get metrics...\n"
        else
            printf "CPU idle ${CPU_IDLE}%%\n"
            # convert flat to int
            CPU_IDLE=${CPU_IDLE%.*}

            if [ -n "${CPU_IDLE}" ] && (( ${CPU_IDLE} < ${CPU_IDLE_MAX} )); then
                i=$((i+1))
                echo "CPU usage reached threshold! [${i}]"
            else
                i=0
            fi

            if (( $i >=${AUTOSCALE_THRESHOLD} )); then
                echo "Upgrading this plan!"
                avn service update -p ${AUTOSCALE_NEXT_PLAN} ${SERVICE}
                avn service wait ${SERVICE}
            fi
        fi
        sleep ${AUTOSCALE_INTERVAL}
    done
}

autoscale_pgload() {
    echo "Running an expensive query..."
    cat ./pgload.sql
    SERVICE_URI=$(avn service connection-info pg uri ${SERVICE})
    psql ${SERVICE_URI} -f ./pgload.sql
}

case $1 in
    setup)
        autoscale_setup ;;
    demo)
        autoscale_demo ;;
    pgload)
        autoscale_pgload ;;
    teardown)
        autoscale_teardown ;;
    *)
        printf "Usage: ./autoscale.sh [setup|demo|pgload|teardown]\n" ;;
esac
