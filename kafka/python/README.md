### Kafka Python Example

This example uses the [kafka-python](https://github.com/dpkp/kafka-python) library to interact with Kafka both as a producer of messages and a consumer. 

#### Installing Dependencies  

```
pip install kafka-python
```

### Running The Example
Note: You can find the connection details in the "Overview" tab in the Aiven Console.

1. Use the [Aiven Client](https://github.com/aiven/aiven-client) to create a topic in your Kafka cluster:
    ```
    avn service topic-create <kafka-service-name>  python_example_topic --partitions 3 --replication 3
    ```
2. Produce some messages:
    ```
    ./main.py --service-uri <host>:<port> --ca-path <ca.pem path> --key-path <service.key path>  --cert-path <service.cert path>  --producer
    ```
3. Consume some messages:
    ```
    ./main.py --service-uri <host>:<port> --ca-path <ca.pem path> --key-path <service.key path>  --cert-path <service.cert path>  --consumer
    ```
