# Using PosgtreSQL read replica quickstart using Pulumi

## Overview
This quickstart will deploy the following infra on Aiven:
- Postgres primary instance in google-us-east1
- Postgres read replicas in google-us-west1 and google-europe-west1
- Cloud Function on GCP to insert fake data

## Requirements
- [Python](https://www.python.org/downloads/) 3.7+
- [Pulumi](https://www.pulumi.com/docs/get-started/install/) 2.10+
- [Google Cloud SDK](https://cloud.google.com/sdk/docs/install)

## Setup
In the main Python file (\_\_main\_\_.py) change the cloud regions if needed.

## Run
Issue the following commands to run and test:

```shell
python3 -m venv venv
pip install -r requirements.txt

pulumi config set aiven:apiToken XXXXXXXXXXXXXXXXXXXX --secret
pulumi config set aiven_project sa-demo
pulumi config set plan_size startup-4
pulumi config set pg_version 12

pulumi up -y
export postgres_master_uri=$(pulumi stack output pulumi-pg-master_uri --show-secrets)
export postgres_replica_uri=$(pulumi stack output pulumi-pg-replica1_uri --show-secrets)

source venv/bin/activate
python3 run.py
```

## Cleanup
Use the following commands to teardown:

```shell
pulumi destroy
pulumi stack rm my-stack-name-here
```
