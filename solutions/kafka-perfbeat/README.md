# kafka-perfbeat

This script uses `kafka-producer-perf-test.sh` and `kafka-consumer-perf-test.sh` from Apache Kafka distribution to send producer and consumer metrics to Datadog.
It creates a topic `kafka.auto_create_topics_enable` with replication factor = (# of nodes - 1) to replicate data to all nodes in the cluster, 
then produces records with `acks=al` to capture perfmance metrics and detect any issues to in-sync replicas in every other nodes.

## Requirement

- `../scripts/dd-custom-metric.sh` is requied for sending custom metrics to Datadog
- `avn` CLI
- `jq`
- `java`
- kafka release from [here](https://kafka.apache.org/downloads)
- 1 Kafka service running on Aiven with `kafka.auto_create_topics_enable` enabled.

## Usage

Replace corresponding project, service names and set desired values in `kafka-perfbeat.env`

```bash
./kafka-perfbeat.sh producer
```

```bash
./kafka-perfbeat.sh consumer
```