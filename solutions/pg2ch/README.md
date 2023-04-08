# pg2ch

This script copies all tables from PostgreSQL database to ClickHouse database on Aiven.

## Requirement

- `avn` CLI
- `clickhouse` client
- `jq`
- You need to have 1 PostgreSQL and 1 Clickhouse services running on Aiven

## Steps

- Install clickhouse client

```curl https://clickhouse.com/ | sh```

- Update the following values in `pg2ch.env` to the databases to be copied

| Tables    | Description              |
| --------- |:------------------------:|
| PG_SVC    | PostgreSQL service name  |
| PG_DB     | PostgreSQL database name |
| PG_SCHEMA | PostgreSQL schema name   |
| CH_SVC    | ClickHouse service name  |
| CH_DB     | ClickHouse database name |


*Please note if there is an existing integration between the specified PostgreSQL and ClickHouse, it will be disconnected and reconnected with the database defined in `pg2ch.env`*

- Run the `./pg2ch.sh` script, it would create SQL files to CREATE, INSERT all the tables from PostgreSQL to ClickHouse.
```
./pg2ch.sh
```

- A cleanup script is generated to drop the generated ClickHouse tables when needed.
```
./${CH_SVC}-${CH_DB}-cleanup.sh
```

## Example Demo
- This is a demo on migrating a PostgreSQL (startup-4) table with 100,000,000 rows around 6.5GB of data to ClickHouse (startup-16), with optimized compression it reduced to 237.48 MiB.

- Please note the table schema codec compression for columns were manually optimized as the following.
References:
https://clickhouse.com/blog/optimize-clickhouse-codecs-compression-schema
https://clickhouse.com/docs/en/sql-reference/statements/create/table#specialized-codecs

```
┏━━━━━━━━━━━━━━━┳━━━━━━━━━━━━━━━━━━━━━━━━━┓
┃ column        ┃ codec                   ┃
┡━━━━━━━━━━━━━━━╇━━━━━━━━━━━━━━━━━━━━━━━━━┩
│ id            │ CODEC(Delta,ZSTD)       │
├───────────────┼─────────────────────────┤
│ temperature   │ CODEC(T64,ZSTD)         │
├───────────────┼─────────────────────────┤
│ elevation     │ CODEC(T64,ZSTD)         │
├───────────────┼─────────────────────────┤
│ precipitation │ CODEC(T64,ZSTD)         │
├───────────────┼─────────────────────────┤
│ snow          │ CODEC(T64,ZSTD)         │
├───────────────┼─────────────────────────┤
│ wind          │ CODEC(T64,ZSTD)         │
├───────────────┼─────────────────────────┤
│ timestamp     │ CODEC(DoubleDelta,ZSTD) │
└───────────────┴─────────────────────────┘
```

#### PostgreSQL
```
defaultdb=> \d weather;
                                          Table "public.weather"
    Column     |            Type             | Collation | Nullable |               Default
---------------+-----------------------------+-----------+----------+-------------------------------------
 id            | integer                     |           | not null | nextval('weather_id_seq'::regclass)
 temperature   | integer                     |           | not null |
 elevation     | bigint                      |           | not null |
 precipitation | integer                     |           |          |
 snow          | integer                     |           |          |
 wind          | integer                     |           |          |
 timestamp     | timestamp without time zone |           | not null |
Indexes:
    "weather_pkey" PRIMARY KEY, btree (id)
    
defaultdb=> \dt+;
                                     List of relations
 Schema |  Name   | Type  |  Owner   | Persistence | Access method |  Size   | Description
--------+---------+-------+----------+-------------+---------------+---------+-------------
 public | weather | table | avnadmin | permanent   | heap          | 6577 MB |
(1 row)

defaultdb=> select count(id) from weather;
   count
-----------
 100000000
(1 row)
```

