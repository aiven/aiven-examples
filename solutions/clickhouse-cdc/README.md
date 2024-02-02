# clickhouse-cdc

**PostgreSQL® -> Debezium ->  Apache Kafka® -> ClickHouse®**
This demo showcases a solution for real-time data integration and analytics using PostgreSQL, Debezium, Apache Kafka, and ClickHouse. The workflow involves capturing changes (supports insert, update and delete) from a PostgreSQL source table, streaming the changes into Kafka using Debezium, integrating Kafka topics into ClickHouse via ClickHouse Kafka Engine, and finally, leveraging ClickHouse's **ReplacingMergeTree** engine with **Materialized View** to isolate and efficiently manage data for different regions.


## Requirements

- `avn`
- `jq`
- `terraform`
- `clickhouse`
- `psql`


## Steps

- Update the `PROJECT` and `SERVICE` in `lab.env`

Run the following to setup required services and download `clickhouse` CLI.

```bash
cd terraform && terraform apply && cd ..
./lab.sh setup
```

Run the following to create clickhouse databases, tables materialized views and load sample data into postgres.  This step would create `mv-${ROLE}.sql` for creating materizled views in ClickHouse.

```bash
./lab.sh reset
```

Run the following to delete all the resources created in this demo.

```bash
./lab.sh teardown
```

## Successful Demo Run

### Run terraform to setup services

```bash
cd terraform && terraform apply && cd ..
data.external.env: Reading...
. . .
Plan: 6 to add, 0 to change, 0 to destroy.

Do you want to perform these actions?
  Terraform will perform the actions described above.
  Only 'yes' will be accepted to approve.

  Enter a value: yes

aiven_clickhouse.clickhouse: Creating...
aiven_pg.pg: Creating...
aiven_kafka.kafka: Creating...
. . .
Apply complete! Resources: 6 added, 0 changed, 0 destroyed.

```

### Configure security and setup databases and tables

```bash
./lab.sh setup
Downloaded to directory '.': CA certificate, certificate, key

✅ certificates and keys downloaded from cdc-kafka

cdc-kafka-felixwu-demo.a.aivencloud.com:24949
✅ kcat.config setup completed

ERROR:  database "middleearth" already exists
You are now connected to database "middleearth" as user "avnadmin".
CREATE TABLE
CREATE TABLE
ALTER TABLE
ALTER TABLE
✅ pg_tables.sql imported into postgres cdc-pg
. . .
Processed rows: 1
```

### Reset all test data and re-populate 10 rows of random data

```bash
./lab.sh reset
Reset all test data in postgres cdc-pg and clickhouse cdc-clickhouse...You are now connected to database "middleearth" as user "avnadmin".
. . .
✅ rivendell created in clickhouse cdc-clickhouse
✅  mv-rivendell.sql created successfully.
. . .
✅ shire created in clickhouse cdc-clickhouse
✅  mv-shire.sql created successfully.
. . .
Generating 10 entries...
\c middleearth;
INSERT INTO population (region, total) VALUES (11, 1493);
. . .
INSERT INTO weather (region, temperature) VALUES (11, 35.82);
. . .
INSERT 0 1
```

### Use kcat to watch Debezium CDC into Kafka topic

```bash
kcat -F kcat.config -t middleearth-replicator.public.population
% Reading configuration from file kcat.config
% Auto-selecting Consumer mode (use -P or -C to override)
{"before.id":0,"before.region":null,"before.total":null,"after.id":1,"after.region":11,"after.total":1493,"source.version":"1.9.7.aiven","source.connector":"postgresql","source.name":"middleearth-replicator","source.ts_ms":1706573591899,"source.snapshot":"true","source.db":"middleearth","source.sequence":"[null,\"150998520\"]","source.schema":"public","source.table":"population","source.txId":913,"source.lsn":150998520,"source.xmin":null,"op":"r","ts_ms":1706573592198,"transaction.id":null,"transaction.total_order":null,"transaction.data_collection_order":null}
. . .
% Reached end of topic middleearth-replicator.public.population [2] at offset 5
```

