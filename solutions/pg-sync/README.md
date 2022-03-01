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
cd pg-sync/src/certs
project=<project-name>
avn service user-creds-download --project $project --username avnadmin replicator-kafka
```

Create the PG table using `pg-sync/sql/pg.sql`
The heartbeat table should be created for all installations as it prevents replication lag
from growing too large, especially in the cases of databases with infrequent writes.

To monitor table changes properly the replica identity should be set to FULL.
```bash
ALTER TABLE <table-name> REPLICA IDENTITY FULL;
```

Use the configuration file (`config/config.json`) to specify which tables (specified as keys)
should be replicated and necessary information about these tables to assist with the
replication. All keys must be present for each table entry. 

Specify the config file path using the environment variable `CONFIG_FILE`.

For `UPDATE` and `DELETE` if some columns cannot be identified precisely, for example,
`FLOAT`, a combination of columns that can identify a unique row (e.g. primary key) can be 
specified. Multiple columns can be specified as well. Regardless, the
recommended setting is to use the primary key if there is one. Set this value for row_identifier.

The app can also process fields in a specific way based upon their type, and these can be 
identified in the configuration file as well.
* utilize the key, `date_fields` for `DATE` fields 
* utilize the key, `datetime_milli_fields` for `DATETIME` fields with precision 0-3
* utilize the key, `datetime_micro_fields` for `DATETIME` fields with precision 4-6
* utilize the key, `timestamp_fields` for `TIMESTAMP` fields 
* utilize the key, `binary_fields` for `BLOB, TINYBLOB, MEDIUMBLOB, LONGBLOB, BINARY, VARBINARY` fields
* utilize the key, `set_fields` for `SET` fields

Below is an example configuration for the table defined in `pg.sql`
```bash
{
  "all_datatypes": {
    "topic": "replicator.public.all_datatypes",
    "date_fields": [
      "date_column"
    ],
    "time_fields": [
      "time_column"
    ],
    "datetime_milli_fields": [],
    "datetime_micro_fields": [],
    "timestamp_fields": [
      "datetime_column",
      "timestamp_column"
    ],
    "set_fields": [
      "set_column"
    ],
    "binary_fields": [
      "blob_column"
    ],
    "binary_encoding": "utf-8",
    "row_identifier": ["id"]
  }
}

```

Run the App to push changes in Kafka to PG
```bash
cd pg-sync/src

PG_HOST=<pg-host>
PG_PORT=<pg-port>
PG_PW=<pg-pw>
PG_USER=<pg-user>
python3 main.py
```

