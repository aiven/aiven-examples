# Flink Stock Data Demo

This demo uses Aiven Flink and Kafka to simulate processing stock data.

## Requirement

- `avn`
- `jq`
- `python3`
- `terraform`

## Usage

- run terraform to create `stockdata-kafka` and `stockdata-flink` services in aiven console under the project you created.

```bash
terraform init
terraform plan
terraform apply"
```

- after terraform completed successfully, the follwing would be in `stockdata-flink`

* `flinkdemo-flink`: flink job to prcoess stock data
* `stock_source` : source table for data feeded from kafka `source_topic`
* `stock_sink`: target table for flink processed data into kafka `sink_topic`

- install the following demo code in virtualenv:

```bash
python3 -m venv venv
. venv/bin/activate
pip install -r requirements.txt
```

- download `ca.pem` `service.cert` `service.key` into `src/` from `flinkdemo-kafka`
```
./lab.sh setup
```

- Go to aiven console, stockdata-flink service -> Applications -> stock-data -> Create deployment

- open two terminals to send messages to kafka `source_topic` and consume messages from `sink_topic`.
  these are running in an infinite loop, press `ctrl` + `c` to stop at anytime.

- send stock messages to kafka producer `source_topic`

```
./lab.sh producer
```

example output:

```
{"symbol": "M3", "bid_price": 19.84, "ask_price": 20.47, "time_stamp": 1637977974214}
{"symbol": "M3", "bid_price": 19.44, "ask_price": 18.0, "time_stamp": 1637977974238}
{"symbol": "KAFKA", "bid_price": 893.83, "ask_price": 893.43, "time_stamp": 1637977974263}
{"symbol": "AVN", "bid_price": 1000.3, "ask_price": 1001.32, "time_stamp": 1637977976790}
{"symbol": "MYSQL", "bid_price": 670.12, "ask_price": 668.68, "time_stamp": 1637977976817}
{"symbol": "CQL", "bid_price": 20.59, "ask_price": 21.28, "time_stamp": 1637977976842}
{"symbol": "M3", "bid_price": 16.62, "ask_price": 17.55, "time_stamp": 1637977976865}
{"symbol": "REDIS", "bid_price": 15.07, "ask_price": 13.88, "time_stamp": 1637977976892}
{"symbol": "KAFKA", "bid_price": 894.48, "ask_price": 893.7, "time_stamp": 1637977976919}
{"symbol": "PSQL", "bid_price": 789.06, "ask_price": 789.97, "time_stamp": 1637977976943}
{"symbol": "PSQL", "bid_price": 791.44, "ask_price": 792.09, "time_stamp": 1637977976968}
{"symbol": "KAFKA", "bid_price": 892.75, "ask_price": 891.81, "time_stamp": 1637977976995}
{"symbol": "M3", "bid_price": 16.89, "ask_price": 15.46, "time_stamp": 1637977977021}
{"symbol": "KAFKA", "bid_price": 891.25, "ask_price": 891.75, "time_stamp": 1637977977046}
{"symbol": "MYSQL", "bid_price": 667.94, "ask_price": 669.31, "time_stamp": 1637977977072}
{"symbol": "PSQL", "bid_price": 792.25, "ask_price": 793.62, "time_stamp": 1637977977096}
{"symbol": "INFLUX", "bid_price": 24.43, "ask_price": 24.79, "time_stamp": 1637977977124}
{"symbol": "REDIS", "bid_price": 12.87, "ask_price": 12.57, "time_stamp": 1637977977150}
{"symbol": "REDIS", "bid_price": 13.33, "ask_price": 12.26, "time_stamp": 1637977977178}
{"symbol": "REDIS", "bid_price": 11.54, "ask_price": 11.29, "time_stamp": 1637977979703}
{"symbol": "OS", "bid_price": 9.49, "ask_price": 10.3, "time_stamp": 1637977979731}
{"symbol": "INFLUX", "bid_price": 24.44, "ask_price": 24.27, "time_stamp": 1637977979757}
{"symbol": "CQL", "bid_price": 22.67, "ask_price": 21.61, "time_stamp": 1637977979788}
{"symbol": "OS", "bid_price": 10.09, "ask_price": 10.49, "time_stamp": 1637977979813}
{"symbol": "CQL", "bid_price": 22.06, "ask_price": 21.28, "time_stamp": 1637977979839}
{"symbol": "MYSQL", "bid_price": 670.94, "ask_price": 669.85, "time_stamp": 1637977979864}
{"symbol": "PSQL", "bid_price": 792.77, "ask_price": 792.24, "time_stamp": 1637977979889}
```

- consume messages from kafka consumer `sink_topic`

```
./lab.sh consumer
```

example output:

