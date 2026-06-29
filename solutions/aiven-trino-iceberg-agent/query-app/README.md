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

- **Read-only (defense in depth).** Two independent layers deny writes/DDL:
  mcp-trino's own guard (`TRINO_ALLOW_WRITE_QUERIES=false`, the default — its
  `execute_query` permits only SELECT/SHOW/DESCRIBE/EXPLAIN), backed by Trino's
  built-in `access-control.name=read-only` at the engine. Either alone is
  sufficient; together they fail safe even if one is misconfigured.
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
| `MCP_OAUTH_ENABLED` | no | `true` to require a JWT on the MCP endpoint (default `false`). |
| `MCP_JWT_SECRET` | when enabled | HMAC (HS256) secret, ≥32 bytes; query-agent signs its JWT with the same value. |
| `MCP_JWT_AUDIENCE` | when enabled | Expected `aud` claim (→ `OIDC_AUDIENCE`). **Required** when OAuth is on — without it mcp-trino logs `audience is required`. Default `trino-mcp`. |
| `MCP_JWT_ISSUER` | when enabled | Expected `iss` claim (→ `OIDC_ISSUER`). Default `aiven-query-agent`. |

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

`mcp-smoke-test.sh` instead exercises the **MCP layer** end-to-end (session →
`tools/list` → `execute_query` → write-denial), which `smoke-test.sh` bypasses by
talking to Trino directly:

```bash
./mcp-smoke-test.sh <namespace>       # against an open endpoint
source .env && ./mcp-smoke-test.sh <namespace>   # mints a JWT from MCP_JWT_SECRET to test a secured one
```

> Note: with OAuth on, `initialize` returns `200` even for a bad token — the
> handshake is pre-auth. The signature is only enforced at `tools/call`, so a
> real auth test **must** invoke a tool (this script does).

## Security / hardening

The MCP endpoint is the only externally-reachable surface, and reading *is* the
sensitive operation here — so before exposing it publicly:

1. **Authenticate the endpoint.** Set `MCP_OAUTH_ENABLED=true` with a strong
   random `MCP_JWT_SECRET` (≥32 bytes) **and** `MCP_JWT_AUDIENCE` (the validator
   rejects all tokens without an audience). The HMAC provider is symmetric:
   query-agent mints an HS256 JWT signed with the same secret and presents it as
   `Authorization: Bearer <jwt>`, with claims:

   ```json
   { "sub": "query-agent", "aud": "trino-mcp", "iss": "aiven-query-agent",
     "iat": <now>, "exp": <now + short> }
   ```

   `aud`/`iss` must match `MCP_JWT_AUDIENCE`/`MCP_JWT_ISSUER` exactly. Keep `exp`
   short — with no IdP, expiry is the only revocation. Rotate the secret.
2. **TLS only.** A bearer token over plaintext is replayable — serve `/mcp` over
   HTTPS (Aiven Apps ingress terminates TLS). The server itself warns if OAuth is
   on without HTTPS.
3. **Hide Trino.** Drop the `8080:8080` mapping in production so Trino is reachable
   only by mcp-trino over the compose network — otherwise it bypasses the auth gate.
4. **Least privilege.** Keep both read-only layers (above); scope the Open Catalog
   OAuth principal to read-only so even Trino can't write to S3/Iceberg.
5. **Limits.** `TRINO_MAX_ROWS` caps result size; add Trino query timeouts to kill
   runaway queries.

## Deploy to Aiven Apps (eu-west-1)

Deploy this compose recipe to Aiven Apps and supply the variables above as
env/secrets. Expose the **mcp-trino** port (`9097`) externally so `query-agent`
can reach `https://<app-host>/mcp`; enable `MCP_OAUTH_ENABLED` + `MCP_JWT_SECRET`
for the exposed endpoint. Trino's `8080` can stay internal.

> Pin both images to released tags (`trinodb/trino:<version>`,
> `ghcr.io/tuannvm/mcp-trino:<tag>`) before deploying — `:latest` is for local dev.
```
