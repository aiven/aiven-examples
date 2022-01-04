The project demonstrates how to read messages from the `heartbeats` topic produced by Kafka MirrorMaker 2.

## Install
You must have Java and Maven installed. The code is tested with Java 11.

### Install dependencies
```
mvn install && mvn clean package
```

### Get credentials

You can use [`avn` CLI tool](https://aiven.io/blog/command-line-magic-with-the-aiven-cli) to get Java credentials. In your terminal go to `certs` directory, and from there run (**please use a strong password**):
```
avn service user-kafka-java-creds --username avnadmin -p VERYSECRETPASSWORD SERVICE_NAME
```
This should download all the required certificate files in the `certs` directory:
```
ca.pem
client.keystore.p12
client.properties
client.truststore.jks
service.cert
service.key
```

Alternativly, you can download the CA and client keys for Kafka from the web console, then run:

```
openssl pkcs12 -export -inkey service.key -in service.cert -out client.keystore.p12 -name service_key
keytool -import -file ca.pem -alias CA -keystore client.truststore.jks 
```

### Configure the app

Update `App.java` with your configuration by searching for the comments `// CHANGE BASED ON YOUR SETUP`

## Dev environment
Repo is preconfigured for development in [VSCode](https://code.visualstudio.com/) with [Debugger for Java](https://marketplace.visualstudio.com/items?itemName=vscjava.vscode-java-debug) extension.
