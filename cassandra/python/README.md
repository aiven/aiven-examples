### Cassandra Python Example

This example uses the [cassandra-driver](https://pypi.org/project/cassandra-driver/) library to connect as the `avnadmin` user, create a keyspace and table, insert some rows, and read them out again.

#### Installing Dependencies  

```
pip install cassandra-driver
```

#### Running The Example
Note: You can find the connection details in the "Overview" tab in the Aiven Console.
```
./main.py --host cassandra-project.aivencloud.com --port <cassandra port> --password <cassandra password> --ca-path <path to ca.pem>
```