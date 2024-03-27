#!/bin/bash
source ./lab.env

setup_env() {
CH_JSON="$(avn service get --json ${SERVICE_CH} --project ${PROJECT})"

CH_USER=avnadmin
CH_PASS=$(echo ${CH_JSON} | jq -r '.users[] | select(.username=="avnadmin") | .password')
CH_HOST=$(echo ${CH_JSON} | jq -r '.components[] | select(.component=="clickhouse") | .host')
CH_PORT=$(echo ${CH_JSON} | jq -r '.components[] | select(.component=="clickhouse") | .port')
CH_HTTPS_PORT=$(echo ${CH_JSON} | jq -r '.components[] | select(.component=="clickhouse_https") | .port')
CH_CLI="./clickhouse client --user ${CH_USER} --password ${CH_PASS} --host ${CH_HOST} --port ${CH_PORT} --secure"

PG_SERVICE_URI=$(avn service get ${SERVICE_PG} --json | jq -r '.service_uri')
}

lab_clickhouse() {
    setup_env
    echo $CH_CLI
    $CH_CLI $@
}

lab_psql() {
    setup_env
    echo $PG_SERVICE_URI
    psql ${PG_SERVICE_URI} $@
}

lab_setuppg() {
    echo
    PG_SERVICE_URI=$(avn service get ${SERVICE_PG} --json | jq -r '.service_uri')
    cat pg_tables.sql | psql ${PG_SERVICE_URI} \
    && printf "✅ " || echo "❌ "
    echo "pg_tables.sql imported into postgres ${SERVICE_PG}"
}

lab_setup() {
    cd terraform && terraform apply ; cd ..

    setup_env
    avn service user-creds-download ${SERVICE_KAFKA} --username avnadmin -d . \
    && printf "✅ " || echo "❌ "
    echo "certificates and keys downloaded from ${SERVICE_KAFKA}"

    echo
    KAFKA_SERVICE_URI=$(avn service list --json ${SERVICE_KAFKA} | jq -r '.[].service_uri')
    echo ${KAFKA_SERVICE_URI}
    cat kcat.config.template > kcat.config
    sed -i -e "s/address:port/${KAFKA_SERVICE_URI}/" kcat.config \
    && printf "✅ " || echo "❌ "
    echo "kcat.config setup completed"

    echo
    PG_SERVICE_URI=$(avn service get ${SERVICE_PG} --json | jq -r '.service_uri')
    cat pg_tables.sql | psql ${PG_SERVICE_URI} \
    && printf "✅ " || echo "❌ "
    echo "pg_tables.sql imported into postgres ${SERVICE_PG}"

    [ -e "./clickhouse" ] || curl https://clickhouse.com/ | sh

    avn service connector restart-task ${SERVICE_KAFKA} kafka-pg-source 0
    ${CH_CLI} --queries-file ./ch_mv.sql --progress=tty --processed-rows --echo -t 2>&1
}

lab_teardown() {
    rm -f ca.pem service.cert service.key os-connector.json kcat.config
    cd terraform && terraform destroy ; cd ..
}

lab_pgload() {
    setup_env
    num_entries=$1

    echo "Generating ${num_entries} entries..."
    SQL="\c middleearth;\n"
    for _ in $(seq $num_entries); do
        # time_stamp=$(date +%s)

        region="1$((RANDOM % 2))"
        total="1$((RANDOM % 1000))"
        temperature=$((RANDOM % 66 - 20)).$((RANDOM % 100))
        
        PSQL+="INSERT INTO population (region, total) VALUES (${region}, ${total});\n"
        WSQL+="INSERT INTO weather (region, temperature) VALUES (${region}, ${temperature});\n"        
    done
    SQL+=${PSQL}${WSQL};

    printf "${SQL}"
    printf "${SQL}" | psql ${PG_SERVICE_URI}
}

lab_chmv() {
    setup_env
    ROLE=$1
    REGION=$2
    echo "REGION: ${REGION}"
    avn service clickhouse database create ${SERVICE_CH} ${ROLE} \
    && printf "✅ " || echo "❌ "
    echo "${ROLE} created in clickhouse ${SERVICE_CH}"
    sed -e "s/role_name/${ROLE}/g" mv.sql.template > mv-${ROLE}.sql
    sed -i -e "s/region_id/${REGION}/g" mv-${ROLE}.sql \
    && printf "✅ " || echo "❌ "
    echo " mv-${ROLE}.sql created successfully."
    ${CH_CLI} --queries-file ./mv-${ROLE}.sql --progress=tty --processed-rows --echo -t 2>&1
}

lab_reset() {
    setup_env
    printf "Reset all test data in postgres ${SERVICE_PG} and clickhouse ${SERVICE_CH}..."
    printf "\c middleearth;\nDELETE FROM population;\nDELETE FROM weather;\n" | psql ${PG_SERVICE_URI}
    # ${CH_CLI} --queries-file ./ch_drop.sql --progress=tty --processed-rows --echo -t 2>&1

    avn service clickhouse database delete cdc-clickhouse rivendell
    avn service clickhouse database delete cdc-clickhouse shire

    lab_chmv rivendell 10
    lab_chmv shire 11
    ${CH_CLI} --queries-file ./ch_users.sql --progress=tty --processed-rows --echo -t 2>&1

    lab_pgload 10
}

case $1 in
    clickhouse)
        lab_clickhouse "${@:2}" ;;
    psql)
        lab_psql "${@:2}" ;;
    reset)
        lab_reset ;;
    setup)
        lab_setup ;;
    setuppg)
        lab_setuppg ;;
    teardown)
        lab_teardown ;;
    pgload)
        lab_pgload "${@:2}" ;;
    chmv)
        lab_chmv "${@:2}" ;; 
    *)
        printf "Usage: ./lab.sh [ setup | clickhouse | psql | pgload n | reset | teardown]\n" ;;
esac
