The project demonstrates how to read send/receive messages serialized/deserialized with Avro to/from Kafka

### Requirements
* Installed JDK 1.8+
* Configured JAVA_HOME

### Preparation
* In case of Linux/Mac `./mvnw clean verify`
* In case of Windows `mvnw clean verify`

### Get credentials
Download service `access_key`, `access_certificate` and `ca_certificate`.
```
openssl pkcs12 -export -inkey service.key -in service.cert -out client.keystore.p12 -name service_key -passout pass:mySSLKeyP@ssw0rd
keytool -import -file ca.pem -alias CA -keystore client.truststore.jks -storepass myTrustSt0reP@ssw0rd -noprompt
```
For detailed follow the instructions at https://developer.aiven.io/docs/products/kafka/howto/keystore-truststore 

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
             -srurl https://kafka-1690a57d-senu-dev-sandbox.aivencloud.com:12696 \
             -ts /path/to/client.truststore.jks \
             -tsp myTrustSt0reP@ssw0rd \
             -ks /path/to/client.keystore.p12 \
             -ksp myKeySt0reP@ssw0rd \
             -sslp myKeySt0reP@ssw0rd \
             -srp MySchem@RegistryP@ssw0rd \
             -sru avnadmin \
             -f FileWithData.csv \
             -t clickrecordTopic
```

### Receiving messages
An example of message consumption (for Windows use consumer.bat)
```
bin/consumer -bs kafka-1690a57d-senu-dev-sandbox.aivencloud.com:12693 \
             -srurl https://kafka-1690a57d-senu-dev-sandbox.aivencloud.com:12696 \
             -ts /path/to/client.truststore.jks \
             -tsp myTrustSt0reP@ssw0rd \
             -ks /path/to/client.keystore.p12 \
             -ksp myKeySt0reP@ssw0rd \
             -sslp myKeySt0reP@ssw0rd \
             -srp MySchem@RegistryP@ssw0rd \
             -sru avnadmin \
             -t clickrecordTopic
```