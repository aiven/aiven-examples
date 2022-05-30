# PostgreSQL to BigQuery using capture data change and Kafka

How to easily make data from PostgreSQL available in real time inside BigQuery to do analytics at scale?

One possible solution: Using Kafka and Kafka connect plugins.

The [Debezium PostgreSQL](https://debezium.io/documentation/reference/stable/connectors/postgresql.html) connector captures row-level changes in the PostgreSQL database and sends messages to a Kafka topic.

The [Kafka connect BigQuery sink](https://github.com/confluentinc/kafka-connect-bigquery) connector sends data from Kafka to BigQuery using the BigQuery [streaming API](https://cloud.google.com/java/docs/reference/google-cloud-bigquery/latest/com.google.cloud.bigquery.InsertAllRequest).


```flow
st=>start: PGSQL
op=>operation: Debezium connector (Use replication slot to stream changes into a kafka topic)
op2=>operation: Kafka topic
op3=>operation: BigQuery sink for Kafka connect (stream)
e=>end: BigQuery

st->op->op2->op3->e
```



## Requirements

Before running this sample solution, you need:
* Python3
* [AIVEN CLI installed](https://aiven.io/blog/command-line-magic-with-the-aiven-cli)
* [Google CLI installed](https://cloud.google.com/sdk/docs/install)
* [An Aiven account with a project](https://console.aiven.io/signup)
* A Google account (with an active credit card as BigQuery stream API is not available with a trial account)

Install Python requirements
```bash
cd solutions/pg-kafka-bigquery
pip3 install -r requirements.txt
```

## Service configuration

Let's define some variables (modify it to match your own setup):
```bash
export CLOUD=google-europe-north1

export PROJECT_NAME=jb-demo

export PG_SERVICE_NAME=jb-pgsql
export PG_DATABASE_NAME=cpu_usage

export KAFKA_SERVICE_NAME=jb-kafka
export KAFKA_TOPIC_NAME=$PG_DATABASE_NAME
export KAFKA_USER_NAME=cpu_usage_app

export KAFKA_CONNECT_SERVICE_NAME=jb-kafkaconnect
export KAFKA_CONNECT_PGSQL_TASK_NAME=pgsql-cpu-usage-cdc
export KAFKA_CONNECT_BIGQUERY_NAME=bigquery-cpu-usage-cdc

export GCP_PROJECT_NAME=aiven-demo
export KAFKA_CONNECT_BIGQUERY_TASK_NAME=bigquery-cpu-usage-cdc
export BIGQUERY_DATASET_NAME=jbdataset
export BIGQUERY_USER_NAME=jbdemouser
```

## AIVEN - Create PostgreSQL database and a table

```bash
avn service create \
   --service-type pg \
   --project $PROJECT_NAME \
   --cloud $CLOUD \
   --plan startup-4 \
   $PG_SERVICE_NAME

avn service wait \
   --project $PROJECT_NAME \
   $PG_SERVICE_NAME

avn service database-create \
   --project $PROJECT_NAME \
   --dbname $PG_DATABASE_NAME \
   $PG_SERVICE_NAME 

export PG_HOST=$(avn service get $PG_SERVICE_NAME --project $PROJECT_NAME --json | jq -r '.connection_info.pg_params[0].host')
export PG_PORT=$(avn service get $PG_SERVICE_NAME --project $PROJECT_NAME --json | jq -r '.connection_info.pg_params[0].port')
export PG_USER=$(avn service get $PG_SERVICE_NAME --project $PROJECT_NAME --json | jq -r '.connection_info.pg_params[0].user')
export PG_PASSWORD=$(avn service get $PG_SERVICE_NAME --project $PROJECT_NAME --json | jq -r '.connection_info.pg_params[0].password')
export PG_SSL_MODE=$(avn service get $PG_SERVICE_NAME --project $PROJECT_NAME --json | jq -r '.connection_info.pg_params[0].sslmode')
export PG_URI=$(avn service get $PG_SERVICE_NAME --project $PROJECT_NAME --json | jq -r '.connection_info.pg[0]')

echo "PGSQL: $PG_HOST:$PG_PORT (User: $PG_USER, Pass:$PG_PASSWORD) [SSL Mode=$PG_SSL_MODE]"
echo "PGSQL: $PG_URI"

psql ${PG_URI//defaultdb/$PG_DATABASE_NAME} -c "CREATE TABLE cpu_usage(id SERIAL PRIMARY KEY, hostname VARCHAR(20), cpu SMALLINT, usage SMALLINT, occurred_at TIMESTAMP);"
```

Execution result:

```
PGSQL: 35.228.172.94:24947 (User: avnadmin, Pass:AVNS_xxx) [SSL Mode=require]
PGSQL: postgres://avnadmin:AVNS_xxx@35.228.172.94:24947/defaultdb?sslmode=require
```

## AIVEN - Create Kafka service, topic and user

```bash
avn service create \
   --service-type kafka \
   --project $PROJECT_NAME \
   --cloud $CLOUD \
   --plan startup-2 \
   $KAFKA_SERVICE_NAME

avn service wait \
   --project $PROJECT_NAME \
   $KAFKA_SERVICE_NAME

avn service topic-create \
   --project $PROJECT_NAME \
   --partitions 2 \
   --replication 3 \
   $KAFKA_SERVICE_NAME \
   $KAFKA_TOPIC_NAME

avn service user-create \
   --project $PROJECT_NAME \
   --username $KAFKA_USER_NAME \
   $KAFKA_SERVICE_NAME

avn service acl-add \
   --project $PROJECT_NAME \
   --username $KAFKA_USER_NAME \
   --permission readwrite \
   --topic $KAFKA_TOPIC_NAME \
   $KAFKA_SERVICE_NAME

rm -Rf ./kafkacerts
avn service user-creds-download \
   --project $PROJECT_NAME \
   --username $KAFKA_USER_NAME \
   --target-directory ./kafkacerts \
   $KAFKA_SERVICE_NAME  

avn service update \
   --project $PROJECT_NAME \
   -c "kafka.auto_create_topics_enable=true" \
   $KAFKA_SERVICE_NAME 

avn service acl-list \
   --project $PROJECT_NAME \
   $KAFKA_SERVICE_NAME 

export KAFKA_HOSTNAME=$(avn service get $KAFKA_SERVICE_NAME --project $PROJECT_NAME --json | jq -r '.components[] | select(.component=="kafka").host') 
export KAFKA_PORT=$(avn service get $KAFKA_SERVICE_NAME --project $PROJECT_NAME --json | jq -r '.components[] | select(.component=="kafka").port')
echo "Kafka hostname and port: $KAFKA_HOSTNAME $KAFKA_PORT"
```

Execution result:

```
ID              USERNAME       TOPIC      PERMISSION
==============  =============  =========  ==========
default         avnadmin       *          admin
acl3b5bb6fa43a  cpu_usage_app  cpu_usage  readwrite

Kafka hostname and port: jb-kafka-jb-demo.aivencloud.com 24949
```


## AIVEN - Create Kafka connect and configure capture data change (CDC) with Debezium connector

```bash
avn service create \
   --service-type kafka_connect \
   --project $PROJECT_NAME \
   --cloud $CLOUD \
   --plan startup-4 \
   $KAFKA_CONNECT_SERVICE_NAME

avn service wait \
   --project $PROJECT_NAME \
   $KAFKA_CONNECT_SERVICE_NAME

avn service integration-create \
   --integration-type kafka_connect \
   --project $PROJECT_NAME \
   --source-service $KAFKA_SERVICE_NAME \
   --dest-service $KAFKA_CONNECT_SERVICE_NAME

# avnadminuser is not allow to create replication slot, let's authorize
psql ${PG_URI//defaultdb/$PG_DATABASE_NAME} -c "CREATE EXTENSION aiven_extras CASCADE;"
psql ${PG_URI//defaultdb/$PG_DATABASE_NAME} -c "SELECT * FROM aiven_extras.pg_create_publication_for_all_tables('debezium', 'INSERT,UPDATE,DELETE');"

envsubst < debezium-pgsql.json.template > debezium-pgsql.json

sleep 5

avn service connector create \
   --project $PROJECT_NAME \
   $KAFKA_CONNECT_SERVICE_NAME \
   @debezium-pgsql.json

sleep 2

avn service connector status \
   --project $PROJECT_NAME \
   $KAFKA_CONNECT_SERVICE_NAME \
   $KAFKA_CONNECT_PGSQL_TASK_NAME
```

Execution result:

```
{
    "status": {
        "state": "RUNNING",
        "tasks": [
            {
                "id": 0,
                "state": "RUNNING",
                "trace": ""
            }
        ]
    }
}
```


## Check everything is working on AIVEN side

Add some data in PGSQL
```bash
psql ${PG_URI//defaultdb/$PG_DATABASE_NAME} -c "INSERT INTO cpu_usage(hostname, cpu, usage, occurred_at) values('cluster0', 100, 45, NOW()::timestamp);"

psql ${PG_URI//defaultdb/$PG_DATABASE_NAME} -c "INSERT INTO cpu_usage(hostname, cpu, usage, occurred_at) values('cluster1', 100, 30, NOW()::timestamp);"
```

Get the topic in Kafka
```
timeout 10s python3 consume.py ./kafkacerts/ $KAFKA_TOPIC_NAME c2
```

Execution result:
```
Receiving: {'hostname': 'cluster1', 'cpu': 1, 'usage': 30, 'occurred_at': 1653436800000000}
Receiving: {'hostname': 'cluster0', 'cpu': 1, 'usage': 45, 'occurred_at': 1653436800000000}
```

## GCP - Creating a BigQuery dataset and a new service account

```bash
gcloud config set project $GCP_PROJECT_NAME
bq mk --dataset $BIGQUERY_DATASET_NAME

gcloud iam service-accounts create $BIGQUERY_USER_NAME --description "Demo BigQuery"
gcloud iam service-accounts keys create \
   --iam-account=$BIGQUERY_USER_NAME@$GCP_PROJECT_NAME.iam.gserviceaccount.com \
   bquser.json

bq show --format=prettyjson $BIGQUERY_DATASET_NAME > $BIGQUERY_DATASET_NAME.json
jq ".access += [{ \"role\": \"WRITER\", \"userByEmail\": \"$BIGQUERY_USER_NAME@$GCP_PROJECT_NAME.iam.gserviceaccount.com\"}]" $BIGQUERY_DATASET_NAME.json > $BIGQUERY_DATASET_NAME-new.json
bq update --source $BIGQUERY_DATASET_NAME-new.json $BIGQUERY_DATASET_NAME
```

   
## AIVEN - Configure a BigQuery sink connector

```bash
export KEY=$(<bquser.json)
export ESCAPED_KEY=${KEY//\"/\\\"}
export ESCAPED_KEY=${ESCAPED_KEY//$'\n'/}
export ESCAPED_KEY=${ESCAPED_KEY//\\\n/\\\\\n}
envsubst < bigquery-sink.json.template > bigquery-sink.json

avn service connector create \
   --project $PROJECT_NAME \
   $KAFKA_CONNECT_SERVICE_NAME \
   @bigquery-sink.json

avn service connector status \
   --project $PROJECT_NAME \
   $KAFKA_CONNECT_SERVICE_NAME \
   $KAFKA_CONNECT_BIGQUERY_NAME
```

Execution result:

```
{
    "status": {
        "state": "RUNNING",
        "tasks": [
            {
                "id": 0,
                "state": "RUNNING",
                "trace": ""
            }
        ]
    }
}
```

## Check everything is working from end to end


Add some data in PGSQL
```bash
psql ${PG_URI//defaultdb/$PG_DATABASE_NAME} -c "INSERT INTO cpu_usage(hostname, cpu, usage, occurred_at) values('cluster20', 100, 45, NOW()::timestamp);"
```

Query (Wait 1 minute before the streaming process starts)
```
bq query --use_legacy_sql=false "SELECT after.* FROM \`$GCP_PROJECT_NAME.$BIGQUERY_DATASET_NAME.$KAFKA_TOPIC_NAME\`"
```

To import more data, let's use a cpu usage simulator demo code:
```bash
python3 produce.py --time=10 --velocity=5
```

Query
```
bq query --use_legacy_sql=false "SELECT after.* FROM \`$GCP_PROJECT_NAME.$BIGQUERY_DATASET_NAME.$KAFKA_TOPIC_NAME\` WHERE after.cpu < 5"
```

You should see 50 records (5 records per second x 10 seconds)

Now, just play with it before cleaning up

## CLEANUP

AIVEN services:

```bash
avn service terminate \
   --project $PROJECT_NAME \
   --force \
   $KAFKA_CONNECT_SERVICE_NAME


avn service terminate \
   --project $PROJECT_NAME \
   --force \
   $PG_SERVICE_NAME

avn service terminate \
   --project $PROJECT_NAME \
   --force \
   $KAFKA_SERVICE_NAME
```

Google Cloud resources:

```bash
bq rm -f -r $BIGQUERY_DATASET_NAME
gcloud iam service-accounts delete $BIGQUERY_USER_NAME@$GCP_PROJECT_NAME.iam.gserviceaccount.com
```
