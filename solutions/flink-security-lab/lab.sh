source ./lab.env

lab_setup() {
avn service user-creds-download ${SERVICE_KAFKA} --username avnadmin -d .

KAFKA_SERVICE_URI=$(avn service list --json ${SERVICE_KAFKA} | jq -r '.[].service_uri')
echo ${KAFKA_SERVICE_URI}
cat kcat.config.example > kcat.config
sed -i '' -e "s/address:port/${KAFKA_SERVICE_URI}/" kcat.config

PG_SERVICE_URI=$(avn service get ${SERVICE_PG} --json | jq -r '.service_uri')
cat audit_logs.sql | psql ${PG_SERVICE_URI}

OS_SERVICE_URI=$(avn service get ${SERVICE_OS} --json | jq -r '.service_uri')
curl -X PUT ${OS_SERVICE_URI}/suspecious-logins -H 'Content-Type: application/json' --data @suspecious-logins-mapping.json
}

lab_teardown() {
rm -f ca.pem service.cert service.key os-connector.json kcat.config
echo ${SERVICE_KAFKA} | avn service terminate ${SERVICE_KAFKA}
echo ${SERVICE_FLINK} | avn service terminate ${SERVICE_FLINK}
echo ${SERVICE_OS} | avn service terminate ${SERVICE_OS}
echo ${SERVICE_PG} | avn service terminate ${SERVICE_PG}
}

lab_demo() {
while true; do
    num_entries=$((1 + RANDOM % 100))

    for _ in $(seq $num_entries); do
        time_stamp=$(date +%s)
        user_id=$((190 + RANDOM % 10))
        action=("login" "attempt")
        random_action=${action[RANDOM % ${#action[@]}]}
        source_ip="192.168.123.16$((RANDOM % 10))"

        echo "{\"time_stamp\": $time_stamp, \"user_id\": $user_id, \"action\": \"$random_action\", \"source_ip\": \"$source_ip\"}" | kcat -T -F kcat.config -P -t security_logs
    done

    sleep 5 
done
}

case $1 in
    setup)
        lab_setup ;;
    teardown)
        lab_teardown ;;
    demo)
        lab_demo ;;
    *)
        printf "Usage: ./lab.sh [setup|teardown]\n" ;;
esac
