# Comprehensive Guide: Kafka to Iceberg on S3 with Snowflake Open Catalog & Trino

This guide will walk you through setting up a complete data pipeline that:
- Produces JSON messages to an Aiven for Apache Kafka topic using a Go application
- Uses Aiven for Apache Kafka Connect with the Iceberg Sink Connector to write messages to an Apache Iceberg table in AWS S3
- Manages the Iceberg table's metadata using Snowflake Open Catalog
- Queries the Iceberg table using Trino running in Docker

## Table of Contents
1. [Prerequisites](#prerequisites)
2. [AWS Setup](#aws-setup)
3. [Snowflake Open Catalog Setup](#snowflake-open-catalog-setup)
4. [Aiven Kafka Setup](#aiven-kafka-setup)
5. [Go Kafka Producer Setup](#go-kafka-producer-setup)
6. [Aiven Kafka Connect and Iceberg Sink](#aiven-kafka-connect-and-iceberg-sink)
7. [Data Verification](#data-verification)
8. [Trino Setup and Querying](#trino-setup-and-querying)
9. [Cleanup](#cleanup)

## Prerequisites

Before starting, ensure you have:
- Docker and Docker Compose installed
- Access to AWS for S3 and IAM setup
- Aiven account for Kafka and Kafka Connect
- Snowflake account for Open Catalog
- AWS CLI installed and configured with necessary permissions

## AWS Setup

### Step 1: Create S3 Bucket
1. Create an S3 bucket in your desired AWS region (e.g., us-west-2)
2. Note the bucket name and path:
   - Example Bucket Name: `your-iceberg-s3-bucket`
   - Example Path: `s3://your-iceberg-s3-bucket/your-catalog-path/`

### Step 2: IAM Role and Policy Setup
To automate the creation of IAM roles and policies required for Snowflake Open Catalog, use the included `roles.sh` script:

1. Configure Environment Variables:
   - Open `roles.sh` and set:
     - `AWS_ACCOUNT_ID`: Your AWS account ID
     - `EXTERNAL_ID`: An external ID for role assumption
     - `BUCKET_NAME`: Your S3 bucket name

2. Run the Script:
   ```bash
   ./roles.sh
   ```
   This will create the necessary IAM policy and role, and attach the policy to the role.

### Step 3: Create IAM Policy for S3 Access
1. Create a policy granting necessary permissions to Snowflake Open Catalog
2. Use the provided JSON template to create the policy

### Step 4: Create IAM Role for Snowflake Open Catalog
1. Create a role and attach the policy created in Step 3
2. Record the Role ARN for later use

## Snowflake Open Catalog Setup

### Step 5: Access or Create a Snowflake Open Catalog Account
1. Sign in as an ORGADMIN or create a new account

### Step 6: Create a Catalog Resource in Open Catalog
1. Link your S3 storage to Open Catalog

### Step 7: Update IAM Role Trust Policy
1. Modify the trust policy to include the Open Catalog IAM User ARN

## Aiven Kafka Setup

### Step 8: Set Up Aiven Services using Terraform

1. **Configure Terraform Variables**
   ```bash
   cd terraform
   cp terraform.tfvars.example terraform.tfvars
   ```
   Edit `terraform.tfvars` and set your values:
   - `aiven_api_token`: Your Aiven API token (get from Aiven Console)
   - `aiven_project_name`: Your Aiven project name
   - `s3_warehouse_location`: Your S3 warehouse path
   - `snowflake_uri`: Your Snowflake account URL
   - `snowflake_warehouse`: Your Snowflake warehouse name
   - `snowflake_database`: Your Snowflake database name

2. **Initialize and Apply Terraform**
   ```bash
   terraform init
   terraform plan
   terraform apply
   ```

   This will create:
   - A Kafka service named `iceberg-kafka`
   - Two Kafka topics: `product` and `iceberg-control`
   - A Kafka Connect service named `iceberg-connect`
   - An Iceberg Sink Connector

3. **Get Service Details**
   After Terraform completes, note the following details from the output:
   - Kafka Service URI
   - Kafka Connect Service URI
   - Topic names

### Step 9: Create Kafka Topics
1. Create the topic for your producer
2. Create a control topic for the connector

## Go Kafka Producer Setup

### Step 10: Set Up and Run the Go Producer
1. Customize the `main.go` file with your Aiven cert file paths
2. Build and run the Go application:
   ```bash
   go build
   ./aiven-iceberg-tutorial
   ```

## Aiven Kafka Connect and Iceberg Sink

### Step 11: Set Up Aiven for Apache Kafka Connect Service
1. Create a Kafka Connect service linked to your Kafka service

### Step 12: Configure the Iceberg Sink Connector
1. Use the provided JSON configuration
2. Replace placeholders with your specific values

## Data Verification

### Step 13: Verify Data in S3
1. Check your S3 bucket to ensure data and metadata are appearing correctly
2. Verify the Iceberg table structure

## Trino Setup and Querying

### Step 14: Prepare Trino Environment
1. Copy the following files to the `aiven-iceberg-tutorial` directory:
   - `docker-compose.yml`
   - `trino/etc/catalog/iceberg.properties`

### Step 15: Configure Trino's Iceberg Catalog
1. Modify `iceberg.properties` with your Snowflake and S3 details
2. Ensure correct configuration for your Iceberg catalog

### Step 16: Launch Trino
1. Navigate to the `aiven-iceberg-tutorial` directory
2. Start the Trino service:
   ```bash
   docker-compose up -d
   ```
3. Check logs to ensure proper startup:
   ```bash
   docker-compose logs trino-coordinator
   ```

### Step 17: Query with Trino
1. Connect to Trino CLI
2. Run example queries:
   ```sql
   SHOW SCHEMAS FROM iceberg;
   SELECT * FROM iceberg.spark_demo.product LIMIT 10;
   ```

## Cleanup

After completing the setup, you can remove the following directories if no longer needed:
- `aiveniceberg`
- `iceberg`
- `polaris-trino-iceberg-spark-main`

---

This guide provides a comprehensive walkthrough for setting up a data pipeline from Kafka to Iceberg on S3, managed by Snowflake Open Catalog, and queried using Trino. Customize the provided configurations and scripts to fit your specific environment and requirements. 