# Project integrations (Terraform)

This folder defines **Aiven project service integration endpoints** for Kafka: reusable connection descriptors that other Aiven resources (for example MirrorMaker 2 service integrations) can reference by ID.

The focus is an **`external_kafka`** endpoint secured with **SASL_SSL** and **SCRAM-SHA-256**, with **credentials loaded from AWS Secrets Manager** so usernames and passwords are not committed in `.tfvars` or plain Terraform variables.

Official provider reference: [aiven_service_integration_endpoint](https://registry.terraform.io/providers/aiven/aiven/latest/docs/resources/service_integration_endpoint).

## Design

### Why an integration endpoint?

An integration endpoint registers “how to reach this Kafka cluster” inside an Aiven project. Downstream resources use the endpoint’s ID (for example as `source_endpoint_id` on an `aiven_service_integration` with `integration_type = "kafka_mirrormaker"`). That keeps bootstrap and auth configuration in one place and avoids duplicating connection details across integrations.

### External Kafka (non-Aiven cluster)

The primary resource is `aiven_service_integration_endpoint.external_kafka`:

- **`endpoint_type`**: `external_kafka`
- **`security_protocol`**: `SASL_SSL`
- **`sasl_mechanism`**: `SCRAM-SHA-256`
- **`bootstrap_servers`**: supplied via Terraform variable (host/port list is usually non-secret)
- **`sasl_plain_username` / `sasl_plain_password`**: read from a **Secrets Manager** secret version; the secret body must be **JSON** (see below)
- **`ssl_ca_cert`**: optional PEM string, either from the secret JSON key `ssl_ca_cert` or from variable `external_kafka_ssl_ca_cert` (variable wins when set)
- **`ssl_endpoint_identification_algorithm`**: `https`

Flow:

1. At plan/apply time, Terraform reads `data.aws_secretsmanager_secret_version.external_kafka`.
2. Locals parse `secret_string` with `jsondecode` and map fields into the Aiven resource.
3. Preconditions fail fast if username or password resolve to empty strings.

### Optional example: Aiven Kafka as the source

When `example_aiven_source_kafka_service_name` is set to a non-empty string, Terraform also creates `aiven_service_integration_endpoint.aiven_kafka_source_example`:

- **`data.aiven_kafka.example_source`**: looks up the existing Kafka service (same pattern as cross-cluster MM2 sources in other examples in this repo).
- **`data.aiven_project.example_kafka_project`**: supplies the project **CA certificate** for TLS trust (same project as the Kafka service by default, or override with `example_aiven_source_kafka_project_name`).

Credentials come from the Aiven provider’s Kafka data source (`username`, `password`), not from Secrets Manager. This block is optional and **off** when the example variable is `null` or unset.

### Security and state

- Storing credentials in Secrets Manager avoids checked-in secrets and keeps rotation in AWS.
- Terraform still **resolves** secret values during apply; they can appear in **state** and in logs if misconfigured. Use **encrypted remote state**, restrict state access, and avoid printing sensitive values in CI.
- The Aiven API token remains sensitive; pass it via environment or a secrets-backed variable, not a committed file.

## Repository layout

| File | Role |
|------|------|
| `provider.tf` | Terraform block, `aiven` and `aws` providers |
| `variables.tf` | Input variables |
| `main.tf` | Data sources, locals, integration endpoint resources |
| `outputs.tf` | Endpoint IDs and names for wiring into other stacks |

## Prerequisites

- **Aiven**: API token with permission to manage the target project and integration endpoints.
- **AWS**: Credentials and region available to the `aws` provider (environment, profile, OIDC role in CI, etc.).
- **IAM**: permission to call `secretsmanager:GetSecretValue` on the configured secret (and `kms:Decrypt` if the secret uses a customer-managed KMS key).

## Variables (summary)

| Variable | Purpose |
|----------|---------|
| `aiven_api_token` | Aiven API token (sensitive) |
| `aiven_project_name` | Project where the endpoint is created |
| `external_kafka_endpoint_name` | Logical name of the external Kafka endpoint |
| `external_kafka_bootstrap_servers` | Comma-separated `host:port` bootstrap list |
| `aws_region` | Region for Secrets Manager |
| `external_kafka_credentials_secret_id` | Secret name or ARN |
| `external_kafka_ssl_ca_cert` | Optional PEM override (sensitive) |
| `example_aiven_source_kafka_service_name` | Optional; enables Aiven-Kafka-as-source example |
| `example_aiven_source_kafka_project_name` | Optional; project owning that Kafka service |
| `example_aiven_kafka_source_endpoint_name` | Name for the optional example endpoint (default provided) |

## AWS Secrets Manager JSON shape

Store a **single JSON object** as the secret string (plain text secret type). Supported keys:

| Key | Required | Notes |
|-----|----------|--------|
| `sasl_plain_username` **or** `username` | Yes | SCRAM user |
| `sasl_plain_password` **or** `password` | Yes | SCRAM password |
| `ssl_ca_cert` | No | PEM for broker verification when needed |

Example:

```json
{
  "username": "app-scram-user",
  "password": "use-a-strong-secret",
  "ssl_ca_cert": "-----BEGIN CERTIFICATE-----\n...\n-----END CERTIFICATE-----\n"
}
```

Create or update the secret with the AWS Console or `aws secretsmanager create-secret` / `put-secret-value` using `--secret-string file://secret.json`.

## Usage

From this directory:

```bash
terraform init
terraform plan -var-file="your.tfvars"
terraform apply -var-file="your.tfvars"
```

Use outputs such as `external_kafka_endpoint_id` when defining `aiven_service_integration` resources in another `.tf` file or workspace (for example MM2 source integrations).

## Relation to `infra-setup`

The sibling `infra-setup` stack provisions hub/spoke Kafka and MirrorMaker services. This stack only registers **how to reach an external (or example Aiven) Kafka** inside the project. Wire the returned endpoint IDs into service integrations there or in a follow-up stack once ordering and dependencies are clear.
