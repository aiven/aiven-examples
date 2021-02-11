### M3DB Go Examples

This directory contains two sample programs for using the M3 database. `m3_write.go` writes
some test metric data to M3's Prometheus write API, using the prometheus remote golang client.
`m3_query.go` reads out a range of recent metrics using the query API.

#### Installing Dependencies

```
go get -u github.com/golang/snappy
go get -u github.com/gogo/protobuf/gogoproto
go get -u github.com/m3db/prometheus_remote_client_golang/promremote
```

### Compiling The Example Programs

```
go build m3_write.go args.go
go build m3_query.go args.go
```

or, if `make` is available, you can just run

```
make
```

#### Running The Examples

```
./m3_write -address https:/<user>:<password>@<host>:<port>/api/v1/prom/remote/write -metric-name my_test_metric
```

The full URL for the Prometheus write endpoint for `-address` can be found in the Aiven console, in
tab 'Prometheus (write)' of the service view.

After writing some metric data with m3_write, you can query it from the coordinator
using the URL in the `M3 Coordinator` tab:

```
./m3_query -address https://<user>:<password>@<host>:<port> -metric-name my_test_metric
```

This queries a one hour range of most recent metric data with one minute granularity,
and prints the JSON response.
