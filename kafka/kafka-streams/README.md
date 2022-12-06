# Kafka Streams Example

This is an example code uses Apache Kafka Streams with Aiven Kafka based on
[Use Apache Kafka® Streams with Aiven for Apache Kafka](https://docs.aiven.io/docs/products/kafka/howto/kafka-streams-with-aiven-for-kafka.html)

## Requirement

- `avn`
- `jq`
- `java`
- `mvn`
- `terraform`

## Usage

- create Aiven Kafka service and build the example code
  
  ```./build.sh PROJECT_NAME SERVICE_NAME```

- Open 3 terminals

- Run the applications
  First terminal
  
  ```./producer.sh```

  Second terminal
  
  ```./consumer.sh```

- Check the produced data
  Third terminal

  ```while [ 1 ]; do curl http://localhost:7070/kafka-music/charts/top-five | jq -c && sleep 1`; done```