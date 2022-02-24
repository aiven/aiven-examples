### Setting up Aiven Services
You will need an Aiven account with a project and a valid token. 

Run the following command to set the Aiven token in the environment variable `AVN_TOKEN`
```bash
. ./scripts/save-token.sh
```

Spin up the required services using terraform.
```bash
cd pg-sync/terraform
terraform init
terraform plan
terraform apply -var="aiven_api_token=$AVN_TOKEN" -var="aiven_project_name=<project-name>"
```

Install Requirements
```bash
cd pg-sync/src
pip3 install -r requirements.txt
```

copy kafka certificates
```bash
cd cdc/src/certs
project=<project-name>
avn service user-creds-download --project $project --username avnadmin cdc-demo-kafka
```

Create the PG table using `pg-sync/sql/pg.sql`

To monitor table changes properly the replica identity should be set to FULL.
```bash
ALTER TABLE <table-name> REPLICA IDENTITY FULL;
```

Run the App to push changes in Kafka to PG
```bash
cd cdc/src

PG_HOST=<pg-host>
PG_PORT=<pg-port>
PG_PW=<pg-pw>
PG_USER=<pg-user>
python3 main.py
```

For `UPDATE` and `DELETE` if some of the columns cannot be identified precisely, for example
`FLOAT` a combination of columns that can identify a unique row (e.g. primary key) can be 
specified. Multiple columns can be specified as comma separated. Regardless, the
recommended setting is to use the primary key if there is one.
```bash
export ROW_IDENTIFIER=id
```

The app can be started with special environment variables to handle non-standard data types.

Set the `DATE_FIELDS` env var to handle `DATE` fields:

Set the `DATETIME_MILLI_FIELDS` env var to handle `DATETIME` fields with precision 0-3:

Set the `DATETIME_MICRO_FIELDS` env var to handle `DATETIME` fields with precision 4-6:

Set the `TIMESTAMP_FIELDS` env var to handle `TIMESTAMP` fields:

Set the `BINARY_FIELDS` env var to handle `BLOB, TINYBLOB, MEDIUMBLOB, LONGBLOB, BINARY, VARBINARY` fields:

Set the `SET_FIELDS` env var to handle `SET` fields:

```bash
export DATE_FIELDS=date_column
export TIME_FIELDS=time_column
export SET_FIELDS=set_column
export BINARY_FIELDS=blob_column
export TIMESTAMP_FIELDS=datetime_column,timestamp_column
```
