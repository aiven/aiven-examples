# clickhouse-cdc

### PostgreSQL® -> Debezium ->  Apache Kafka® -> ClickHouse®
This demo showcases a solution for real-time data integration and analytics using PostgreSQL, Debezium, Apache Kafka, and ClickHouse. The workflow involves capturing changes (supports insert, update and delete) from a PostgreSQL source table, streaming the changes into Kafka using Debezium, integrating Kafka topics into ClickHouse via ClickHouse Kafka Engine, and finally, leveraging ClickHouse's **ReplacingMergeTree** engine with **Materialized View** to isolate and efficiently manage data for different regions.


## Requirements

- `avn`
- `jq`
- `terraform`
- `clickhouse`
- `psql`


## Steps

- Update the `PROJECT` and `SERVICE` in `lab.env`

Run the following to setup required services and download clickhouse CLI.

```bash
cd terraform && terraform apply && cd ..
./lab.sh setup
```

Run the following to create clickhouse databases, tables materialized views and load sample data into postgres.

```bash
./lab.sh reset
```

Run the following to delete all the resources created in this demo.

```bash
./lab.sh teardown
```

## References

- [Create a Debezium source connector from PostgreSQL® to Apache Kafka®](https://docs.aiven.io/docs/products/kafka/kafka-connect/howto/debezium-source-connector-pg)
- [Connect Apache Kafka® to Aiven for ClickHouse®](https://docs.aiven.io/docs/products/clickhouse/howto/integrate-kafka)
- [Create materialized views in ClickHouse®](https://docs.aiven.io/docs/products/clickhouse/howto/materialized-views)
- [Change Data Capture (CDC) with PostgreSQL and ClickHouse - Part 1](https://clickhouse.com/blog/clickhouse-postgresql-change-data-capture-cdc-part-1)
- [Change Data Capture (CDC) with PostgreSQL and ClickHouse - Part 2](https://clickhouse.com/blog/clickhouse-postgresql-change-data-capture-cdc-part-2)
- [Materialized views in Aiven for ClickHouse® optimize queries for speed and freshness](https://aiven.io/blog/materialized-views-in-aiven-for-clickhouse)
- [ClickHouse® Kafka Engine](https://clickhouse.com/docs/en/engines/table-engines/integrations/kafka)
- [ClickHouse® ReplacingMergeTree Engine](https://clickhouse.com/docs/en/engines/table-engines/mergetree-family/replacingmergetree)