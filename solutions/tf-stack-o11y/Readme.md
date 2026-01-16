# Terraform Stack Observability Module

This Terraform module sets up a complete observability stack for Aiven services, providing centralized logging, metrics collection, and visualization capabilities.

## Overview

The module provisions the following Aiven services and integrations:

- **OpenSearch**: Centralized log storage and analysis
- **Grafana**: Metrics visualization and dashboards
- **Thanos**: Long-term metrics storage with 90-day retention
- **Service Integrations**: Automatic log and metrics collection from your Aiven services
- **Prometheus Endpoint**: External Prometheus scraping endpoint for existing monitoring tools

## Architecture

```
Source Service (e.g., Kafka, PostgreSQL, etc.)
    │
    ├─── Logs ────────> OpenSearch (os-logs)
    │
    ├─── Metrics ─────> Thanos (thanos-metrics-demo)
    │                      │
    │                      └───> Grafana (metrics-dashboard)
    │
    └─── Prometheus ──> Prometheus Endpoint (external scraping)
```

## Features

- **Centralized Logging**: All service logs are automatically forwarded to OpenSearch
- **Metrics Collection**: Service metrics are stored in Thanos with 90-day retention
- **Grafana Dashboards**: Pre-configured Grafana instance connected to Thanos
- **Prometheus Integration**: External Prometheus endpoint for existing monitoring infrastructure
- **Configurable Plans**: Customize service plans based on your requirements
- **Maintenance Windows**: Configurable maintenance schedules

## Prerequisites

- Aiven account with API token
- Existing Aiven project
- Terraform >= 1.0
- Aiven Terraform provider >= 4.38.0

## Usage

### Basic Example

```hcl
module "observability" {
  source = "./modules/metrics-logs"

  # Required variables
  project              = "my-aiven-project"
  aiven_api_token      = var.aiven_api_token
  cloud_name           = "aws-us-east-1"
  source_service_name  = "my-kafka-service"
  prom_name            = "prometheus-endpoint"
  prom_username        = "promuser"
  prom_password        = "secure-password"
  
  # Optional variables (with defaults)
  os_log_integration_plan = "startup-16"
  grafana_integration_plan = "startup-8"
  thanos_plan             = "business-8"
  maint_dow                = "saturday"
  maint_time               = "10:00:00"
}
```

### Complete Example with terraform.tfvars

1. Create a `terraform.tfvars` file:

```hcl
aiven_api_token      = "your-aiven-api-token"
project              = "my-aiven-project"
cloud_name           = "aws-us-east-1"
source_service_name  = "my-kafka-service"
prom_name            = "prometheus-endpoint"
prom_username        = "promuser"
prom_password        = "secure-password-here"

# Optional: Customize service plans
os_log_integration_plan = "startup-16"
grafana_integration_plan = "startup-8"
thanos_plan             = "business-8"
maint_dow               = "saturday"
maint_time              = "10:00:00"
```

2. Initialize Terraform:

```bash
cd modules/metrics-logs
terraform init
```

3. Review the plan:

```bash
terraform plan -var-file="../../terraform.tfvars"
```

4. Apply the configuration:

```bash
terraform apply -var-file="../../terraform.tfvars"
```

## Variables

### Required Variables

| Variable | Type | Description |
|----------|------|-------------|
| `project` | string | Aiven project name |
| `aiven_api_token` | string | Aiven API token for authentication |
| `cloud_name` | string | Cloud provider and region (e.g., "aws-us-east-1") |
| `source_service_name` | string | Name of the Aiven service to monitor |
| `prom_name` | string | Name for the Prometheus endpoint |
| `prom_username` | string | Username for Prometheus endpoint authentication |
| `prom_password` | string | Password for Prometheus endpoint authentication |

