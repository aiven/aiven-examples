### InfluxDB Python Example

This example uses the [influxdb](https://github.com/influxdata/influxdb-python) library to connect to InfluxDB, write some data points, and read them out again.

#### Installing Dependencies  

```
pip install influxdb
```

#### Running The Example
Note: You can find the connection details in the "Overview" tab in the Aiven Console.
```
./main.py --url https+influxdb://<username>:<password>@<host>:<port>/<database>
```
