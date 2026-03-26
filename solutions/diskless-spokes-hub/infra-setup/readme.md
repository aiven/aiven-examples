# Diskless Spokes–Hub Infrastructure Setup

Terraform module that provisions the Aiven infrastructure for a **diskless Kafka hub–spoke** pattern with schema replication via Kafka MirrorMaker 2 (MM2).

## What Gets Created

- **Hub Kafka** – Diskless Kafka cluster with tiered storage, Schema Registry leader eligibility enabled.
- **Spoke Kafka** – Diskless Kafka cluster with tiered storage, Schema Registry leader eligibility disabled.
- **Kafka MirrorMaker 2** – MM2 service for replicating schemas from hub to spoke, with:
  - Hub and spoke service integrations
  - Topic/config/group-offset sync and checkpoints
  - A 10-minute wait after MM2 creation so clusters are ready before replication setup

All Kafka services use Kafka 4.0 with diskless and tiered storage enabled.

## Prerequisites

- [Terraform](https://www.terraform.io/downloads) (compatible with provider versions below)
- An [Aiven](https://aiven.io/) account and project
- An Aiven [API token](https://docs.aiven.io/docs/platform/howto/create-api-token)
- Aiven cloud / region names where the hub and spoke clusters will run

## Provider Requirements

- **aiven** (~> 4.0)
- **time** (0.7.2) – for the readiness wait
- **env** (0.0.2)
- **null** (~> 3.0)

## Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `aiven_api_token` | Aiven API token | *(required)* |
| `aiven_project_name` | Aiven project name | `sa-inkless-gcp` |
| `service_prefix` | Prefix for created service names | `mp-demo` |
| `cloud_name_hub` | Cloud/region for the hub Kafka cluster | *(see variables.tf)* |
| `cloud_name_spoke_1` | Cloud/region for the spoke Kafka cluster | *(see variables.tf)* |
| `hub_kafka_plan` | Plan for hub Kafka | `business-8-inkless` |
| `spoke_kafka_plan` | Plan for spoke Kafka | `business-8-inkless` |
| `mm2_plan_hub_cluster` | Plan for MM2 service | `business-4` |

Create a `.tfvars` file (e.g. from `variables-example.tfvars.examples`) and set these as needed. **Do not commit files that contain your API token.**

## Usage

1. **Initialize Terraform**

   ```bash
   terraform init
   ```

2. **Review the plan**

   ```bash
   terraform plan -var-file=your.tfvars
   ```

3. **Apply**

   ```bash
   terraform apply -var-file=your.tfvars
   ```

   The apply includes a 10-minute wait after the MM2 service and integrations are created so that the hub and spoke clusters are ready for replication configuration (e.g. in `replication-setup`).

## Outputs and Next Steps

After a successful apply, use the created hub and spoke Kafka service names and connection details in the [replication-setup](../replication-setup) module to configure replication (topics, MM2 connectors, etc.).
