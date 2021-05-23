### M3DB PHP Example

This example uses the [influxdb](https://github.com/influxdata/influxdb-php) library to connect to M3DB and write a data point.

#### Pre-Requisites

An M3DB service that you can connect to.

The PHP InfluxDB library (for InfluxDB v1, beware of the newer package with a similar-but-different name for Influx v2), which is included in `composer.json` so just run:

```
composer install
```

#### Running The Example

The parameters you will need are:

* host
* port
* user
* password

With all those values ready, run the command:

```
php m3_write --host <host> --port <port> --user <user> --password <password>
```

If it worked, you should see the output `bool(true)`.

#### Inspecting The Data

Congratulations, you have written data to M3DB. To see it, add a Grafana integration if you haven't already, and choose the data field `php_example_metric` to see what you sent. Feel free to edit the script to send more different data points too.
