# 🔎 Live Orders → Iceberg → Trino MCP → AI Agent on Aiven

Ask plain-English questions about a **live order stream** and get answers backed
by real SQL — no SQL written by you. A long-running app writes orders into
**Aiven for PostgreSQL**, a **Debezium CDC source connector** streams the
changes into **Kafka**, the **Iceberg sink** lands them in **Iceberg-on-S3**,
**Trino** queries that Iceberg data through **Snowflake Open Catalog**, and an
**Amazon Bedrock**–powered chat agent drives Trino through the **Trino MCP**
server. An end-to-end tour of Aiven: PostgreSQL, Kafka, Kafka Connect, and
Aiven Apps.

> This solution builds on [`aiven-iceberg-tutorial`](../aiven-iceberg-tutorial/)
> for the Kafka → Iceberg pipeline and reuses its Snowflake Open Catalog.

## ✨ What's inside

- 🟢 **`live-orders`** — a Go worker that continuously INSERTs mock ecommerce
  orders into Postgres and UPDATEs their status lifecycle
  (`PENDING → PAID → SHIPPED → DELIVERED`, some `CANCELLED`).
- 🐘 **Postgres → Debezium CDC → Kafka** — a Debezium PostgreSQL source
  connector on Aiven Kafka Connect streams inserts *and* updates
  ([`cdc/`](cdc/)).
- ❄️ **Kafka → Iceberg sink → S3** + **Snowflake Open Catalog** — an
  upsert-mode Iceberg sink keeps one current row per order in the
  `moneylion.live_orders` table.
