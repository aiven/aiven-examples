# Iceberg Sink Connector with Aiven 🦀

This example demonstrates how to set up an Apache Iceberg sink connector using Aiven services (Kafka, Kafka Connect, PostgreSQL) to write data to Amazon S3.

## Architecture

- **Kafka**: Message streaming platform
- **Kafka Connect**: Connector framework
- **PostgreSQL**: Iceberg catalog metadata storage
- **S3**: Iceberg data warehouse storage
- **DuckDB**: Query engine for testing

## Prerequisites

- Aiven account and API token
- AWS account with S3 bucket
- Python 3.8+ with pip
- Terraform

## Quick Start

### 1. Configure Environment

Copy the example configuration:
```bash
cp terraform.tfvars.example terraform.tfvars
```

### 2. Set Up AWS Access

Choose one of these methods:

#### Option A: IAM Assume Role (Recommended)
This is the most secure option as you don't expose any AWS credentials:

- **No AWS credentials exposed** in configuration files
- **Aiven's dedicated IAM user** assumes your role using temporary credentials
- **Automatic credential rotation** - credentials expire and are refreshed automatically
- **Full audit trail** - all S3 access is logged in AWS CloudTrail with session names

**How it works:**

1. **Contact Aiven Support**: Email `support@aiven.io` to request your unique IAM user and External ID
2. **Create Cross-Account Role**: In your AWS Console, go to IAM → Roles → Create Role
3. **Select Trusted Entity**: Choose "Another AWS account" and enter Aiven's account ID
4. **Set External ID**: Paste the External ID provided by Aiven support
5. **Add S3 Permissions**: Attach policies for `s3:GetObject`, `s3:PutObject`, `s3:DeleteObject`, `s3:ListBucket`, `s3:AbortMultipartUpload`, `s3:ListMultipartUploadParts`, `s3:ListBucketMultipartUploads`

**Example IAM Policy:**
```json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "s3:GetObject",
                "s3:PutObject",
                "s3:DeleteObject",
                "s3:ListBucket",
                "s3:AbortMultipartUpload",
                "s3:ListMultipartUploadParts",
                "s3:ListBucketMultipartUploads"
            ],
            "Resource": [
                "arn:aws:s3:::your-bucket-name/*",
                "arn:aws:s3:::your-bucket-name"
            ]
        }
    ]
}
```
6. **Note the Role ARN**: Copy the role ARN (e.g., `arn:aws:iam::123456789012:role/iceberg-s3-role`)

For more information, see the [Aiven documentation](https://aiven.io/docs/products/kafka/kafka-connect/howto/s3-iam-assume-role).

#### Option B: Direct AWS Credentials
For development/testing, you can use direct AWS credentials:

```bash
export AWS_ACCESS_KEY_ID="your-access-key"
export AWS_SECRET_ACCESS_KEY="your-secret-key"
```

**Security Note**: This method stores credentials in your connector configuration. For production, use IAM assume role or secret providers. See the [Aiven documentation](https://aiven.io/docs/products/kafka/kafka-connect/howto/configure-secret-providers) for setup instructions.


### 3. Configure Aiven Access

Get your Aiven API token from the [Aiven Console](https://console.aiven.io/account/tokens) and set it:

```bash
export AIVEN_API_TOKEN="your-aiven-token"
```

### 4. Update Configuration

Edit `terraform.tfvars` with your specific values:

```hcl
# Required: Your Aiven project name
project_name = "your-aiven-project"

# Required: Your S3 bucket name (must exist)
s3_bucket_name = "your-s3-bucket"

# Required: AWS region (must match your S3 bucket region)
aws_region = "eu-west-1"

# Optional: IAM role ARN (if using assume role)
# Copy the role ARN from step 6 above and paste it here:
aws_role_arn = "arn:aws:iam::123456789012:role/iceberg-s3-role"

# Optional: Customize service names and settings
service_name_prefix = "iceberg-sink"
topic_name = "test_iceberg_topic"
table_name = "systest-table"
```

### 5. Deploy Infrastructure

Initialize and deploy the infrastructure:

```bash
# Initialize Terraform and download providers
terraform init

# Review what will be created
terraform plan

# Apply the configuration (this will create Aiven services)
terraform apply
```

**Important**: This creates multiple Aiven services that will incur costs. Review the plan carefully before applying.

### 6. Install Python Dependencies

Install the required Python packages for testing:

```bash
pip install -r ./scripts/requirements.txt
```

### 7. Run Test

Execute the test script to validate the setup:

```bash
python ./scripts/test_iceberg_connector.py
```

The test will:
- Send test messages to Kafka
- Wait for the Iceberg sink connector to process them
- Query the data using DuckDB
- Display results and timing information


## Cleanup

```bash
terraform destroy
```
