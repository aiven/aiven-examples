# Debezium Inkless Replication

This solution demonstrates PostgreSQL Change Data Capture (CDC) using Debezium with Aiven Inkless (diskless Kafka). It sets up a complete pipeline that replicates PostgreSQL table changes to Kafka topics using Inkless storage for improved performance and cost efficiency.

> **Learn more about Inkless:** [Aiven Inkless](https://aiven.io/inkless-campaign) - Cut your TCO by up to 80% with diskless topics for Apache Kafka®

> **⚠️ Note:** Inkless is currently only available for BYOC (Bring Your Own Cloud) setups. This means you need to deploy Aiven services in your own cloud account/VPC.

## Overview

The solution provisions:
- **Aiven Inkless (Kafka)** with diskless storage enabled
- **Aiven PostgreSQL** database
- **Aiven Kafka Connect** with Debezium PostgreSQL connector
- A test script to validate end-to-end replication

## Prerequisites

- Aiven account with API token
- **BYOC (Bring Your Own Cloud) setup** - Inkless is currently only available for BYOC deployments
- Terraform >= 1.0
- Python 3.11+ with pip
- `psql` client (for PostgreSQL connection)

## Setup

1. **Configure Terraform variables:**

   Copy and edit `terraform.tfvars`:
   ```bash
   # Required
   project_name = "your-project-name"
   aiven_api_token = ""  # Or set AIVEN_API_TOKEN environment variable
   
   # Optional (defaults shown)
   # cloud_name = "google-europe-west1"
   # plan_name = "startup-4"
   # kafka_plan_name = "business-16-inkless"
   # service_name_prefix = "debezium-diskless-"
   # table_name = "diskless_test"
   ```

2. **Deploy infrastructure:**

   ```bash
   terraform init
   terraform plan
   terraform apply
   ```

3. **Install Python dependencies:**

   ```bash
   pip install -r requirements.txt
   ```

## Usage

Run the test script to validate the replication:

```bash
# Use defaults (500 messages, batch size 100)
python test.py

# Customize number of messages
python test.py -n 5000

# Customize batch size
python test.py -b 50

# Combine options
python test.py -n 2000 -b 200
```

The test script will:
1. Create a table in PostgreSQL (if it doesn't exist)
2. Insert test data with unique run IDs
3. Consume messages from Kafka topic
4. Verify all messages were successfully replicated

## How It Works

1. **PostgreSQL** table changes are captured via logical replication
2. **Debezium connector** streams changes to Kafka
3. **Inkless (Kafka)** stores messages using diskless storage (writes directly to object storage like S3/GCS)
4. **Test script** validates end-to-end replication with message tracking

For more information about Inkless and its benefits, visit [Aiven Inkless](https://aiven.io/inkless-campaign).

## Cleanup

```bash
terraform destroy
```

## Files

- `main.tf` - Terraform configuration for Aiven services
- `terraform.tfvars` - Variable configuration (copy and customize)
- `publication.sql` - PostgreSQL publication setup for logical replication
- `test.py` - Test script for validating replication
- `requirements.txt` - Python dependencies

