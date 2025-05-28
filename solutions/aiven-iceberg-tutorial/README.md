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

### Step 1: Create or use AWS IAM User
1. Create an AWS User or use an existing one
2. Make sure the following policy is attached to the user (either create or use existing policy):
   ```json
   {
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "iam:CreatePolicy",
                "iam:CreateRole",
                "iam:AttachRolePolicy",
                "iam:GetRole",
                "iam:GetPolicy",
                "iam:ListAttachedRolePolicies"
            ],
            "Resource": [
                "arn:aws:iam::<account-id>:role/*",
                "arn:aws:iam::<account-id>:policy/*"
            ]
        },
        {
            "Effect": "Allow",
            "Action": [
                "s3:CreateBucket",
                "s3:HeadBucket",
                "s3:ListBucket",
                "s3:GetBucketLocation",
                "s3:PutBucketPolicy",
                "s3:GetBucketPolicy"
            ],
            "Resource": [
                "arn:aws:s3:::<your-s3-bucket>",
                "arn:aws:s3:::<your-s3-bucket>/*"
            ]
        }
    ]
   }    
   ```
### Step 2: S3, IAM Role and Policy Setup
To automate the creation of S3, IAM roles and policies required for Snowflake Open Catalog, use the included `setup_snowflake_aws_access.sh` script:
1. Ensure AWS cli is downloaded and run:
   ```bash
   aws configure
   ```
2. You should be prompted to enter your AWS credentials, make sure you use the same aws-region as the S3 bucket you created.

3. Configure Environment Variables (note: for external-id, we can create an id of our choice and use it in the snowflake catalog):
   ```bash
   export AWS_ACCOUNT_ID="your-aws-account-id"
   export EXTERNAL_ID="your-external-id"
   export S3_BUCKET_NAME="your-bucket-name"
   export AWS_REGION="your-aws-region"
   ```
4. Run the Script:
   ```bash
   ./setup_snowflake_aws_access.sh
   ```
   This will create:
   - An S3 bucket in your desired AWS region (e.g., us-west-2)
   - An IAM policy for S3 access
   - An IAM role for Snowflake
   - Attach the policy to the role

## Snowflake Open Catalog Setup

### Step 1: Access or Create a Snowflake Open Catalog Account
1. Sign in as an ORGADMIN or create a new account 

### Step 2: Create a Catalog Resource in Open Catalog
1. Click create a Catalog in Snowflake open catalog
1. In the Snowflake UI, navigate to Catalogs
2. Click "Create Catalog"
3. Fill in the following details:
   - Name: Choose a name for your catalog (e.g., `ICEBERG_CATALOG`)
   - Storage Provider: Select "S3" 
   - Default base location: Enter `s3://<s3-bucket-name>` (e.g., `s3://apache-iceberg-bucket-demo`)
   - S3 Role ARN: Enter the ARN of the role created by setup_snowflake_aws_access.sh
     (Format: `arn:aws:iam::<AWS_ACCOUNT_ID>:role/snowflake_s3_role`)
   - External Id: Enter the external id from the setup_snowflake_aws_access.sh script
4. Click "Create" to finalize the catalog creation

## Aiven Kafka Setup

### Step 1: Set Up Aiven Services using Terraform

1. **Configure Terraform Variables**
   ```bash
   cd terraform
   cp terraform.tfvars.example terraform.tfvars
   ```
   Edit `terraform.tfvars` and set your values:
   - `aiven_api_token`: Your Aiven API token (Aiven Console https://console.aiven.io/profile/tokens)
   - `aiven_project_name`: Your Aiven project name (Aiven Console https://console.aiven.io/projects)
   - `s3_access_key_id`: Your AWS access key ID
   - `s3_secret_access_key`: Your AWS secret access key
   - `snowflake_uri`: Your Snowflake Open Catalog URI (eg. https://<your-account>.snowflakecomputing.com/polaris/api/catalog)
   - `iceberg_catalog_scope`:
   - `iceberg_s3_access_key`: Your Snowflake Connector access key
   - `iceberg_s3_secret_key`: Your Snowflake Connector secret key

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

### Step 1: Set Up and Run the Go Producer
1. Add your certs from the Aiven for Kafka Service to certs directory (ca.pem, service.cert, service.key)
2. Update `main.go` on line 83 <your-aiven-kafka-broker-address> with the Service URI from Aiven for Kafka Service
3. Build and run the Go application:
   ```bash
   go build
   ./aiven-iceberg-tutorial
   ```

## Data Verification

### Step 1: Verify Data in S3
1. Check your S3 bucket to ensure data and metadata are appearing correctly
2. Verify the Iceberg table structure

## Trino Setup and Querying

### Step 1: Set Up Trino
1. Navigate to the `trinocontainer` directory
2. Inside `trinocontainer/trino/etc/catalog/iceberg.properties` and update the values
3. Start the Trino service:
   ```bash
   docker-compose up -d
   ```

### Step 2: Query with Trino
1. Connect to Trino CLI:
   ```bash
   docker exec -it trinocontainer-trino-1 trino
   ```

2. Run example queries:
   ```sql
   SHOW SCHEMAS FROM iceberg;
   SELECT * FROM iceberg.spark_demo.product LIMIT 15;
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
   