### Check test data has been loaded into PostgreSQL®

```bash
./lab.sh psql
. . .
defaultdb=> \c middleearth;
middleearth=> \dt
           List of relations
 Schema |    Name    | Type  |  Owner   
--------+------------+-------+----------
 public | population | table | avnadmin
 public | weather    | table | avnadmin
(2 rows)

middleearth=> select * from weather;
 id | region | temperature 
----+--------+-------------
  1 |     11 |       35.82
  2 |     10 |       42.12
  3 |     11 |       10.28
  4 |     10 |       42.38
  5 |     11 |       -9.75
  6 |     10 |        25.8
  7 |     10 |       16.16
  8 |     11 |      -17.82
  9 |     11 |        8.92
 10 |     10 |        2.42
(10 rows)

middleearth=> select * from population;
 id | region | total 
----+--------+-------
  1 |     11 |  1493
  2 |     10 |   174
  3 |     11 |  1160
  4 |     10 |  1127
  5 |     11 |  1103
  6 |     10 |  1264
  7 |     10 |  1529
  8 |     11 |  1386
  9 |     11 |  1442
 10 |     10 |  1912
(10 rows)
```

### Check test data has been synced into ClickHouse®

```bash
./lab.sh clickhouse
. . .
cdc-clickhouse-1 :) show databases;
SHOW DATABASES
Query id: f2bea58f-70b5-4085-99dc-ea0d4ecf6fff
┌─name───────────────┐
│ INFORMATION_SCHEMA │
│ default            │
│ information_schema │
│ rivendell          │
│ service_cdc-kafka  │
│ shire              │
│ system             │
└────────────────────┘
7 rows in set. Elapsed: 0.001 sec. 

cdc-clickhouse-1 :) select * from `shire`.weather final order by id;
. . .
┌─id─┬──────────────────────ts─┬─region─┬─temperature─┬───version─┬─deleted─┐
│  1 │ 2024-01-30 00:13:12.224 │     11 │       35.82 │ 150998520 │       0 │
│  3 │ 2024-01-30 00:13:12.225 │     11 │       10.28 │ 150998520 │       0 │
│  5 │ 2024-01-30 00:13:12.225 │     11 │       -9.75 │ 150998520 │       0 │
│  8 │ 2024-01-30 00:13:12.228 │     11 │      -17.82 │ 150998520 │       0 │
│  9 │ 2024-01-30 00:13:12.228 │     11 │        8.92 │ 150998520 │       0 │
└────┴─────────────────────────┴────────┴─────────────┴───────────┴─────────┘
5 rows in set. Elapsed: 0.002 sec. 

cdc-clickhouse-1 :) select * from `rivendell`.weather final order by id;
. . .
┌─id─┬──────────────────────ts─┬─region─┬─temperature─┬───version─┬─deleted─┐
│  2 │ 2024-01-30 00:13:12.225 │     10 │       42.12 │ 150998520 │       0 │
│  4 │ 2024-01-30 00:13:12.225 │     10 │       42.38 │ 150998520 │       0 │
│  6 │ 2024-01-30 00:13:12.227 │     10 │        25.8 │ 150998520 │       0 │
│  7 │ 2024-01-30 00:13:12.228 │     10 │       16.16 │ 150998520 │       0 │
│ 10 │ 2024-01-30 00:13:12.228 │     10 │        2.42 │ 150998520 │       0 │
└────┴─────────────────────────┴────────┴─────────────┴───────────┴─────────┘
5 rows in set. Elapsed: 0.002 sec. 
```

### Test UPDATE from PostgreSQL®

```bash
middleearth=> update weather set temperature=99.99 where id > 3;
UPDATE 7
```

### Validate updated values are in ClickHouse®

