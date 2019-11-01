### Kafka Go Example

This example uses the [sarama](https://github.com/Shopify/sarama) library to interact with Kafka both as a producer of messages and a consumer. 

#### Installing Dependencies  

```
go get github.com/Shopify/sarama
```

### Compiling The Example Program

```
go build main.go producer_example.go client.go consumer_example.go
```

### Running The Example
Note: You can find the connection details in the "Overview" tab in the Aiven Console.

1. Use the [Aiven Client](https://github.com/aiven/aiven-client) to create a topic in your Kafka cluster:
    ```
    avn service topic-create <kafka-service-name>  go_example_topic --partitions 3 --replication 3
    ```
2. Open two shells. In the first, create a consumer:
    ```
    ./main --service-uri <host>:<port> --ca-path <ca.pem path> --key-path <service.key path>  --cert-path <service.cert path>  --consumer
    ```
3. Once you see the message "Ready to consume messages", execute the producer in the second shell:
    ```
    ./main --service-uri <host>:<port> --ca-path <ca.pem path> --key-path <service.key path>  --cert-path <service.cert path>  --producer
    ```