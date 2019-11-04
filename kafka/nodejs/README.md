### Kafka node.js example

This example uses the [node-rdkafka](https://github.com/blizzard/node-rdkafka) library to connect to produce a message to kafka, and read it out again.


#### Installing Dependencies  
Note: this example requires node-rdkafka be compiled with ssl support, which is not the default. Consult the documentation from the project for more information - https://github.com/blizzard/node-rdkafka.
```
npm install
```

#### Running The Example
Note: You can find the connection details in the "Overview" tab in the Aiven Console.
```
node index.js --host <host:port> --key-path <key path> --cert-path <cert path> --ca-path <ca path>
```