```
Received: b'{"symbol":"KAFKA","change_bid_price":0.07,"change_ask_price":2.81,"min_bid_price":887.95,"max_bid_price":888.02,"min_ask_price":886.55,"max_ask_price":889.36,"time_interval":0,"time_stamp":"2021-11-27 01:52:33.743"}'
Received: b'{"symbol":"AVN","change_bid_price":0.44,"change_ask_price":0.53,"min_bid_price":1001.21,"max_bid_price":1001.65,"min_ask_price":1000.78,"max_ask_price":1001.31,"time_interval":0,"time_stamp":"2021-11-27 01:52:33.744"}'
Received: b'{"symbol":"MYSQL","change_bid_price":0,"change_ask_price":0,"min_bid_price":667.55,"max_bid_price":667.55,"min_ask_price":668.37,"max_ask_price":668.37,"time_interval":0,"time_stamp":"2021-11-27 01:52:33.744"}'
Received: b'{"symbol":"PSQL","change_bid_price":0,"change_ask_price":0,"min_bid_price":777.12,"max_bid_price":777.12,"min_ask_price":778.09,"max_ask_price":778.09,"time_interval":0,"time_stamp":"2021-11-27 01:52:33.744"}'
Received: b'{"symbol":"INFLUX","change_bid_price":2.25,"change_ask_price":2.02,"min_bid_price":23.96,"max_bid_price":26.21,"min_ask_price":24.66,"max_ask_price":26.68,"time_interval":0,"time_stamp":"2021-11-27 01:52:33.744"}'
Received: b'{"symbol":"M3","change_bid_price":0,"change_ask_price":0,"min_bid_price":26.57,"max_bid_price":26.57,"min_ask_price":25.9,"max_ask_price":25.9,"time_interval":0,"time_stamp":"2021-11-27 01:52:33.744"}'
Received: b'{"symbol":"REDIS","change_bid_price":0,"change_ask_price":0,"min_bid_price":13.3,"max_bid_price":13.3,"min_ask_price":14.48,"max_ask_price":14.48,"time_interval":0,"time_stamp":"2021-11-27 01:52:33.745"}'
Received: b'{"symbol":"OS","change_bid_price":1.52,"change_ask_price":1.92,"min_bid_price":19.04,"max_bid_price":20.56,"min_ask_price":18.61,"max_ask_price":20.53,"time_interval":0,"time_stamp":"2021-11-27 01:52:33.745"}'
Received: b'{"symbol":"OS","change_bid_price":1.74,"change_ask_price":2.27,"min_bid_price":15.24,"max_bid_price":16.98,"min_ask_price":14.45,"max_ask_price":16.72,"time_interval":2,"time_stamp":"2021-11-27 01:52:42.358"}'
Received: b'{"symbol":"MYSQL","change_bid_price":1.43,"change_ask_price":1.08,"min_bid_price":667.17,"max_bid_price":668.6,"min_ask_price":666.92,"max_ask_price":668,"time_interval":3,"time_stamp":"2021-11-27 01:52:42.358"}'
Received: b'{"symbol":"REDIS","change_bid_price":2.7,"change_ask_price":4.31,"min_bid_price":12.98,"max_bid_price":15.68,"min_ask_price":11.55,"max_ask_price":15.86,"time_interval":3,"time_stamp":"2021-11-27 01:52:42.359"}'
Received: b'{"symbol":"M3","change_bid_price":1.85,"change_ask_price":3.38,"min_bid_price":24.4,"max_bid_price":26.25,"min_ask_price":23.83,"max_ask_price":27.21,"time_interval":6,"time_stamp":"2021-11-27 01:52:42.359"}'
Received: b'{"symbol":"CQL","change_bid_price":3.73,"change_ask_price":3.11,"min_bid_price":22.43,"max_bid_price":26.16,"min_ask_price":21.75,"max_ask_price":24.86,"time_interval":6,"time_stamp":"2021-11-27 01:52:42.357"}'
Received: b'{"symbol":"INFLUX","change_bid_price":4.43,"change_ask_price":3.7,"min_bid_price":23.67,"max_bid_price":28.1,"min_ask_price":23.45,"max_ask_price":27.15,"time_interval":5,"time_stamp":"2021-11-27 01:52:42.358"}'
Received: b'{"symbol":"KAFKA","change_bid_price":0.94,"change_ask_price":0.16,"min_bid_price":887.75,"max_bid_price":888.69,"min_ask_price":889.1,"max_ask_price":889.26,"time_interval":2,"time_stamp":"2021-11-27 01:52:42.358"}'
Received: b'{"symbol":"PSQL","change_bid_price":4.35,"change_ask_price":4.67,"min_bid_price":775.89,"max_bid_price":780.24,"min_ask_price":775.93,"max_ask_price":780.6,"time_interval":6,"time_stamp":"2021-11-27 01:52:42.358"}'
Received: b'{"symbol":"GRAFANA","change_bid_price":6.04,"change_ask_price":6.28,"min_bid_price":24.56,"max_bid_price":30.6,"min_ask_price":24.48,"max_ask_price":30.76,"time_interval":6,"time_stamp":"2021-11-27 01:52:42.359"}'
Received: b'{"symbol":"AVN","change_bid_price":4.23,"change_ask_price":3.86,"min_bid_price":999.49,"max_bid_price":1003.72,"min_ask_price":1000.24,"max_ask_price":1004.1,"time_interval":6,"time_stamp":"2021-11-27 01:52:42.359"}'
```

- Run ./lab.sh teardown to delete all the resources created from this demo. Note: this would cause terraform.tfstate out of sync which would have to be deleted after.

./lab.sh teardown