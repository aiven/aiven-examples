#!/bin/sh
kubectl create secret generic tms-ingest-cert \
--from-file=secrets/aiven/ingest/service.cert \
--from-file=secrets/aiven/ingest/service.key \
--from-file=secrets/aiven/ingest/ca.pem \
--from-file=secrets/aiven/ingest/client.keystore.p12 \
--from-file=secrets/aiven/ingest/client.truststore.jks \
-n tms-demo
kubectl create secret generic tms-processing-cert \
--from-file=secrets/aiven/processing/service.cert \
--from-file=secrets/aiven/processing/service.key \
--from-file=secrets/aiven/processing/ca.pem \
--from-file=secrets/aiven/processing/client.keystore.p12 \
--from-file=secrets/aiven/processing/client.truststore.jks \
--from-file=secrets/aiven/schema_registry.truststore.jks \
-n tms-demo
kubectl create secret generic tms-sink-cert \
--from-file=secrets/aiven/sink/service.cert \
--from-file=secrets/aiven/sink/service.key \
--from-file=secrets/aiven/sink/ca.pem \
--from-file=secrets/aiven/sink/client.keystore.p12 \
--from-file=secrets/aiven/sink/client.truststore.jks \
-n tms-demo
kubectl create secret generic tms-service-endpoint \
--from-file=BOOTSTRAP_SERVERS=secrets/aiven/kafka_service_uri \
--from-file=SCHEMA_REGISTRY=secrets/aiven/schema_registry_uri \
--from-file=M3_INFLUXDB_URL=secrets/aiven/m3_influxdb_uri \
--from-file=M3_INFLUXDB_CREDENTIALS=secrets/aiven/m3_credentials \
-n tms-demo
kubectl create secret generic tms-os-service \
--from-file=OPENSEARCH_HOST=secrets/aiven/os_host \
--from-file=OPENSEARCH_PORT=secrets/aiven/os_port \
--from-file=OPENSEARCH_USER=secrets/aiven/os_user \
--from-file=OPENSEARCH_PASSWORD=secrets/aiven/os_password \
-n tms-demo
kubectl create -f secrets.yaml
