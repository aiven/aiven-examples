### M3DB Python Example

This example uses the [influxdb](https://github.com/influxdata/influxdb-python) library to connect to M3DB and write some data points.

#### Pre-Requisites

This python script requires the InfluxDB package (M3 uses InfluxDB line protocol), which you can install with:

```
pip install influxdb
```

You will need an API auth token, available from your [Aiven console user settings](https://console.aiven.io/profile/auth), stored in an environment variable called `AIVEN_AUTH_TOKEN`.

You should have both an M3 and an M3 Aggregator service running.

#### Running The Example

The parameters you will need are:

* The name of the project your services are in
* The service names of both the M3 and M3 Aggregator services

For the M3 service itself, check the "overview" tab for the credentials needed:

* host
* port
* user
* password

With all those values ready, run the command:

```
./main.py --project <project_name> --m3db <m3 service name> --m3aggregator <m3 aggregator service name> --host <host> --port <port> --user <user> --password <password>
```

If it worked, you should see the output `True`.

#### Inspecting The Data

Congratulations, you have written data to M3DB. To see it, add a Grafana integration if you haven't already, and choose the data field `cpu_load_short_value` to see what you sent. Feel free to edit the script to send more different data points too.
