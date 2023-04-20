#!/bin/bash
source ./lab.env

lab_up() {
avn service create ${SERVICE_OPENSEARCH} -t opensearch -p startup-4 --project ${PROJECT}
avn service create ${SERVICE_KAFKA} -t kafka -p business-4 -c kafka_connect=true -c schema_registry=true --project ${PROJECT}
avn service wait ${SERVICE_KAFKA}
avn service user-creds-download ${SERVICE_KAFKA} --username avnadmin -d .
avn service topic-create ${SERVICE_KAFKA} measurements --partitions 1 --replication 2

avn service wait ${SERVICE_OPENSEARCH}
AVN_PASSWORD=$(avn service user-get --username ${AVN_USERNAME} --json  ${SERVICE_OPENSEARCH} | jq -r '.password')
OS_SERVICE_URL=$(avn service list --json ${SERVICE_OPENSEARCH} | jq -r '.[].service_uri' | sed "s/${AVN_USERNAME}:${AVN_PASSWORD}@//")

cat os-connector.json.example > os-connector.json
sed -i '' -e "s~OS_URL~${OS_SERVICE_URL}~" os-connector.json
sed -i '' -e "s/USERNAME/${AVN_USERNAME}/" os-connector.json
sed -i '' -e "s/PASSWORD/${AVN_PASSWORD}/" os-connector.json

avn service wait ${SERVICE_KAFKA}

echo "Waiting for kafka connector to be available..."
until avn service connector list ${SERVICE_KAFKA} 2>&1>/dev/null ; do sleep 1 ; done
avn service connector create ${SERVICE_KAFKA} "$(cat os-connector.json)"
until avn service connector list ${SERVICE_KAFKA} 2>&1>/dev/null ; do sleep 1 ; done

KAFKA_SERVICE_URI=$(avn service list --json ${SERVICE_KAFKA} | jq -r '.[].service_uri')
echo ${KAFKA_SERVICE_URI}
cat kcat.config.example > kcat.config
sed -i '' -e "s/address:port/${KAFKA_SERVICE_URI}/" kcat.config

read -p "Press any key to start generating data..."
chmod 755 ./measurements_generator.sh && ./measurements_generator.sh
}

lab_down() {
rm -f ca.pem service.cert service.key os-connector.json kcat.config
echo ${SERVICE_KAFKA} | avn service terminate ${SERVICE_KAFKA}
echo ${SERVICE_OPENSEARCH} | avn service terminate ${SERVICE_OPENSEARCH}
}

case $1 in
    up)
        lab_up ;;
    down)
        lab_down ;;
    *)
        printf "Usage: ./lab.sh [up|down]\n" ;;
esac