#### Running `pg2ch.sh`
```
-- CH_CLI: ./clickhouse client --user avnadmin --password ****** --host clickhouse-target-******.aivencloud.com --port ***** --secure
-- CH_PGDB: service_pg-data_defaultdb_public
-- CH_SVC: clickhouse-target
-- SERVICE_INTEGRATION_ID: ***884f-****-4491-83e3-***********
Setting up service integration [c***884f-****-4491-83e3-***********] [pg-data.defaultdb.public] for [clickhouse-target.default] ...

Warning: [Nullable(Int32)] column detected in [weather.precipitation], null records may fail to be migrated.
Warning: [Nullable(Int32)] column detected in [weather.snow], null records may fail to be migrated.
Warning: [Nullable(Int32)] column detected in [weather.wind], null records may fail to be migrated.
Generated clickhouse-target_defaultdb_dump.sql, By default tables are ordered by the 1st column, please review and adjust for optimal performance.
Generated clickhouse-target_defaultdb_drop.sql

Press any key to load clickhouse-target_defaultdb_dump.sql to clickhouse-target.default or CTRL+C to stop

CREATE TABLE IF NOT EXISTS default.weather(`id` Int32 CODEC(Delta,ZSTD),`temperature` Int32 CODEC(T64,ZSTD),`elevation` Int64 CODEC(T64,ZSTD),`precipitation` Nullable(Int32) CODEC(T64,ZSTD),`snow` Nullable(Int32) CODEC(T64,ZSTD),`wind` Nullable(Int32) CODEC(T64,ZSTD),`ts` DateTime64(6) CODEC(DoubleDelta,ZSTD)) ENGINE = MergeTree() ORDER by id;
s_42214	clickhouse-target-2.felixwu-demo.aiven.local	OK	0	0
0.019
Processed rows: 1
CREATE TABLE IF NOT EXISTS default.weather_buffer AS default.weather ENGINE = Buffer(default, weather, 40, 10, 100, 10000, 1000000, 10000000, 100000000);
s_42214	clickhouse-target-2.felixwu-demo.aiven.local	OK	0	0
0.006
Processed rows: 1
INSERT INTO default.weather_buffer SELECT * FROM `service_pg-data_defaultdb_public`.`weather`
0 rows in set. Elapsed: 209.327 sec. Processed 100.00 million rows, 3.90 GB (477.72 thousand rows/s., 18.63 MB/s.)
Processed rows: 0


DROP TABLE IF EXISTS default.weather_buffer;
s_42214	clickhouse-target-2.felixwu-demo.aiven.local	OK	0	0
0.040
Processed rows: 1

┏━━━━━━━━━━┳━━━━━━━━━━━┳━━━━━━━━━━━━┳━━━━━━━━━━━━━━┳━━━━━━━━━━━━┳━━━━━━━━━━━┳━━━━━━━━━━━━┓
┃ database ┃ table     ┃ compressed ┃ uncompressed ┃ compr_rate ┃      rows ┃ part_count ┃
┡━━━━━━━━━━╇━━━━━━━━━━━╇━━━━━━━━━━━━╇━━━━━━━━━━━━━━╇━━━━━━━━━━━━╇━━━━━━━━━━━╇━━━━━━━━━━━━┩
│ default  │ weather   │ 237.48 MiB │ 3.63 GiB     │      15.66 │ 100000000 │          7 │
├──────────┼───────────┼────────────┼──────────────┼────────────┼───────────┼────────────┤
│ system   │ query_log │ 2.56 MiB   │ 27.79 MiB    │      10.87 │     27077 │          6 │
└──────────┴───────────┴────────────┴──────────────┴────────────┴───────────┴────────────┘
┏━━━━━━━━━━━━━━━┳━━━━━━━━━━━━━━━━━┳━━━━━━━━━━━━━━━━━━━┳━━━━━━━━┓
┃ name          ┃ compressed_size ┃ uncompressed_size ┃  ratio ┃
┡━━━━━━━━━━━━━━━╇━━━━━━━━━━━━━━━━━╇━━━━━━━━━━━━━━━━━━━╇━━━━━━━━┩
│ elevation     │ 48.05 MiB       │ 762.94 MiB        │  15.88 │
├───────────────┼─────────────────┼───────────────────┼────────┤
│ snow          │ 47.04 MiB       │ 476.84 MiB        │  10.14 │
├───────────────┼─────────────────┼───────────────────┼────────┤
│ wind          │ 47.04 MiB       │ 476.84 MiB        │  10.14 │
├───────────────┼─────────────────┼───────────────────┼────────┤
│ precipitation │ 47.04 MiB       │ 476.84 MiB        │  10.14 │
├───────────────┼─────────────────┼───────────────────┼────────┤
│ temperature   │ 46.98 MiB       │ 381.47 MiB        │   8.12 │
├───────────────┼─────────────────┼───────────────────┼────────┤
│ timestamp     │ 919.43 KiB      │ 762.94 MiB        │ 849.71 │
├───────────────┼─────────────────┼───────────────────┼────────┤
│ id            │ 429.22 KiB      │ 381.47 MiB        │ 910.09 │
└───────────────┴─────────────────┴───────────────────┴────────┘
```
