#!/bin/sh
# Download Kafka service user certificates
[ ! -d "k8s/secrets/aiven/ingest" ] && avn service user-kafka-java-creds --project $1 --username tms-ingest-user -p supersecret -d k8s/secrets/aiven/ingest tms-demo-kafka
[ ! -d "k8s/secrets/aiven/processing" ] && avn service user-kafka-java-creds --project $1 --username tms-processing-user -p supersecret -d k8s/secrets/aiven/processing tms-demo-kafka
[ ! -d "k8s/secrets/aiven/sink" ] && avn service user-kafka-java-creds --project $1 --username tms-sink-user -p supersecret -d k8s/secrets/aiven/sink tms-demo-kafka
[ ! -d "k8s/secrets/aiven/admin" ] && avn service user-kafka-java-creds --project $1 --username avnadmin -p supersecret -d k8s/secrets/aiven/admin tms-demo-kafka

# Generate pgpassfile for bootstrapping PostgreSQL tables
avn service get tms-demo-pg --json -v --project $1|jq -r '("host=" + .service_uri_params.host + " port=" + .service_uri_params.port + " dbname=" + .service_uri_params.dbname + " user=" + .service_uri_params.user + " password=" + .service_uri_params.password)' > database/pgpassfile

# Extract endpoints and secrets from Aiven services
KAFKA_JSON=$(avn service get tms-demo-kafka --project $1 --json -v)
M3_OBS_JSON=$(avn service get tms-demo-obs-m3db --project $1 --json -v)
M3_IOT_JSON=$(avn service get tms-demo-iot-m3db --project $1 --json -v)
OS_JSON=$(avn service get tms-demo-os --project $1 --json -v)

M3_PROM_URI=$(jq -r '.components[] | select(.component == "m3coordinator_prom_remote_write") |"https://\(.host):\(.port)\(.path)"' <<< $M3_OBS_JSON)
M3_PROM_USER=$(jq -r '.users[] | select(.type == "primary") |"\(.username)"' <<< $M3_OBS_JSON)
M3_PROM_PWD=$(jq -r '.users[] | select(.type == "primary") |"\(.password)"' <<< $M3_OBS_JSON)
M3_INFLUXDB_URI=$(jq -r '"https://" + (.service_uri_params.host + ":" + .service_uri_params.port + "/api/v1/influxdb/write")' <<< $M3_IOT_JSON)
M3_CREDENTIALS=$(jq -r '.users[] | select(.type == "primary") |"\(.username):\(.password)"' <<< $M3_IOT_JSON)

SCHEMA_REGISTRY_HOST=$(jq -r '.components[] | select(.component == "schema_registry") |"\(.host):\(.port)"' <<< $KAFKA_JSON)
SCHEMA_REGISTRY_URI=$(jq -r .connection_info.schema_registry_uri <<< $KAFKA_JSON)
KAFKA_SERVICE_URI=$(jq -r .service_uri <<< $KAFKA_JSON)

OS_HOST=$(jq -r '(.service_uri_params.host)' <<< $OS_JSON)
OS_PORT=$(jq -r '(.service_uri_params.port)' <<< $OS_JSON)
OS_USER=$(jq -r '(.service_uri_params.user)' <<< $OS_JSON)
OS_PASSWORD=$(jq -r '(.service_uri_params.password)' <<< $OS_JSON)


echo $SCHEMA_REGISTRY_URI > k8s/secrets/aiven/schema_registry_uri
echo $M3_INFLUXDB_URI > k8s/secrets/aiven/m3_influxdb_uri
echo $M3_CREDENTIALS > k8s/secrets/aiven/m3_credentials
echo $M3_PROM_USER > k8s/secrets/aiven/m3_prom_user
echo $M3_PROM_PWD > k8s/secrets/aiven/m3_prom_pwd
echo $M3_PROM_URI > k8s/secrets/aiven/m3_prom_uri
echo $KAFKA_SERVICE_URI > k8s/secrets/aiven/kafka_service_uri
echo $OS_HOST > k8s/secrets/aiven/os_host
echo $OS_PORT > k8s/secrets/aiven/os_port
echo $OS_USER > k8s/secrets/aiven/os_user
echo $OS_PASSWORD > k8s/secrets/aiven/os_password

# Generate truststore for Schema Registry CA
openssl s_client -connect $SCHEMA_REGISTRY_HOST -showcerts < /dev/null 2>/dev/null | awk '/BEGIN CERT/{s=1}; s{t=t "\n" $0}; /END CERT/ {last=t; t=""; s=0}; END{print last}' > k8s/secrets/aiven/sr-ca.cert
keytool -import -file k8s/secrets/aiven/sr-ca.cert -alias CA -keystore k8s/secrets/aiven/schema_registry.truststore.jks -storepass supersecret -noprompt

