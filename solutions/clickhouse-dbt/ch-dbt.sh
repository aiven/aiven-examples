#!/bin/bash
set -e
source ./ch-dbt.env

ch_dbt_config() {
    CH_JSON="$(avn service get --json ${SERVICE} --project ${PROJECT})"

    CH_USER=avnadmin
    CH_PASS=$(echo ${CH_JSON} | jq -r '.users[] | select(.username=="avnadmin") | .password')
    CH_HOST=$(echo ${CH_JSON} | jq -r '.components[] | select(.component=="clickhouse") | .host')
    CH_PORT=$(echo ${CH_JSON} | jq -r '.components[] | select(.component=="clickhouse") | .port')
    CH_HTTPS_PORT=$(echo ${CH_JSON} | jq -r '.components[] | select(.component=="clickhouse_https") | .port')

    CH_CLI="./clickhouse client --user ${CH_USER} --password ${CH_PASS} --host ${CH_HOST} --port ${CH_PORT} --secure"
}

ch-dbt_setup() {
    python3 -m venv venv &&
        printf "✅ " || echo "❌ "
    echo "python venv environment setup completed"

    . venv/bin/activate
    pip install -r requirements.txt &&
        printf "✅ " || echo "❌ "
    echo "python requirements installed successfully"
    deactivate

    rm -f clickhouse
    curl https://clickhouse.com/ | sh
    avn service create -t clickhouse -p startup-16 ${SERVICE}
    avn service wait ${SERVICE}
    avn service clickhouse database create ${SERVICE} imdb
    avn service clickhouse database create ${SERVICE} imdb_dbt
}

ch-dbt_demo() {
    ch_dbt_config
    ${CH_CLI} --queries-file ../clickhouse-dbt/create.sql --progress=tty --processed-rows --echo -t 2>&1
    ${CH_CLI} --queries-file ../clickhouse-dbt/insert.sql --progress=tty --processed-rows --echo -t 2>&1
    ${CH_CLI} --queries-file ../clickhouse-dbt/select.sql --progress=tty --processed-rows --echo -t 2>&1

    rm -rf imdb/ logs/
    echo "1" | dbt init imdb

    cat profiles.yml.sample | sed -e "s/CH_HOST/${CH_HOST}/" >imdb/profiles.yml
    sed -i '' -e "s/CH_USER/${CH_USER}/" imdb/profiles.yml
    sed -i '' -e "s/CH_PASS/${CH_PASS}/" imdb/profiles.yml
    sed -i '' -e "s/CH_HTTPS_PORT/${CH_HTTPS_PORT}/" imdb/profiles.yml

    cp dbt_project.yml.sample imdb/dbt_project.yml
    cd imdb
    rm -rf models/example
    mkdir -p models/actors
    cp -p ../actor_summary.sql models/actors/
    cp -p ../schema.yml models/actors/
    dbt debug
    dbt run
    cd ..

    ${CH_CLI} --queries-file select-imdb_dbt.sql --progress=tty --processed-rows --echo -t 2>&1
}

ch-dbt_teardown() {
    rm -f ca.pem service.cert service.key os-connector.json kcat.config clickhouse
    echo ${SERVICE} | avn service terminate ${SERVICE}
}

case $1 in
setup)
    ch-dbt_setup
    ;;
demo)
    ch-dbt_demo
    ;;
teardown)
    ch-dbt_teardown
    ;;
demo)
    ch-dbt_demo
    ;;
*)
    printf "Usage: ./ch-dbt.sh [ setup | demo | teardown ]\n"
    ;;
esac
