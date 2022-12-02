#!/bin/sh

AVN_PROJECT=$1

cd terraform
terraform init
terraform apply -var="aiven_project=${AVN_PROJECT}"
cd ..

read -p "Press [enter] to download java certs and keystores"
avn service user-kafka-java-creds --username avnadmin --project $1 kafka-streams

read -p "Press [enter] to download kafka-streams-examples"
git clone git@github.com:confluentinc/kafka-streams-examples.git

cp -p src/KafkaMusicExample.java kafka-streams-examples/src/main/java/io/confluent/examples/streams/interactivequeries/kafkamusic/
cp -p src/KafkaMusicExampleDriver.java kafka-streams-examples/src/main/java/io/confluent/examples/streams/interactivequeries/kafkamusic/

read -p "Press [enter] to build kafka-streams-examples"
cd kafka-streams-examples/
mvn -DskipTests=true clean package


