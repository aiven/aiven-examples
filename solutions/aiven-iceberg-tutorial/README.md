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
To automate the creation of IAM roles and policies required for Snowflake Open Catalog, use the included `setup_snowflake_aws_access.sh` script:

1. Configure Environment Variables:
   ```bash
   export AWS_ACCOUNT_ID="your-aws-account-id"
   export EXTERNAL_ID="your-external-id"
   export S3_BUCKET_NAME="your-bucket-name"
   ```

2. Run the Script:
   ```bash
   ./setup_snowflake_aws_access.sh
   ```
   This will create:
   - An IAM policy for S3 access
   - An IAM role for Snowflake
   - Attach the policy to the role

## Snowflake Open Catalog Setup

### Step 3: Access or Create a Snowflake Open Catalog Account
1. Sign in as an ORGADMIN or create a new account

### Step 4: Create a Catalog Resource in Open Catalog
1. Link your S3 storage to Open Catalog

## Aiven Kafka Setup

### Step 5: Set Up Aiven Services using Terraform

1. **Configure Terraform Variables**
   ```bash
   cd terraform
   cp terraform.tfvars.example terraform.tfvars
   ```
   Edit `terraform.tfvars` and set your values:
   - `aiven_api_token`: Your Aiven API token (get from Aiven Console)
   - `aiven_project_name`: Your Aiven project name
   - `s3_access_key_id`: Your AWS access key ID
   - `s3_secret_access_key`: Your AWS secret access key
   - `snowflake_uri`: Your Snowflake Open Catalog URI

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

## Go Kafka Producer Setup

### Step 6: Set Up and Run the Go Producer
1. Customize the `main.go` file with your Aiven cert file paths
2. Build and run the Go application:
   ```bash
   go build
   ./aiven-iceberg-tutorial
   ```

## Aiven Kafka Connect and Iceberg Sink

### Step 7: Set Up Aiven for Apache Kafka Connect Service
1. Create a Kafka Connect service linked to your Kafka service

### Step 8: Configure the Iceberg Sink Connector
1. Use the provided JSON configuration
2. Replace placeholders with your specific values

## Data Verification

### Step 9: Verify Data in S3
1. Check your S3 bucket to ensure data and metadata are appearing correctly
2. Verify the Iceberg table structure

## Trino Setup and Querying

### Step 10: Set Up Trino
1. Navigate to the `trinocontainer` directory
2. Start the Trino service:
   ```bash
   docker-compose up -d
   ```

### Step 11: Query with Trino
1. Connect to Trino CLI:
   ```bash
   docker exec -it trinocontainer-trino-1 trino
   ```

2. Run example queries:
   ```sql
   SHOW SCHEMAS FROM iceberg;
   SELECT * FROM iceberg.spark_demo.product LIMIT 10;
   ```

## Cleanup

To clean up resources:
1. Stop the Trino container:
   ```bash
   cd trinocontainer
   docker-compose down
   ```

2. Destroy Terraform resources:
   ```bash
   cd terraform
   terraform destroy
   ```

3. Delete AWS resources:
   - Remove the IAM role and policy
   - Delete the S3 bucket
   