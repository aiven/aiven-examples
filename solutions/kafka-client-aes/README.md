`# Kafka producer & consumer encryption/decryption

This is a short example on how to encrypt data using custom serdes in Kafka. 

The example is produced in Python, but similar approaches in other languages can be done. 

As noted in the code, the key should never be hardcoded like it is here - this is purely to demonstrate the functionality. 

# Setup

This guide assumes you already have the aiven-client installed

https://pypi.org/project/aiven-client/

Create, then initialize the virtual environment. Install required packages. 
```
python -m venv venv
source venv/bin/activate
pip install -r requirements.txt
```

Set the following variables which get used in the configuration of the Aiven for Kafka service. 

- `PROJECT_NAME` The Aiven project your service will belong to
- `SERVICE_NAME` Give the service a name
- `CLOUD` The cloud and region you wish to deploy in
- `PLAN` The size (nodes, CPU, RAM, disk) of your Kafka cluster

```
PROJECT_NAME=my-project-name
SERVICE_NAME=my-kafka-service
CLOUD=google-us-west1
PLAN=business-4
```

Create the service, download the user credentials and configure a test topic "my-secrets"
```
avn service create \
  --project $PROJECT_NAME \
  --service-type kafka \
  --plan $PLAN \
  --cloud $CLOUD \
  --no-project-vpc \
  $SERVICE_NAME

# wait for the service to activate
avn service wait $SERVICE_NAME --project $PROJECT_NAME

# Store bootstrap server in env variable
export BOOTSTRAP_SERVER=$(avn service get --format '{service_uri}' $SERVICE_NAME)

# download the kafka certs for authentication
avn service user-kafka-java-creds \
  --project $PROJECT_NAME \
  --username avnadmin \
  $SERVICE_NAME
  
# Create the topic
avn service topic-create $SERVICE_NAME my-secrets \
  --partitions 2 \
  --replication 2
```
# Run the scripts
```
# Run producer
python aes_producer.py

# Run consumer to verify data is retrived and decrpyted
python aes_consumer.py
```