## This folder contains examples used for OpenSearch course made by Aiven

### Data discovery with Kafka topic containing measurements values

To demonstrate data discovery based on measurements data

1. Create an OpenSearch cluster
2. Create an Apache Kafka cluster
3. Add a topic "measurements" to Kafka
4. Copy kcat.config.example, remove ".example" and set your Kafka connection details
5. Run the script measurements_generator.sh to add data to the topic
6. Create a Kafka OpenSearch connector and replciate the data to OpenSearch

Above steps can be done with setting project and services names in `lab.env` and run
```
./lab.sh up
```

To teardown these services and cleanup
```
./lab.sh down
```

### Search queries

For the building examples, find queries to setup mapping, data and run search requests in buildings.sh.
You can copy the content and past it in OpenSearch Dashboards Dev Tools and then select chunks one by one to run them.




