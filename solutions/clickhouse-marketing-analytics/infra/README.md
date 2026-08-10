# Aiven infra — ClickHouse + Valkey

Provisions two services in the same region (default **azure-southeastasia**):

| Service | Plan | Version | Role |
|---|---|---|---|
| Aiven for ClickHouse® | `business-16` | 26.3 | analytics store (`campaign_analytics` db + `demo_ingest` user) |
| Aiven for Valkey™ | `business-8` | 9.1 | ingestion buffer (Valkey Streams) + shared runtime config store |

Both are variables (`clickhouse_plan`, `valkey_plan`, `clickhouse_version`,
`valkey_version`) if you want different sizing — the ingestion benchmark numbers
in the root README were measured on a single-node `startup-16`.

> Aiven limitation: ClickHouse databases can't be created with plain SQL — the
> `aiven_clickhouse_database` resource here is the only supported path.
> Also note `ENGINE = MergeTree` is auto-remapped to `ReplicatedMergeTree`.

Apply (manual step — not run by CI or Claude Code):

```bash
terraform init
terraform apply -var="aiven_api_token=$AIVEN_TOKEN" -var="project=<aiven-project>"
```

Then apply the DDLs (the HTTP interface takes one statement per request, so use
the client's multiquery mode — or paste the files into the Aiven console query
editor):

```bash
HOST=$(terraform output -raw service_host)
PORT=$(terraform output -json native_port | jq -r '.[0]')
for f in ../shared/schema/01_campaign_events.sql ../shared/schema/02_daily_campaign_rollup.sql; do
  clickhouse client --host "$HOST" --port "$PORT" --secure \
    --user avnadmin --password "$AIVEN_CH_PASSWORD" \
    --database campaign_analytics --multiquery < "$f"
done
```

Connection values for the ingest service (`.env.aiven` at the repo root):

```bash
terraform output -raw service_host     # AIVEN_CH_HOST
terraform output -json https_port      # AIVEN_CH_PORT
terraform output -raw demo_password    # AIVEN_CH_PASSWORD (or use avnadmin)
terraform output -raw valkey_uri       # AIVEN_VALKEY_URI (valkeys:// = TLS)
```
