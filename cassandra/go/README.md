### Cassandra Go Example

This example uses the [gocql](https://godoc.org/github.com/gocql/gocql) library to connect as the `avnadmin` user, create a keyspace and table, insert some rows, and read them out again.

#### Installing Dependencies  

```
go get github.com/gocql/gocql
```

### Compiling The Example Program

```
go build main.go cassandra_example.go
```

#### Running The Example
Note: You can find the connection details in the "Overview" tab in the Aiven Console.
```
./main -host cassandra-project.aivencloud.com -port <cassandra port> -password <cassandra password> -ca-path <path to ca.pem>
```
