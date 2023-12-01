# Kafka Modern C++ Example

This example uses the [modern-cpp-kafka](https://github.com/morganstanley/modern-cpp-kafka) library to connect to Kafka produce and consume messages.

## Requirement

- `avn` 
- `cmake`
- `libkafka`
- `rapidjson`

## Steps

- Update the `PROJECT` and `SERVICE` in `ccexample.env`

| Tables                   | Description                 |
| ------------------------ |:---------------------------:|
| PROJECT                  | project name                |
| SERVICE                  | service name                |
| KAFKA_BROKER_LIST        | kafka service URI           |  
| KAFKA_TOPIC              | test topic name             |
| SECURITY_PROTOCOL        | security protocol           |
| SSL_CA_LOCATION          | path to ca file             |
| SSL_CERTIFICATE_LOCATION | path to certificate file    |
| SSL_KEY_LOCATION         | path to key file            |


- Run `./ccexample.sh setup`, this would create a kafka service and auto populate service URI into `ccexample.env`
```
./autoscale.sh setup
```

- Run `./ccexample.sh consumer`, this sets the environment variables required and runs `./avn_KafkaConsumer_Simple`.  This process does not exit until `CTRL + C`, *please keep this process and terminal running.*
```
./ccexample.sh consumer
```

- Open another terminal to run `./ccexample.sh producer`, this sets the environment variables required and runs `./avn_KafkaProducer_Simple`.  Any messages entered with [ENTER] becomes a message record to the topic and it will be consumed and displayed in the consumer terminal.
```
./ccexample.sh producer
```

- Run `./ccexample.sh teardown` to delete all the resources created from this example.
```
./ccexample.sh teardown
```

