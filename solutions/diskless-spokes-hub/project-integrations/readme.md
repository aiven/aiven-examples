# Project integrations (Terraform)

This folder defines **Aiven project service integration endpoints** for Kafka: reusable connection descriptors that other Aiven resources (for example MirrorMaker 2 service integrations) can reference by ID.

The primary endpoint is `external_kafka` secured with **SASL_SSL** and **SCRAM-SHA-256**, with credentials loaded from **AWS Secrets Manager** so usernames and passwords are not committed in `.tfvars` or plain Terraform variables.

An optional second endpoint shows how to register an **existing Aiven Kafka service** as an `external_kafka` source using provider data sources (no Secrets Manager).

Official provider reference: [aiven_service_integration_endpoint](https://registry.terraform.io/providers/aiven/aiven/latest/docs/resources/service_integration_endpoint).

## Design

### Why an integration endpoint?

An integration endpoint registers how to reach a Kafka cluster inside an Aiven project. Downstream resources use the endpoint ID (for example as `source_endpoint_id` on an `aiven_service_integration` with `integration_type = "kafka_mirrormaker"`). Bootstrap and auth stay in one place instead of being duplicated across integrations.

### External Kafka (non-Aiven cluster)

Resource: `aiven_service_integration_endpoint.external_kafka`

| Setting | Value |
| --- | --- |
| `endpoint_type` | `external_kafka` |
| `security_protocol` | `SASL_SSL` |
| `sasl_mechanism` | `SCRAM-SHA-256` |
| `bootstrap_servers` | `var.external_kafka_bootstrap_servers` (comma-separated `host:port`; usually non-secret) |
| `sasl_plain_username` / `sasl_plain_password` | From Secrets Manager JSON (see below) |
| `ssl_ca_cert` | `var.external_kafka_ssl_ca_cert` when non-null; otherwise `ssl_ca_cert` from the secret JSON |
| `ssl_endpoint_identification_algorithm` | `https` |

Flow:

1. `data.aws_secretsmanager_secret_version.external_kafka` reads the secret at plan/apply time.
2. `locals.external_kafka_creds` parses `secret_string` with `jsondecode`.
3. Username and password accept either `sasl_plain_*` or `username` / `password` keys; values are trimmed with `trimspace`.
4. `lifecycle.precondition` blocks apply if username or password resolve to empty strings.

### Optional example: Aiven Kafka as the source

When `example_aiven_source_kafka_service_name` is non-null and non-empty after `trimspace`, Terraform creates `aiven_service_integration_endpoint.aiven_kafka_source_example` (count = 1).

| Data source | Role |
| --- | --- |
| `data.aiven_kafka.example_source` | Existing Kafka service in `local.example_aiven_kafka_project` |
| `data.aiven_project.example_kafka_project` | Project CA certificate for TLS trust |

`local.example_aiven_kafka_project` is `coalesce(var.example_aiven_source_kafka_project_name, var.aiven_project_name)`.

The example endpoint is also `endpoint_type = "external_kafka"` with the same SASL/SSL settings. Connection details come from the Aiven provider:

- `bootstrap_servers` → `data.aiven_kafka.example_source[0].service_uri`
- `sasl_plain_username` / `sasl_plain_password` → Kafka data source `username` / `password`
- `ssl_ca_cert` → `data.aiven_project.example_kafka_project[0].ca_cert`

The endpoint is created in `var.aiven_project_name` with name `var.example_aiven_kafka_source_endpoint_name` (default `aiven-kafka-source-example`). Leave `example_aiven_source_kafka_service_name` unset or null to skip this resource.

The same `external_kafka_user_config` fields do not have to come from `data.aiven_kafka` / `data.aiven_project`. You can map them from **locals** or **input variables** instead—for example `terraform_remote_state` outputs from `infra-setup`, values passed in from another workspace, or sensitive variables backed by Secrets Manager (same pattern as the primary external endpoint).

### Hub and spoke endpoints (commented in `main.tf`)

At the bottom of `main.tf`, two blocks are **commented out** and are not applied by default. They sketch dedicated integration endpoints for the diskless hub/spoke layout provisioned in `infra-setup`:

| Commented resource | Intended source | `endpoint_name` (in snippet) |
| --- | --- | --- |
| `aiven_service_integration_endpoint.aiven_kafka_spoke_endpoint` | `data.aiven_kafka.spoke_kafka_1` | `aiven_kafka_source_endpoint` |
| `aiven_service_integration_endpoint.aiven_kafka_hub_endpoint` | `data.aiven_kafka.hub_kafka` | `aiven_kafka_source_endpoint` |

Each uses the same `external_kafka` + SASL_SSL + SCRAM-SHA-256 shape as the active example:

- `bootstrap_servers` ← Kafka `service_uri`
- `sasl_plain_username` / `sasl_plain_password` ← Kafka data source credentials
- `ssl_ca_cert` ← project or service CA (the spoke snippet references `data.aiven_kafka.spoke_kafka`; align with `data.aiven_project` or the hub service CA when you uncomment)

To use them:

1. Uncomment the resource(s) you need and add matching `data "aiven_kafka"` blocks (or point at resources if this root module shares state with `infra-setup`).
2. Give each endpoint a **distinct** `endpoint_name` if both hub and spoke are enabled (the snippet reuses the same name for both).
3. Alternatively, keep the resources commented and wire `external_kafka_user_config` from **locals** fed by variables or remote state—no live `data.aiven_kafka` lookup required in this workspace.

That local/variable approach is useful when `project-integrations` runs as a **separate stack** from `infra-setup`: pass bootstrap URI, SCRAM user/password, and CA PEM via outputs → variables → locals, without importing `aiven_kafka.hub_kafka` / `aiven_kafka.spoke_kafka_1` into the same state.

### Security and state

- Credentials for the external cluster live in Secrets Manager; bootstrap servers stay in Terraform variables.
- Terraform still resolves secret values during apply; they can appear in **state** and in logs if misconfigured. Use encrypted remote state, restrict state access, and avoid printing sensitive values in CI.
- The Aiven API token is sensitive; pass it via environment or a secrets-backed variable, not a committed file.

## Repository layout

| File | Role |
| --- | --- |
| `provider.tf` | Terraform block, `aiven` (~> 4.0) and `aws` (~> 5.0) providers |
| `variables.tf` | Input variables |
| `main.tf` | Secrets Manager data source, locals, integration endpoint resources |
| `outputs.tf` | Endpoint IDs and names for wiring into other stacks |

## Prerequisites

- **Aiven**: API token with permission to manage the target project and integration endpoints.
- **AWS**: Credentials and region available to the `aws` provider (environment, profile, OIDC role in CI, etc.).
- **IAM**: `secretsmanager:GetSecretValue` on the configured secret (and `kms:Decrypt` if the secret uses a customer-managed KMS key).

## Variables (summary)

| Variable | Purpose |
| --- | --- |
| `aiven_api_token` | Aiven API token (sensitive) |
| `aiven_project_name` | Project where endpoints are created |
| `external_kafka_endpoint_name` | Name of the external Kafka endpoint |
| `external_kafka_bootstrap_servers` | Comma-separated `host:port` bootstrap list |
| `aws_region` | Region for Secrets Manager and the AWS provider |
| `external_kafka_credentials_secret_id` | Secret name or ARN |
| `external_kafka_ssl_ca_cert` | Optional PEM override (sensitive; default null) |
| `example_aiven_source_kafka_service_name` | Optional; enables Aiven-Kafka-as-source example |
| `example_aiven_source_kafka_project_name` | Optional; project owning that Kafka service (defaults to `aiven_project_name`) |
| `example_aiven_kafka_source_endpoint_name` | Name for the example endpoint (default `aiven-kafka-source-example`) |

## AWS Secrets Manager JSON shape

Store a single JSON object as the secret string. Supported keys:

| Key | Required | Notes |
| --- | --- | --- |
| `sasl_plain_username` or `username` | Yes | SCRAM user |
| `sasl_plain_password` or `password` | Yes | SCRAM password |
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

## Outputs

| Output | Description |
| --- | --- |
| `external_kafka_endpoint_id` | ID of `aiven_service_integration_endpoint.external_kafka` |
| `external_kafka_endpoint_name` | Configured `endpoint_name` for the external Kafka endpoint |
| `aiven_kafka_source_example_endpoint_id` | ID of the optional example endpoint, or `null` when the example is disabled |

## Usage

From this directory:

```bash
terraform init
terraform plan -var-file="your.tfvars"
terraform apply -var-file="your.tfvars"
```

Use `external_kafka_endpoint_id` (and optionally `aiven_kafka_source_example_endpoint_id`) when defining `aiven_service_integration` resources in another `.tf` file or workspace (for example MM2 source integrations).

## Relation to `infra-setup`

The sibling `infra-setup` stack provisions hub/spoke Kafka and MirrorMaker services. This stack only registers how to reach an external (or example Aiven) Kafka inside the project. Wire the returned endpoint IDs into service integrations there or in a follow-up stack once ordering and dependencies are clear.
