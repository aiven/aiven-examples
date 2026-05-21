# Service integrations — schema replication (MM2)

Terraform configuration for **Kafka MirrorMaker 2** service integrations used for **schema replication** between the hub Kafka cluster (same VPC / in-project) and the MM2 service, plus the **spoke** path that uses a project-level **`external_kafka`** integration endpoint when the spoke (or its logical source) is reached over a different network than in-project service DNS.

## Relationship to other folders

| Piece | Role |
|-------|------|
| [`../infra-setup`](../infra-setup) | Creates hub Kafka, spoke Kafka, MM2 for schema replication, and (if still there) duplicate integrations—often you remove integrations from infra and manage them only here. |
| [`../project-integrations`](../project-integrations) | Registers the **`aiven_service_integration_endpoint`** of type `external_kafka` (bootstrap, SASL, CA). Use its **`external_kafka_endpoint_id`** output as the endpoint ID for the spoke integration. |
| [`../service-integrations-data-replication`](../service-integrations-data-replication) | Same pattern for **data** replication MM2 integrations; uses regional endpoint variable names (`use1`, `euw1`). |

This directory’s **`provider.tf`** matches **[`../infra-setup/provider.tf`](../infra-setup/provider.tf)** (required providers + `provider "aiven"`). **`variables.tf`** follows **[`../service-integrations-data-replication/variables.tf`](../service-integrations-data-replication/variables.tf)** for the two external endpoint IDs, and adds **`aiven_api_token`** and **`aiven_project_name`** so this folder can run as its own Terraform root.

## What `main.tf` defines

1. **`mm2-hub-svc-integration-schema-source`** — MM2 source is the **hub Aiven Kafka service** (`source_service_name`), appropriate when MM2 and the hub are in the same connectivity context.
2. **`mm2-spoke-svc-integration-schema-destination`** — MM2 source is the **`external_kafka` endpoint** (`source_endpoint_id` = `external_source_aiven_kafka_endpoint_id_use1`), for a spoke or external cluster reached via the registered endpoint.
3. **`hub_to_spoke_schema`** — MM2 replication flow from `aiven-hub-schema-produce-cluster` to `aiven-spoke-schema-receiver-cluster`. It defaults to the `_schemas` topic, uses `IdentityReplicationPolicy` to preserve the topic name, enables exactly-once delivery, and excludes internal / replica / Connect topics.

Official reference: [aiven_service_integration](https://registry.terraform.io/providers/aiven/aiven/latest/docs/resources/service_integration).

## Prerequisites

- Terraform compatible with the provider constraints in `provider.tf`
- An Aiven API token and project
- **Hub Kafka** and **`aiven_kafka_mirrormaker.mm2_schema_replication_1`** must exist in the same Terraform state (e.g. apply [`../infra-setup`](../infra-setup) first, or merge `.tf` files, or replace resource references with `data` / `terraform_remote_state`—this repo’s `main.tf` assumes those resources are in scope)
- **`external_kafka` endpoint** from [`../project-integrations`](../project-integrations) (or equivalent) for `external_source_aiven_kafka_endpoint_id_use1`

## Provider requirements

Same as [`../infra-setup/readme.md`](../infra-setup/readme.md#provider-requirements): **aiven** (~> 4.0), **time** (0.7.2), **env** (0.0.2), **null** (~> 3.0). Only **aiven** is required for the resources in `main.tf`; the other providers are declared to stay aligned with `infra-setup`.

## Variables

| Variable | Required | Description |
|----------|----------|-------------|
| `aiven_api_token` | yes | Aiven API token for the provider |
| `aiven_project_name` | yes | Aiven project for all integrations |
| `external_source_aiven_kafka_endpoint_id_use1` | yes | Endpoint ID for the spoke-side MM2 source on `mm2-spoke-svc-integration-schema-destination` |
| `external_source_aiven_kafka_endpoint_id_euw1` | no | Optional; same naming as data-replication. Defaults to `null` and is **not used** by current `main.tf` |
| `schema_replication_topics` | no | Java regex list for hub → spoke schema topics; defaults to `_schemas` |
| `replication_topics_blacklist` | no | Java regex list for topics excluded from replication; defaults to internal, replica, `__*`, and Connect topics |
| `schema_replication_exactly_once_delivery_enabled` | no | Enables exactly-once delivery on the schema flow; defaults to `true` |
| `schema_replication_factor` | no | Replication factor for MM2 internal topics used by the flow; defaults to `3` |

## Example tfvars

Copy [`variables-example.tfvars.examples`](variables-example.tfvars.examples) to a local `*.tfvars` file, fill in values, and **do not commit** secrets.

## Usage

```bash
cd service-integrations-schema-replication
terraform init
terraform plan -var-file=your.tfvars
terraform apply -var-file=your.tfvars
```

If `aiven_kafka.hub_kafka` and `aiven_kafka_mirrormaker.mm2_schema_replication_1` are not in this root module, add `data` sources or `terraform_remote_state` (or symlink / merge with `infra-setup`) before apply.
