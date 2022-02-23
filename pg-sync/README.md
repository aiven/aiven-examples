### Setting up Aiven Services
You will need an Aiven account with a project and a valid token. 

Run the following command to set the Aiven token in the environment variable `AVN_TOKEN`
```bash
. ./scripts/save-token.sh
```

Spin up the required services using terraform.
```bash
cd cdc/terraform
terraform init
terraform plan
terraform apply -var="aiven_api_token=$AVN_TOKEN" -var="aiven_project_name=<project-name>"
```

Install Requirements
```bash
cd cdc/src
pip3 install -r requirements.txt
```

copy kafka certificates
```bash
cd cdc/src/certs
project=<project-name>
avn service user-creds-download --project $project --username avnadmin cdc-demo-kafka
```

Create the PG table using `cdc/sql/pg.sql`

If tables do not have a primary key, then the replica identity should be set to FULL
```bash
ALTER TABLE public.test REPLICA IDENTITY FULL;
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
specified. Multiple columns can be specified as comma separated.
```bash
export ROW_IDENTIFIER=id
```

Some type, when pulled from MySQL using Kafka Connect, are represented in way that are
not directly compatible with PG. The Faust app can be started with special environment variables
set to handle these.

Set the `DATE_FIELDS` env var to handle `DATE` fields:
```bash
export DATE_FIELDS=date_column
```

Set the `DATETIME_MILLI_FIELDS` env var to handle `DATETIME` fields with precision 0-3:
```bash
export DATETIME_MILLI_FIELDS=datetime_column
```

Set the `DATETIME_MICRO_FIELDS` env var to handle `DATETIME` fields with precision 4-6:
```bash
export DATETIME_MILLI_FIELDS=datetime_column
```

Set the `TIMESTAMP_FIELDS` env var to handle `TIMESTAMP` fields:
```bash
export TIMESTAMP_FIELDS=timestamp_column
```

Set the `BINARY_FIELDS` env var to handle `BLOB, TINYBLOB, MEDIUMBLOB, LONGBLOB, BINARY, VARBINARY` fields:
```bash
export BINARY_FIELDS=tinyblob_column,mediumblob_column,longblob_column,binary_column,varbinary_column,blob_column
```

Set the `SET_FIELDS` env var to handle `SET` fields:
```bash
export SET_FIELDS=set_column
```

