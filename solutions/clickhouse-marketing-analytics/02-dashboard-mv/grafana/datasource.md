# Grafana datasource setup (Aiven for ClickHouse)

1. In Aiven for Grafana (or any Grafana ≥ 10), install the official
   **ClickHouse** plugin (`grafana-clickhouse-datasource`).
2. Add a datasource:
   - **Server address**: your service host (`...aivencloud.com`)
   - **Port**: the HTTPS port from the service overview; **Protocol**: HTTP(S), **Secure**: on
   - **Username / password**: `avnadmin` / service password
   - **Default database**: the database holding `campaign_events` (local Docker: `campaign_analytics`)
3. Import `dashboard.json` (Dashboards → Import) and pick that datasource when prompted.

Panels read the rollups (`daily_campaign_rollup`, `funnel_rollup`,
`email_health_rollup`) except email-by-hour, which partition-prunes the raw
table. With `live/run_day90.sh` streaming, the day-90 stat panel and the
revenue series climb in real time on a 5s refresh — the refresh stays cheap
because nothing here scans raw history. Attribution and cohort retention are
deliberately NOT on this board; run them on demand in the report page.
