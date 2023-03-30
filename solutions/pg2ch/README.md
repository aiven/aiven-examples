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
- This is a demo on migrating a PostgreSQL (startup-16) table with 2,040,000,000 rows 99GB of data to ClickHouse (business-32).
```
test=> \d large_test;
                 Table "public.large_test"
 Column |       Type       | Collation | Nullable | Default
--------+------------------+-----------+----------+---------
 num1   | bigint           |           |          |
 num2   | double precision |           |          |
 num3   | double precision |           |          |

test=> \dt+;
                                     List of relations
 Schema |    Name    | Type  |  Owner   | Persistence | Access method | Size  | Description
--------+------------+-------+----------+-------------+---------------+-------+-------------
 public | large_test | table | avnadmin | permanent   | heap          | 99 GB |

test=> select count(num1) from large_test;
   count
------------
 2040000000
(1 row)
```

```
-- CH_CLI: ./clickhouse client --user avnadmin --password ****** --host clickhouse-test-******.aivencloud.com --port ***** --secure
-- CH_PGDB: service_pg-load_test_public
-- CH_SVC: clickhouse-test
-- SERVICE_INTEGRATION_ID: ***884f-****-4491-83e3-***********
Setting up service integration [***884f-****-4491-83e3-**********] [pg-load.test.public] for [clickhouse-test.default] ...

Generated clickhouse-test_test_dump.sql
Generated clickhouse-test_test_drop.sql

Press any key to load clickhouse-test_test_dump.sql to clickhouse-test.default or CTRL+C to stop

CREATE TABLE IF NOT EXISTS default.large_test(`num1` Int64,`num2` Float64,`num3` Float64) ENGINE = MergeTree() ORDER by tuple();
s_c2c75	clickhouse-test-13.felixwu-demo.aiven.local	OK	0	0
0.015
Processed rows: 1
CREATE TABLE IF NOT EXISTS default.large_test_buffer AS default.large_test ENGINE = Buffer(default, large_test, 40, 10, 100, 10000, 1000000, 10000000, 100000000);
s_c2c75	clickhouse-test-13.felixwu-demo.aiven.local	OK	0	0
0.005
Processed rows: 1
INSERT INTO default.large_test_buffer SELECT * FROM `service_pg-load_test_public`.`large_test`;
0 rows in set. Elapsed: 3299.402 sec. Processed 2.04 billion rows, 55.08 GB (618.29 thousand rows/s., 16.69 MB/s.)

┏━━━━━━━━━━┳━━━━━━━━━━━━┳━━━━━━━━━━━━┳━━━━━━━━━━━━━━┳━━━━━━━━━━━━┳━━━━━━━━━━━━┳━━━━━━━━━━━━┓
┃ database ┃ table      ┃ compressed ┃ uncompressed ┃ compr_rate ┃       rows ┃ part_count ┃
┡━━━━━━━━━━╇━━━━━━━━━━━━╇━━━━━━━━━━━━╇━━━━━━━━━━━━━━╇━━━━━━━━━━━━╇━━━━━━━━━━━━╇━━━━━━━━━━━━┩
│ default  │ large_test │ 36.92 GiB  │ 47.12 GiB    │       1.28 │ 2108155425 │         12 │
├──────────┼────────────┼────────────┼──────────────┼────────────┼────────────┼────────────┤
│ system   │ query_log  │ 1.85 MiB   │ 20.77 MiB    │      11.26 │      18012 │          7 │
├──────────┼────────────┼────────────┼──────────────┼────────────┼────────────┼────────────┤
│ default  │ rental     │ 378.93 KiB │ 579.71 KiB   │       1.53 │      16044 │          1 │
└──────────┴────────────┴────────────┴──────────────┴────────────┴────────────┴────────────┘
```