### Optional Variables

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `os_log_integration_plan` | string | `"startup-16"` | OpenSearch service plan for logs |
| `grafana_integration_plan` | string | `"startup-8"` | Grafana service plan |
| `thanos_plan` | string | `"business-8"` | Thanos service plan for metrics |
| `maint_dow` | string | `"saturday"` | Maintenance window day of week |
| `maint_time` | string | `"10:00:00"` | Maintenance window time (HH:MM:SS) |

## Resources Created

### Services

1. **OpenSearch** (`os-logs`)
   - Service name: `os-logs`
   - Purpose: Centralized log storage
   - Index retention: 3 days (configurable)
   - Index prefix: `logs`

2. **Grafana** (`metrics-dashboard`)
   - Service name: `metrics-dashboard`
   - Purpose: Metrics visualization
   - Alerting: Enabled
   - Public access: Disabled (private by default)

3. **Thanos** (`thanos-metrics-demo`)
   - Service name: `thanos-metrics-demo`
   - Purpose: Long-term metrics storage
   - Retention: 90 days
   - Query timeout: 3 minutes
   - Storage alert threshold: 100 GB

### Integrations

1. **Logging Integration**: Routes logs from `source_service_name` to OpenSearch
2. **Metrics Integration**: Routes metrics from `source_service_name` to Thanos
3. **Dashboard Integration**: Connects Grafana to Thanos for visualization
4. **Prometheus Integration**: Creates a Prometheus endpoint for external scraping

## Accessing Services

After deployment, you can access the services:

- **Grafana**: Access via Aiven Console → Service → Connection Information
- **OpenSearch**: Access via Aiven Console → Service → Connection Information
- **Prometheus Endpoint**: Use the endpoint URL and credentials from Aiven Console

## Configuration Details

### OpenSearch Log Configuration

- **Index Prefix**: `logs`
- **Index Retention**: 3 days maximum
- Logs are automatically indexed by date

### Thanos Configuration

- **Retention**: 90 days
- **Query Timeout**: 3 minutes
- **Storage Alert**: Triggers at 100 GB usage

### Grafana Configuration

- **Alerting**: Enabled
- **Public Access**: Disabled (private access only)

## Notes

- The module uses **Thanos** instead of M3DB for metrics storage (M3DB is commented out in the code)
- This module is designed for **single service monitoring**. For multiple services, you may need to call the module multiple times or modify the `source_service_name` variable
- The Prometheus endpoint allows you to integrate with existing Prometheus scraping infrastructure
- All services are configured with maintenance windows to minimize disruption

## Troubleshooting

### Service Integration Issues

If logs or metrics are not appearing:

1. Verify the `source_service_name` matches an existing service in your project
2. Check service integration status in Aiven Console
3. Ensure the source service is running and generating logs/metrics

### Access Issues

If you cannot access Grafana or OpenSearch:

1. Check service status in Aiven Console
2. Verify connection information and credentials
3. Ensure network/firewall rules allow access

### Prometheus Endpoint

To use the Prometheus endpoint:

1. Retrieve the endpoint URL from Aiven Console
2. Configure your Prometheus server to scrape using the provided credentials
3. Use the `prom_username` and `prom_password` for basic authentication

## Example Prometheus Configuration

```yaml
scrape_configs:
  - job_name: 'aiven-services'
    basic_auth:
      username: 'promuser'
      password: 'secure-password'
    static_configs:
      - targets: ['<prometheus-endpoint-url>']
```

## Cost Considerations

Service costs depend on the selected plans:

- **OpenSearch**: Based on `os_log_integration_plan` (default: `startup-16`)
- **Grafana**: Based on `grafana_integration_plan` (default: `startup-8`)
- **Thanos**: Based on `thanos_plan` (default: `business-8`)

Review [Aiven pricing](https://aiven.io/pricing) for current plan costs and adjust plans based on your requirements.

## Support

For issues or questions:
- Check the [Aiven Documentation](https://docs.aiven.io/)
- Review Terraform provider documentation
- Contact Aiven support for service-specific issues
