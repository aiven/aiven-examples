The project demonstrates how to read send/receive messages serialized/deserialized with Avro to/from Kafka

### Requirements
* Installed JDK 1.8+
* Configured JAVA_HOME

### Preparation
* In case of Linux/Mac `./mvnw clean verify`
* In case of Windows `mvnw clean verify`

### Get credentials
Follow the instructions at https://developer.aiven.io/docs/products/kafka/howto/keystore-truststore 

### List of available flags

List of arguments 
```
-bootstrap, -bs                  A list of host/port pairs to use for establishing the initial connection to the Kafka cluster
-schemaregistryurl, -srurl       Schema registry url
-schemaregistryuser, -sru        Schema registry user
-schemaregistrypassword, -srp    Schema registry user
-sslkeypassword, -sslp           The password of the private key in the key store file
-keystore, -ks                   The location of the key store file
-keystorepassword, -ksp          The store password for the key store file
-truststore, -ts                 The location of the trust store file
-truststorepassword, -tsp        The password for the trust store file
-f                               Semicolon separated file with data (Optional)
-t                               Kafka topic
```

### Sending messages
An example of message producing (for Windows use producer.bat)
```
bin/producer -bs kafka-1690a57d-senu-dev-sandbox.aivencloud.com:12693 \
             -ksp myKeySt0reP@ssw0rd \
             -srurl https://kafka-1690a57d-senu-dev-sandbox.aivencloud.com:12696 \
             -ts /path/to/client.truststore.jks \
             -tsp myTrustSt0reP@ssw0rd \
             -ks /path/to/client.keystore.p12 \
             -srp MySchem@RegistryP@ssw0rd \
             -sru avnadmin \
             -sslp mySSLKeyP@ssw0rd \
             -f FileWithData.csv \
             -t clickrecordTopic
```

### Receiving messages
An example of message consumption (for Windows use consumer.bat)
```
bin/consumer -bs kafka-1690a57d-senu-dev-sandbox.aivencloud.com:12693 \
             -ksp myKeySt0reP@ssw0rd \
             -srurl https://kafka-1690a57d-senu-dev-sandbox.aivencloud.com:12696 \
             -ts /path/to/client.truststore.jks \
             -tsp myTrustSt0reP@ssw0rd \
             -ks /path/to/client.keystore.p12 \
             -srp MySchem@RegistryP@ssw0rd \
             -sru avnadmin \
             -sslp mySSLKeyP@ssw0rd \
             -t clickrecordTopic
```