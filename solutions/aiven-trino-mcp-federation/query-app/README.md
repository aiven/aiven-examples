# query-app

Trino + a co-located **Trino MCP server**, packaged for Aiven Apps. Trino queries
the live order data in Iceberg-on-S3 through **Snowflake Open Catalog**; the MCP
server ([`tuannvm/mcp-trino`](https://github.com/tuannvm/mcp-trino)) exposes Trino
to the [`query-agent`](../query-agent/) over MCP.

```
query-agent ──MCP/HTTP──► mcp-trino ──SQL──► Trino ──► Snowflake Open Catalog ──► Iceberg / S3
```

## Layout

```
query-app/
├── query-app-docker-compose.yml    # trino + mcp-trino
├── .env.example                # config (secrets via env, never committed)
└── trino/etc/
    ├── config.properties       # single-node Trino
    ├── node.properties
    ├── jvm.config
    ├── log.properties
    ├── access-control.properties   # read-only enforcement
    └── catalog/iceberg.properties  # Open Catalog REST + ${ENV:...} secrets
```

## Key design choices

- **Read-only.** mcp-trino has no read-only mode and runs arbitrary SQL via its
  `execute_query` tool, so the guarantee is enforced at the engine with Trino's
  built-in `access-control.name=read-only` — all writes/DDL are denied.
- **Secrets via env.** `iceberg.properties` uses Trino's `${ENV:VAR}` expansion;
  catalog credentials come from env vars (Aiven Apps secrets / local `.env`).
  Nothing sensitive is in the repo or the image.
- **Cross-region S3 (Path A).** Trino runs in eu-west-1 but the bucket is in
  us-west-2, so `s3.region=us-west-2` (region follows the data, not the compute —
  else `301 PermanentRedirect`). Open Catalog vends temp S3 creds
  (`vended-credentials-enabled=true`), so Trino needs no AWS keys. Expect higher
  query latency from the trans-Atlantic S3 reads.

## Configuration

| Variable | Required | Notes |
|----------|----------|-------|
| `ICEBERG_CATALOG_URI` | yes | Snowflake Open Catalog REST URI (`https://<account>.us-west-2.snowflakecomputing.com/polaris/api/catalog`). |
| `ICEBERG_OAUTH_CREDENTIAL` | yes | `<client-id>:<client-secret>` for the catalog. |
| `ICEBERG_OAUTH_SCOPE` | yes | e.g. `PRINCIPAL_ROLE:<role>`. |
| `ICEBERG_WAREHOUSE` | yes | Open Catalog catalog/warehouse name. |
| `MCP_OAUTH_ENABLED` | no | `true` to require JWT on the MCP endpoint (default `false`). |
| `MCP_JWT_SECRET` | when enabled | HMAC secret; query-agent signs its JWT with the same value. |

## Run locally

```bash
cp .env.example .env      # fill in Open Catalog values
docker compose -f query-app-docker-compose.yml up    # (reads .env)
```

- Trino UI/CLI: `http://localhost:8080` (catalog `iceberg`).
- MCP endpoint: `http://localhost:9097/mcp`.

Quick check with the Trino CLI:

```bash
docker exec -it trino trino
trino> SHOW SCHEMAS FROM iceberg;
trino> SELECT count(*) FROM iceberg.<namespace>.orders;
```

## Smoke test

`smoke-test.sh` runs the keystone check (Trino → Open Catalog → S3) against a
running container:

```bash
./smoke-test.sh                       # catalogs + schemas in iceberg
./smoke-test.sh <namespace>           # + tables in that namespace
./smoke-test.sh <namespace> <table>   # + SELECT count(*) (default table: orders)
```

## Deploy to Aiven Apps (eu-west-1)

Deploy this compose recipe to Aiven Apps and supply the variables above as
env/secrets. Expose the **mcp-trino** port (`9097`) externally so `query-agent`
can reach `https://<app-host>/mcp`; enable `MCP_OAUTH_ENABLED` + `MCP_JWT_SECRET`
for the exposed endpoint. Trino's `8080` can stay internal.

> Pin both images to released tags (`trinodb/trino:<version>`,
> `ghcr.io/tuannvm/mcp-trino:<tag>`) before deploying — `:latest` is for local dev.
```
