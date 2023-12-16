# clickhouse-dbt

This demostrates how to integrate dbt with ClickHouse for Aiven by following the steps in https://clickhouse.com/docs/en/integrations/dbt


## Requirement

- `avn`
- `jq`


## Steps

- Update the `PROJECT` and `SERVICE` in `ch-dbt.env

Run the following to download clickhouse CLI and setup required service and databases.
```
./ch-dbt.sh setup
```

Run the following would load sample data, setup dbt and the ClickHouse plugin, then creates a Simple View Materialization.  dbt will represent the model as a view in ClickHouse as requested and finally query this view. 
```
./ch-dbt.sh demo
```

Run the following to delete all the resources created in this demo.
```
./ch-dbt.sh teardown
```