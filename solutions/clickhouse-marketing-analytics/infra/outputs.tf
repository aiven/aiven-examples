# ClickHouse
output "service_host" {
  value = aiven_clickhouse.campaign_analytics.service_host
}

output "https_port" {
  description = "HTTPS interface port - use as AIVEN_CH_PORT for the ingest service"
  value       = [for c in aiven_clickhouse.campaign_analytics.components : c.port if c.component == "clickhouse_https"]
}

output "native_port" {
  value = [for c in aiven_clickhouse.campaign_analytics.components : c.port if c.component == "clickhouse"]
}

output "demo_user" {
  value = aiven_clickhouse_user.demo.username
}

output "demo_password" {
  value     = aiven_clickhouse_user.demo.password
  sensitive = true
}

output "avnadmin_password" {
  description = "For applying the DDL files (demo_ingest is SELECT+INSERT only)"
  value       = aiven_clickhouse.campaign_analytics.service_password
  sensitive   = true
}

# Valkey (ingestion buffer + shared config store)
output "valkey_host" {
  value = aiven_valkey.ingest_buffer.service_host
}

output "valkey_port" {
  value = aiven_valkey.ingest_buffer.service_port
}

output "valkey_uri" {
  description = "Full valkeys:// connection URI (TLS) - use as AIVEN_VALKEY_URI for the ingest service"
  value       = aiven_valkey.ingest_buffer.service_uri
  sensitive   = true
}

# Observability (Thanos + Grafana)
output "thanos_remote_write_uri" {
  description = "Prometheus remote-write endpoint for the OTel Collector's prometheusremotewrite exporter"
  value       = one(aiven_thanos.metrics.thanos[*].receiver_remote_write_uri)
  sensitive   = true
}

output "grafana_url" {
  value = "https://${aiven_grafana.dashboards.service_host}:${aiven_grafana.dashboards.service_port}"
}

output "grafana_user" {
  value = aiven_grafana.dashboards.service_username
}

output "grafana_password" {
  value     = aiven_grafana.dashboards.service_password
  sensitive = true
}

output "thanos_user" {
  value = aiven_thanos.metrics.service_username
}

output "thanos_password" {
  value     = aiven_thanos.metrics.service_password
  sensitive = true
}
