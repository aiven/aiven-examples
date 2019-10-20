### Cassandra Java Example

This example uses the [java-driver](https://github.com/datastax/java-driver) library to connect to Cassandra, create a keyspace and table, insert some rows, and read them out again.

#### Running The Example
Note: You can find the connection details in the "Overview" tab in the Aiven Console.
```
./gradlew -q run --args="--ca-path <path to project CA> --host <cassandra host>  --port <cassandra port> --password <cassandra password>"
```
