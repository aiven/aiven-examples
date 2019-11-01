### InfluxDB Go Example

This example uses the [influxdb1-client](https://github.com/influxdata/influxdb1-client) library to connect to InfluxDB, write some data points, and read them out again.

#### Installing Dependencies  

```
go get -u github.com/influxdata/influxdb1-client/v2
```

### Compiling The Example Program

```
go build main.go influxdb_example.go
```

#### Running The Example
Note: You can find the connection details in the "Overview" tab in the Aiven Console.
```
./main --host https://<host>:<port> --password <password>
```
