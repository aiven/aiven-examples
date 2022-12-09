#!/bin/sh

usage() {
    printf "Usage: ./build.sh PROJECT_NAME SERVICE_NAME\n" 1>&2;
    exit 1;
}

if [ "$#" -ne 2 ]; then
    usage;
fi

AVN_PROJECT=$1
AVN_SERVICE=$2

cd terraform
terraform init
terraform apply -var="aiven_project=${AVN_PROJECT}" -var="aiven_service=${AVN_SERVICE}"
cd ..

read -p "Press [enter] to download java certs and keystores"
avn service user-kafka-java-creds --username avnadmin --project $1 ${AVN_SERVICE}
echo "Generating kafaka.properties and schema.properties..."
./makeconf.sh ${AVN_SERVICE}

read -p "Press [enter] to download kafka-streams-examples"
git clone git@github.com:confluentinc/kafka-streams-examples.git

cp -p src/KafkaMusicExample.java kafka-streams-examples/src/main/java/io/confluent/examples/streams/interactivequeries/kafkamusic/
cp -p src/KafkaMusicExampleDriver.java kafka-streams-examples/src/main/java/io/confluent/examples/streams/interactivequeries/kafkamusic/

read -p "Press [enter] to build kafka-streams-examples"
cd kafka-streams-examples/ && mvn -DskipTests=true clean package && cd ..

JAR=$(find kafka-streams-examples/target/ -name "*standalone.jar")

echo "java -Dconfigkafka=./kafka.properties -Dconfigschema=./schema.properties -cp $JAR io.confluent.examples.streams.interactivequeries.kafkamusic.KafkaMusicExampleDriver" > producer.sh && chmod 755 producer.sh
echo "java -Dconfigkafka=./kafka.properties -Dconfigschema=./schema.properties -cp $JAR io.confluent.examples.streams.interactivequeries.kafkamusic.KafkaMusicExample 7070" > consumer.sh && chmod 755 consumer.sh
