# kafka-perfbeat

This is a helper script uses `kafka-producer-perf-test.sh` and `kafka-consumer-perf-test.sh` from Apache Kafka distribution to send metrics to Datadog

## Requirement

- `avn` CLI
- `jq`
- 1 Kafka service running on Aiven


### 

```bash
./kafka-perfbeat.sh producer
```

```bash
./kafka-perfbeat.sh consumer
```
