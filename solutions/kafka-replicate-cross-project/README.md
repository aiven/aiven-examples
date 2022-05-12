# Intro
This guide is intended to assist with replicating Kafka data across projects. At 
the moment it is not possible to link services across projects so we have to use the 
public internet. However, we do not want to expose Kafka to the entire world and will
use static IPs to whitelist only the traffic from MM2.

If we are linking two projects with differing priority levels (e.g. Prod and Dev) then 
we will expose the Dev Kafka and assign static IPs to the MM2 in prod.

This set up assumes you have two valid Aiven projects and each of 
them have active VPCs (Not public internet).

# Execution
Set up env vars for easier execution. Project 1 should be the higher priority project if
applicable.
```bash
export PROJECT1=akahn-demo
export PROJECT2=sa-demo

export KAFKA1=cross-project-kafka-sink
export MM2=cross-project-mm2
export KAFKA2=cross-project-kafka-source

export PROJECT1_CLOUD_VPC=google-us-east4
export PROJECT2_CLOUD_VPC=google-us-east1

export EXTERNAL_KAFKA_ENDPOINT=project2-kafka
```

Generate two static IPs for MM2
```bash
for _ in 1 2
do
  avn static-ip create --cloud $PROJECT1_CLOUD_VPC --project $PROJECT1
done
```

Create a Kafka and MM2 service in Project 1, and a kafka service in project 2.
```bash
avn service create $KAFKA1 \
  -t kafka \
  --project $PROJECT1 \
  --plan startup-2 \
  --cloud $PROJECT1_CLOUD_VPC

avn service create $MM2 \
  -t kafka_mirrormaker \
  --project $PROJECT1 \
  --plan startup-4 \
  --cloud $PROJECT1_CLOUD_VPC
  
avn service create $KAFKA2 \
  -t kafka \
  --project $PROJECT2 \
  --plan startup-2 \
  --cloud $PROJECT2_CLOUD_VPC \
  -c public_access.kafka=true
```

Associate static IPs to MM2 service.
```bash
IP_IDS=$(avn static-ip list --project $PROJECT1 --json | jq -r 'map(.static_ip_address_id) | .[]')
IPS=$(avn static-ip list --project $PROJECT1 --json | jq -c 'map(.ip_address)')
IP_WHITELIST=$(python parse.py $IPS)

echo $IP_IDS | while read ip_id; do
  avn static-ip associate --project $PROJECT1 --service $MM2 $ip_id
done
```

Enable static IPs for MM2. This will cause the service to migrate.
```bash
avn service update -c static_ips=true $MM2 --project $PROJECT1
```

Set the allowed IP list for Kafka2 to be the static IPs of MM2
```bash
avn service update -c ip_filter=$IP_WHITELIST $KAFKA2 --project $PROJECT2
```

Download Kafka2 SSL credentials
```bash
avn service user-creds-download \
  -d creds \
  --project $PROJECT2 \
  --username avnadmin \
  $KAFKA2

export KAFKA2_SERVICE_URI=$(avn service get $KAFKA2 --project $PROJECT2 --json | jq -r '.components | map(select(.component=="kafka" and .route=="public")) | .[0].host')
```

Create external Kafka endpoint for Kafka in project 2
```bash
avn service integration-endpoint-create \
  --project $PROJECT1 \
  --endpoint-type external_kafka \
  --endpoint-name $EXTERNAL_KAFKA_ENDPOINT \
  -c bootstrap_servers=$KAFKA2_SERVICE_URI \
  -c security_protocol=SSL \
  -c ssl_ca_cert="$(cat creds/ca.pem)" \
  -c ssl_client_cert="$(cat creds/service.cert)" \
  -c ssl_client_key="$(cat creds/service.key)"
  
export ENDPOINT_ID=$(avn service integration-endpoint-list --project $PROJECT1 --json | jq -r --arg EXTERNAL_KAFKA_ENDPOINT "$EXTERNAL_KAFKA_ENDPOINT" 'map(select(.endpoint_name==$EXTERNAL_KAFKA_ENDPOINT)) | .[0].endpoint_id')
```

Create the service integration between Kafka1 and MM2 and Kafka2 and MM2.
```bash
avn service integration-create \
  --project $PROJECT1 \
  -t kafka_mirrormaker \
  -s $KAFKA1 \
  -d $MM2 \
  -c cluster_alias=sink

avn service integration-create \
  --project $PROJECT1 \
  -t kafka_mirrormaker \
  -S $ENDPOINT_ID \
  -d $MM2 \
  -c cluster_alias=source
```

Create replication flow in MM2 to move data from Kafka2 to Kafka1
```bash
avn mirrormaker replication-flow create $MM2 '{"enabled": true, "topics": ["test"]}' -s source -t sink --project $PROJECT1
```

# Teardown
```bash
avn service terminate -f $KAFKA1 --project $PROJECT1
avn service terminate -f $MM2 --project $PROJECT1
avn service terminate -f $KAFKA2 --project $PROJECT2
avn service integration-endpoint-delete $ENDPOINT_ID --project $PROJECT1

echo $IP_IDS | while read ip_id; do
    avn static-ip delete --project $PROJECT1 $ip_id
done
```