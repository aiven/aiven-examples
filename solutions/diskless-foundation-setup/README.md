# Diskless Foundation Setup

This Terraform configuration is a foundation to set up a Kafka service with diskless topics backed by Object Storage enabled on Aiven.

## Overview

This setup creates:
- A Kafka service with diskless storage enabled
- A Kafka topic configured for diskless storage
- Schema Registry and Kafka REST API enabled
- Tiered storage enabled for efficient data management

## Prerequisites

1. **Aiven Account**: You need an active Aiven account with an API token
2. **Terraform**: Version >= 1.0 installed
3. **Aiven Project**: An existing Aiven project where services will be created
4. **API Token**: Your Aiven API token (can be set via environment variable or terraform.tfvars)

## Getting Started

### 1. Set Up Your API Token

You can provide your Aiven API token in one of two ways:

**Option A: Environment Variable (Recommended)**
```bash
export AIVEN_API_TOKEN="your-api-token-here"
```

**Option B: Terraform Variables File**
Create a `terraform.tfvars` file (see `example-terraform-tfvars.txt` for reference):
```hcl
project_name = "your-aiven-project-name"
aiven_api_token = "your-api-token-here"
```

### 2. Configure Variables

Create a `terraform.tfvars` file based on `example-terraform-tfvars.txt`:

```hcl
project_name = "your-aiven-project-name"
aiven_api_token = "aa...."  # Or set AIVEN_API_TOKEN environment variable

# Optional (defaults shown)
cloud_name = "google-europe-west1"
kafka_plan_name = "business-16-inkless"
service_name_prefix = "demo-diskless-"
```

### 3. Initialize and Apply

```bash
# Initialize Terraform
terraform init

# Review the plan
terraform plan

# Apply the configuration
terraform apply
```

## Configuration Options

### Variables

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `project_name` | Aiven project name where services will be created | - | Yes |
| `aiven_api_token` | Aiven API token | - | No* |
| `cloud_name` | Cloud region for services | `google-europe-west1` | No |
| `kafka_plan_name` | Kafka service plan | `business-16-inkless` | No |
| `service_name_prefix` | Prefix for service names | `demo-diskless-` | No |

*API token can be provided via `AIVEN_API_TOKEN` environment variable

### Kafka Configuration

The setup configures Kafka with:
- **Kafka Version**: 4.0
- **Schema Registry**: Enabled
- **Kafka REST API**: Enabled
- **Kafka Connect**: Disabled
- **Tiered Storage**: Enabled
- **Follower Fetching**: Enabled
- **Diskless Storage**: Enabled
- **Auto-create Topics**: Enabled
- **Default Replication Factor**: 3
- **Min In-Sync Replicas**: 2

#### Follower Fetching

Follower fetching is enabled in this configuration to optimize performance for diskless topics. When enabled, Kafka followers can fetch data from other followers in addition to the leader, which:

- **Reduces leader load**: Distributes read load across multiple brokers
- **Improves throughput**: Allows followers to fetch from the nearest available replica
- **Enhances availability**: Provides better fault tolerance and recovery capabilities
- **Optimizes for diskless storage**: Particularly beneficial for diskless topics where data is stored in object storage

This feature is configured in the Terraform setup via the `follower_fetching` block with `enabled = true` in the Kafka user configuration.

### Topic Configuration

A sample topic `diskless_test_1` is created with:
- **Partitions**: 3
- **Replication**: 1
- **Diskless Storage**: Enabled

## Client Configuration Best Practices

When using diskless storage, configure your Kafka clients according to the recommendations in `settings.ini`:

### Producer Settings

```properties
# AZ aware clients
client.id="<custom_id>,diskless_az=<rack>"

# Larger Batches - Completely depends on the use case
linger.ms=100
batch.size=16384  # 16KiB
max.request.size=1048576  # 1MiB
acks=all
enable.idempotence=true
max.inflight.requests.per.connection=2  # default 5
```

### Consumer Settings

```properties
# AZ aware clients
client.id="<custom_id>,diskless_az=<rack>"
fetch.max.bytes=1048576  # 1MiB
max.partition.fetch.bytes=1048576  # 1MiB

# Optional for higher throughput at expense of higher latency
# fetch.min.bytes=1
# fetch.max.wait.ms=500
```

## Outputs

After applying the Terraform configuration, you'll get the following outputs:

- `kafka_service_uri`: URI of the Kafka service (sensitive)
- `kafka_certificate`: Client certificate for Kafka (sensitive)
- `kafka_access_key`: Private key for Kafka (sensitive)
- `kafka_ca_cert`: CA certificate for the project (sensitive)
- `topic_name`: Name of the created Kafka topic

To view outputs:
```bash
terraform output
```


## Cleanup

To destroy all resources created by this configuration:

```bash
terraform destroy
```

## Notes

- Diskless storage is optimized for high-throughput, high-latency workloads
- Ensure your clients are configured with AZ awareness for optimal performance
- For the classic topics, the default replication factor is set to 3 for high availability
- For the Diskless topics, the replication factor is always going to be set as 1 because it directly writes to Object Storage for high durability
- Tiered storage is enabled to efficiently manage data lifecycle
- Follower fetching is enabled to improve performance and reduce leader load, which is particularly beneficial for diskless topics

## Additional Resources

- [Aiven Kafka Documentation](https://docs.aiven.io/docs/products/kafka)
- [Aiven Terraform Provider Documentation](https://registry.terraform.io/providers/aiven/aiven/latest/docs)
- [Kafka Diskless Topics Architecture](https://aiven.io/docs/products/kafka/diskless/concepts/diskless-topics-architecture)
- [Inkless FAQs](https://github.com/aiven/inkless/blob/main/docs/inkless/FAQ.md)
