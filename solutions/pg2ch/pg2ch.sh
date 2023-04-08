#!/bin/bash

source ./pg2ch.env

echo "-- CH_CLI: ${CH_CLI}"
echo "-- CH_PGDB: ${CH_PGDB}"
echo "-- CH_SVC: ${CH_SVC}"

avn service integration-create --integration-type clickhouse_postgresql --source-service ${PG_SVC} --dest-service ${CH_SVC}
SERVICE_INTEGRATION_ID=$(avn service integration-list ${CH_SVC} --json | jq -r ".[] | select(.source_service==\""${PG_SVC}"\") | .service_integration_id")
echo "-- SERVICE_INTEGRATION_ID: ${SERVICE_INTEGRATION_ID}"
avn service integration-update ${SERVICE_INTEGRATION_ID} --user-config-json "{\"databases\":[{\"database\":\""${PG_DB}"\",\"schema\":\""${PG_SCHEMA}"\"}]}"
printf "Setting up service integration [${SERVICE_INTEGRATION_ID}] [${PG_SVC}.${PG_DB}.${PG_SCHEMA}] for [${CH_SVC}.${CH_DB}] ...\n\n" && sleep 5

echo "" > ${CH_SQL_LOAD} && echo "" > ${CH_SQL_DROP}

for TABLE in $(echo "show tables from \`${CH_PGDB}\`" | ${CH_CLI});
do
    i=0
    printf "CREATE TABLE IF NOT EXISTS ${CH_DB}.${TABLE}(" >> ${CH_SQL_LOAD}
    while read -r COL_NAME COL_TYPE
    do
        [[ i -ge 1 ]] && printf "," >> ${CH_SQL_LOAD} || KEY=${COL_NAME} ; ((i++))

        [[ "${COL_TYPE}" == *"Nullable"* ]] && echo "Warning: [${COL_TYPE}] column detected in [${TABLE}.${COL_NAME}], null records may fail to be migrated."
#        COL_TYPE=${COL_TYPE#"Nullable("} && COL_TYPE=${COL_TYPE%")"}
        printf "\`${COL_NAME}\` ${COL_TYPE}" >> ${CH_SQL_LOAD}
    done <<< "$(echo "describe \`${CH_PGDB}\`.\`${TABLE}\`" |  ${CH_CLI})"
    printf ") ENGINE = MergeTree() ORDER by ${KEY};\n" >> ${CH_SQL_LOAD}

    printf "CREATE TABLE IF NOT EXISTS ${CH_DB}.${TABLE}_buffer AS ${CH_DB}.${TABLE} ENGINE = Buffer(${CH_DB}, ${TABLE}, ${NUM_LAYERS}, 10, 100, 10000, 1000000, 10000000, 100000000);\n" >> ${CH_SQL_LOAD}
    printf "INSERT INTO ${CH_DB}.${TABLE}_buffer SELECT * FROM \`${CH_PGDB}\`.\`${TABLE}\`;\n" >> ${CH_SQL_LOAD}
    printf "DROP TABLE IF EXISTS ${CH_DB}.${TABLE}_buffer;\n" >> ${CH_SQL_LOAD}
    printf "DROP TABLE IF EXISTS ${CH_DB}.${TABLE};\n" >> ${CH_SQL_DROP}
done

cat << EOF > ${CH_SVC}-${CH_DB}-cleanup.sh
#!/bin/bash
${CH_CLI} --queries-file ./table_sizes.sql --progress=tty 2>&1
printf "This will drop all [${PG_SVC}.${PG_DB}.${PG_SCHEMA}] tables in [${CH_SVC}.${CH_DB}], press any key to continue or CTRL+C to stop\n"
read
${CH_CLI} --queries-file ./${CH_SQL_DROP} --progress=tty --processed-rows --echo -t 2>&1
${CH_CLI} --queries-file ./table_sizes.sql --progress=tty 2>&1
EOF
chmod 755 ${CH_SVC}-${CH_DB}-cleanup.sh

printf "Generated ${CH_SQL_LOAD}, By default tables are ordered by the 1st column, please review and adjust for optimal performance.\n"
printf "Generated ${CH_SQL_DROP}\n\n"

printf "Press any key to load ${CH_SQL_LOAD} to ${CH_SVC}.${CH_DB} or CTRL+C to stop\n"
read 
${CH_CLI} --queries-file ./${CH_SQL_LOAD} --progress=tty --processed-rows --echo -t 2>&1
${CH_CLI} --queries-file ./table_sizes.sql --progress=tty 2>&1