```bash
cdc-clickhouse-1 :) select * from `shire`.weather final order by id;
. . .
┌─id─┬──────────────────────ts─┬─region─┬─temperature─┬───version─┬─deleted─┐
│  1 │ 2024-01-30 00:13:12.224 │     11 │       35.82 │ 150998520 │       0 │
│  3 │ 2024-01-30 00:13:12.225 │     11 │       10.28 │ 150998520 │       0 │
│  5 │ 2024-01-30 00:31:39.817 │     11 │       99.99 │ 201328456 │       0 │
│  8 │ 2024-01-30 00:31:39.818 │     11 │       99.99 │ 201328768 │       0 │
│  9 │ 2024-01-30 00:31:39.818 │     11 │       99.99 │ 201328872 │       0 │
└────┴─────────────────────────┴────────┴─────────────┴───────────┴─────────┘

5 rows in set. Elapsed: 0.003 sec. 

cdc-clickhouse-1 :) select * from `rivendell`.weather final order by id;
. . .
┌─id─┬──────────────────────ts─┬─region─┬─temperature─┬───version─┬─deleted─┐
│  2 │ 2024-01-30 00:13:12.225 │     10 │       42.12 │ 150998520 │       0 │
│  4 │ 2024-01-30 00:31:39.816 │     10 │       99.99 │ 201328352 │       0 │
│  6 │ 2024-01-30 00:31:39.817 │     10 │       99.99 │ 201328560 │       0 │
│  7 │ 2024-01-30 00:31:39.818 │     10 │       99.99 │ 201328664 │       0 │
│ 10 │ 2024-01-30 00:31:39.819 │     10 │       99.99 │ 201328976 │       0 │
└────┴─────────────────────────┴────────┴─────────────┴───────────┴─────────┘
5 rows in set. Elapsed: 0.002 sec. 
```

### Test DELETE from PostgreSQL®

```bash
middleearth=> delete from weather where id > 3;
DELETE 7
```

### Validate deleted values are no longer in ClickHouse®

```bash
cdc-clickhouse-1 :) select * from `shire`.weather final order by id;
. . .
┌─id─┬──────────────────────ts─┬─region─┬─temperature─┬───version─┬─deleted─┐
│  1 │ 2024-01-30 00:13:12.224 │     11 │       35.82 │ 150998520 │       0 │
│  3 │ 2024-01-30 00:13:12.225 │     11 │       10.28 │ 150998520 │       0 │
└────┴─────────────────────────┴────────┴─────────────┴───────────┴─────────┘
2 rows in set. Elapsed: 0.002 sec. 

cdc-clickhouse-1 :) select * from `rivendell`.weather final order by id;
. . .
┌─id─┬──────────────────────ts─┬─region─┬─temperature─┬───version─┬─deleted─┐
│  2 │ 2024-01-30 00:13:12.225 │     10 │       42.12 │ 150998520 │       0 │
└────┴─────────────────────────┴────────┴─────────────┴───────────┴─────────┘
1 row in set. Elapsed: 0.002 sec. 
```

### Validate users only have permission to assigned database in ClickHouse®

```bash
./clickhouse client --user sam --host **********.a.aivencloud.com --port 24947 --secure
Connecting to **********..a.aivencloud.com:24947 as user sam.
. . .
cdc-clickhouse-1 :) show databases;
. . .
┌─name──┐
│ shire │
└───────┘
1 row in set. Elapsed: 0.001 sec. 
cdc-clickhouse-1 :) select * from `shire`.weather final order by id;
. . .
┌─id─┬──────────────────────ts─┬─region─┬─temperature─┬───version─┬─deleted─┐
│  1 │ 2024-01-30 00:13:12.224 │     11 │       35.82 │ 150998520 │       0 │
│  3 │ 2024-01-30 00:13:12.225 │     11 │       10.28 │ 150998520 │       0 │
└────┴─────────────────────────┴────────┴─────────────┴───────────┴─────────┘
2 rows in set. Elapsed: 0.002 sec. 
cdc-clickhouse-1 :) select * from `rivendell`.weather final order by id;
. . .
Received exception from server (version 23.8.8):
Code: 497. DB::Exception: Received from **********.a.aivencloud.com:24947. DB::Exception: sam: Not enough privileges. To execute this query, it's necessary to have the grant SELECT(id, ts, region, temperature, version, deleted) ON rivendell.weather. (ACCESS_DENIED)
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