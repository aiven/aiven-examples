# OpenSearch Example

This repo is intended to provide an example of how to populate an OpenSearch index with data.  There is also a Postman collection showing how common search logic can be accomplished with OpenSearch. 

## Requirements

- [Terraform CLI](https://developer.hashicorp.com/terraform/tutorials/aws-get-started/install-cli)
- Python 3.8+
- [Aiven CLI](https://docs.aiven.io/docs/tools/cli.html)
- Project created via Aiven Console or CLI for running services
- (Optional) [Postman v2.1](https://www.postman.com/downloads/)


## Steps
1. Run the setup.sh file to unzip the file ``` ./setup.sh ```


2. Run the provided terraform files to create an OpenSearch instance and a Kafka service we will use to add data from the csv file.
```
cd terraform
terraform init
terraform plan 
terraform apply -var=aiven_project="<project-name>"
```
You may encounter a permission error on the included avn-token.sh file.  To resolve yo umay need to run the following

```
chmod u+x avn-token.sh 
```

3.Run the following shell command to create connection between Opensearch and Kafka. As of 12/8/2022 there is a bug in the Aiven console which prevents setting the value converter field correctly. There may also be a way to make this work via terraform but will have to be added in future versions.
```
avn service connector create os_demo '{
    "name":"sink_product_json",
    "connector.class": "io.aiven.kafka.connect.opensearch.OpensearchSinkConnector",
    "topics": "products",
    "connection.url": <OPEN SEARCH URL>>,
    "connection.username": <OPEN SEARCH USERNAME>,
    "connection.password": <OPEN SEARCH PASSWORD>,
    "type.name": "products",
    "tasks.max":"1",
    "key.converter": "org.apache.kafka.connect.storage.StringConverter",
    "value.converter": "org.apache.kafka.connect.json.JsonConverter",
    "value.converter.schemas.enable": "false",
    "schema.ignore": "true"
}'
```
4. Download the certificate files for the Kafka service to enable connection from our python file.
```
cd src && ../../../solutions/scripts/save-certs.sh os_kafka
```
5. Update the config.py file with your Kafka service URI.  You can find value in the console, or you can run the following CLI command

```
$(avn service list --json ${AVN_KAFKA_SERVICE_NAME} | jq -r '.[].service_uri')
```

6. Start the kafka producer.  There are over 500k records in the file so this may take some time to complete.
```
python3 kafkaProducer.py
```
7.(Optional) There is a Postman collection in the postman folder showing some sample queries.

## Attribution
The data provided for this demo can be found [here](https://www.kaggle.com/datasets/thedevastator/product-prices-and-sizes-from-walmart-grocery?resource=download)