- 🔭 **`query-app`** — **Trino** + a co-located **Trino MCP** server
  ([`tuannvm/mcp-trino`](https://github.com/tuannvm/mcp-trino)), read-only.
- 🤖 **`query-agent`** — a web chat (FastAPI + [Strands Agents](https://strandsagents.com/)
  + **Amazon Bedrock** Claude) that turns questions into Trino queries via MCP.

## 🏗 Architecture

```
  ┌─────────────┐  INSERT/   ┌────────────┐  Debezium CDC   ┌──────────┐  Iceberg sink   ┌──────────────┐
  │ live-orders │  UPDATE    │ PostgreSQL │ ──────────────► │  Kafka   │ ──────────────► │ Iceberg / S3 │
  │ (Go worker) │ ─────────► │  (Aiven)   │  Kafka Connect  │ (Aiven)  │  (upsert mode)  │  (us-west-2) │
  └─────────────┘  ~100/min  └────────────┘                 └──────────┘                 └──────┬───────┘
                                                       registered in                            │ metadata
                                                 Snowflake Open Catalog ◄────────────────────────┘ (REST catalog)
                                                 ▲
   ┌──────────── query-app (Aiven Apps) ─────────┼──────────┐
   │  mcp-trino (HTTP :9097/mcp) ──► Trino ───────┘ reads    │
   │                                  (read-only)  Iceberg/S3 │
   └──────────────────┬───────────────────────────────────────┘
                      │ MCP over HTTP (StreamableHTTP + optional JWT)
   ┌──────────────────▼──── query-agent (Aiven Apps) ─────────┐
   │  Web chat ──► Strands agent ──► Amazon Bedrock (Claude)   │
   └───────────────────────────────────────────────────────────┘
```

**Flow:** question → Strands agent (Bedrock) → Trino MCP tools (discover schema,
run read-only `SELECT`) → Trino reads Iceberg via Open Catalog → answer + the SQL.

> **Regions (Path A):** the apps and Bedrock run in **eu-west-1** (where Aiven
> Apps on AWS is available); the S3 bucket + Open Catalog stay in **us-west-2**.
> Trino reads S3 cross-region — correct, just higher latency. This is why
> `query-app` pins `s3.region=us-west-2`.
>
> **Freshness:** orders reach Iceberg through the Kafka→Iceberg sink, which
> commits on an interval, so the agent queries *near*-real-time data.

## 📑 Contents

- [Prerequisites](#prerequisites)
- [Base pipeline (Kafka → Iceberg)](#base-pipeline)
- [The three apps](#the-three-apps)
- [Run it locally](#run-it-locally)
- [Deploy to Aiven Apps](#deploy-to-aiven-apps)
- [Configuration reference](#configuration-reference)
- [Cleanup](#cleanup)
- [Helpful resources](#helpful-resources)

<a id="prerequisites"></a>
## 🛠 Prerequisites

- **Aiven account** + API token + project (Kafka, Kafka Connect, **Aiven Apps**
  access — Aiven Apps on AWS is currently **eu-west-1** only).
- **AWS account** with an S3 bucket and **Amazon Bedrock** (Claude) access in
  **eu-west-1** (auto-enabled on first invocation).
- **Snowflake Open Catalog** with `ORGADMIN` (or equivalent) — reused from the
  Iceberg tutorial.
- **Docker / Podman**, **Go**, **Python 3.12+**, **Terraform**, **AWS CLI**.

<a id="base-pipeline"></a>
## ❄️ Base pipeline (Kafka → Iceberg)

Stand up Kafka, Kafka Connect, S3, and Snowflake Open Catalog by following
[`aiven-iceberg-tutorial`](../aiven-iceberg-tutorial/) (AWS setup → Open
Catalog → Aiven Kafka). On top of that, this solution adds the **CDC leg**:
an Aiven for PostgreSQL service that `live-orders` writes into, a **Debezium
PostgreSQL source connector** that streams the changes to Kafka (topic
`live_orders.public.orders`), and a **second Iceberg sink** in upsert mode
that lands them in `moneylion.live_orders`. Full setup — Postgres init SQL and
both connector configs — lives in [`cdc/`](cdc/).

<a id="the-three-apps"></a>
## 📦 The three apps

Each app is self-contained with its own README, `Dockerfile`, and a
`compose.yaml` that Aiven Apps auto-detects during deployment. **No
secrets are committed or baked into images** — all config is supplied via
environment variables (Aiven Apps secrets / a local git-ignored `.env`).

| App | What it does | Deploy as | Details |
|-----|--------------|-----------|---------|
| [`live-orders/`](live-orders/) | Writes live orders to Postgres | worker (no port) | [README](live-orders/README.md) |
| [`query-app/`](query-app/) | Trino + Trino MCP (read-only) | service (MCP `:9097`) | [README](query-app/README.md) |
| [`query-agent/`](query-agent/) | Web chat over the Trino MCP | web app (`:8000`) | [README](query-agent/README.md) |

<a id="run-it-locally"></a>
## 💻 Run it locally

After the base pipeline exists and Snowflake Open Catalog is wired, first do the
one-time **Bedrock identity** setup, then bring up the stack.

**Bedrock identity** (one-time) — provision the scoped IAM user, then create its
access key:
```bash
cd query-agent && ./setup-bedrock.sh
aws iam create-access-key --user-name query-agent-bedrock   # capture the keys
```

### Option A — whole stack, one command (recommended)

The root [`compose.yaml`](compose.yaml) runs all three services together (shared
network; query-agent reaches query-app by service name):
```bash
cp .env.example .env      # consolidated: Postgres + Open Catalog + Bedrock
docker compose up --build
```

### Option B — one app at a time

Each app also has its own `compose.yaml` and `.env.example`, handy for iterating
on a single service (this is also the unit you deploy to Aiven Apps):
```bash
cd live-orders && cp .env.example .env && docker compose up --build   # Postgres writer
cd query-app   && cp .env.example .env && docker compose up           # Trino + MCP
cd query-agent && cp .env.example .env && docker compose up --build   # chat (set MCP URL=http://localhost:9097/mcp)
```

Either way, open <http://localhost:8000> and ask: *“Top 5 products by total
revenue”*, *“How many orders in the last hour?”*, *“Average order amount by status.”*

<a id="deploy-to-aiven-apps"></a>
## 🚀 Deploy to Aiven Apps (eu-west-1)

> **Deployment source.** Aiven Apps deploys this project from a standalone repo
> ([`rezaaiven/aiven-trino-iceberg-agent`](https://github.com/rezaaiven/aiven-trino-iceberg-agent),
> branch `main`) where this folder's contents sit at the repo root. That repo is a
> `git subtree` mirror of `solutions/aiven-trino-iceberg-agent/` in the
> `aiven/aiven-examples` monorepo — make changes here, commit them, then re-sync:
>
> ```bash
> # run from the aiven-examples repo root, after committing your changes
> git subtree push --prefix=solutions/aiven-trino-iceberg-agent iceberg-agent main
> ```
>
> The `iceberg-agent` remote points at the standalone repo. Only **committed**
> changes are pushed.

Onboard the repo against the **root [`compose.yaml`](compose.yaml)**: Aiven Apps
detects all three `build:` services and resolves each build context to its
subfolder, so you get three deployable app suggestions from the one file. They
deploy as **three separate Aiven App services** (Aiven runs one buildable service
per app) — the root compose is the shared source, not a single combined
container. (You can equally onboard one app from its own `compose.yaml`.)

**Order matters.** Aiven Apps has no app-to-app service discovery — each service
gets only a public URL (`https://<uuid>-<port>.eur-1.aiven.app`), and there's no
internal DNS or automatic URL injection. So `query-app` must exist before you can
point `query-agent` at it. Deploy in this sequence:

#### 1. `query-app` (Trino + Trino MCP) — deploy first

- Set the Open Catalog env: `ICEBERG_CATALOG_URI`, `ICEBERG_OAUTH_CREDENTIAL`,
  `ICEBERG_OAUTH_SCOPE`, `ICEBERG_WAREHOUSE`.
- **Expose port `9097`** (the MCP endpoint).
- **Enable auth** (mandatory — see below): `MCP_OAUTH_ENABLED=true` + a strong
  `MCP_JWT_SECRET` (`openssl rand -hex 32`).
- After it deploys, **copy its public URL** — you'll get something like
  `https://<uuid>-9097.eur-1.aiven.app`. The MCP endpoint is that **+ `/mcp`**.

#### 2. `query-agent` (web chat) — deploy second, wired to query-app

- Set the Bedrock env: `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_REGION`,
  `BEDROCK_MODEL_ID`.
- Set **`TRINO_MCP_URL`** to query-app's deployed endpoint from step 1: the
  public host (which already encodes the port as `-9097`) **plus `/mcp`**, with
  **no `:port` suffix** — e.g. `https://<uuid>-9097.eur-1.aiven.app/mcp`. The
  root compose's `http://query-app:9097/mcp` default is local-only and won't
  resolve here. Two easy mistakes: forgetting the trailing `/mcp` (the MCP
  `initialize` handshake fails → `MCPClientInitializationError`), and appending
  `:9097` (Aiven serves over HTTPS/443; the port lives in the hostname).
- Set **`MCP_JWT_SECRET`** to the **same** secret you set on query-app.
  query-agent mints a fresh short-lived HMAC JWT per request, so the token never
  expires. (`MCP_JWT_AUDIENCE`/`MCP_JWT_ISSUER` default to `trino-mcp` /
  `aiven-query-agent` and must match query-app's `OIDC_AUDIENCE`/`OIDC_ISSUER`.)
  Alternatively paste a ready-made `TRINO_MCP_JWT` — but that one **will expire**.
- Exposes the web UI on port `8000`.

#### 3. `live-orders` (Postgres writer) — independent, deploy any time

- Set the Postgres env: `POSTGRES_URI` (optional: `ORDERS_PER_MINUTE`,
  `UPDATES_PER_MINUTE`).
- Worker that also serves `/healthz`–`/readyz` on `8080`. Has no dependency on
  the other two, so its order doesn't matter — but data only reaches Iceberg
  once the [CDC connectors](cdc/) are running.

> **Security — JWT is mandatory, not optional.** `query-app`'s MCP endpoint is a
> **public internet URL** (no VPC-internal option yet), and it runs SQL against
> your data. Without `MCP_OAUTH_ENABLED` + `MCP_JWT_SECRET` it is an open,
> query-executing endpoint. Always enable it for a deployed setup.

> **Image tags are pinned** for reproducible builds — `query-app`'s Dockerfile
> uses `trinodb/trino:482` and `ghcr.io/tuannvm/mcp-trino:4.3.1`. Bump those tags
> deliberately when you want newer versions.

<a id="configuration-reference"></a>
## ⚙️ Configuration reference

Per-app variables are documented in each app's README. The secrets you supply at
deploy time:

- **Postgres** (`live-orders`): `POSTGRES_URI`.
- **CDC connectors** (Kafka Connect, not apps): see [`cdc/`](cdc/) — Debezium
  source needs the PG connection, the Iceberg sink needs the Open Catalog +
  S3 credentials.
- **Open Catalog** (`query-app`): `ICEBERG_CATALOG_URI`, `ICEBERG_OAUTH_CREDENTIAL`,
  `ICEBERG_OAUTH_SCOPE`, `ICEBERG_WAREHOUSE`; optional MCP `MCP_JWT_SECRET`.
- **Bedrock** (`query-agent`): `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`,
  `AWS_REGION`, `BEDROCK_MODEL_ID`; plus `TRINO_MCP_URL` and, for MCP auth,
  `MCP_JWT_SECRET` (mints per-request tokens) or a ready-made `TRINO_MCP_JWT`.

<a id="cleanup"></a>
## 🧹 Cleanup

- Stop/delete the three Aiven Apps (`live-orders`, `query-app`, `query-agent`).
- Delete the two CDC connectors, then **drop the replication slot**
  (`SELECT pg_drop_replication_slot('live_orders_cdc');`) before deleting the
  Postgres service — a dangling slot retains WAL forever.
- `terraform destroy` the Aiven + AWS infra (see the Iceberg tutorial).
- Remove the Snowflake Open Catalog table/namespace/catalog + connection.
- Delete the `query-agent-bedrock` IAM access key + user.

<a id="helpful-resources"></a>
## 📚 Helpful resources

- [aiven-iceberg-tutorial](../aiven-iceberg-tutorial/) — the base Kafka→Iceberg pipeline
- [Strands Agents SDK](https://strandsagents.com/) · [Strands + MCP (AWS blog)](https://aws.amazon.com/blogs/opensource/open-protocols-for-agent-interoperability-part-3-strands-agents-mcp/)
- [tuannvm/mcp-trino](https://github.com/tuannvm/mcp-trino) — the Trino MCP server
- [Trino Iceberg connector](https://trino.io/docs/current/connector/iceberg.html) · [Amazon Bedrock](https://docs.aws.amazon.com/bedrock/)
- [From Stream to Table: Real-Time Analytics](https://getkafkanated.substack.com/p/from-stream-to-table-real-time-analytics)
