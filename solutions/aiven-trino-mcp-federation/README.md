# 🔎 Live Orders → Iceberg → Trino MCP → AI Agent on Aiven

Ask plain-English questions about a **live order stream** and get answers backed
by real SQL — no SQL written by you. A long-running app streams orders into
**Kafka → Iceberg-on-S3**, **Trino** queries that Iceberg data through
**Snowflake Open Catalog**, and an **Amazon Bedrock**–powered chat agent drives
Trino through the **Trino MCP** server. Everything runs on **Aiven Apps**.

> This solution builds on [`aiven-iceberg-tutorial`](../aiven-iceberg-tutorial/)
> for the Kafka → Iceberg pipeline and reuses its Snowflake Open Catalog. See
> [`PLAN-SIMPLIFIED.md`](PLAN-SIMPLIFIED.md) for the full design and decisions.

## ✨ What's inside

- 🟢 **`live-orders`** — a Go producer that continuously streams mock ecommerce
  orders to Kafka at a configurable rate.
- ❄️ **Kafka → Iceberg sink → S3** + **Snowflake Open Catalog** — reused from the
  Iceberg tutorial; lands the live orders in an Iceberg table.
- 🔭 **`query-app`** — **Trino** + a co-located **Trino MCP** server
  ([`tuannvm/mcp-trino`](https://github.com/tuannvm/mcp-trino)), read-only.
- 🤖 **`query-agent`** — a web chat (FastAPI + [Strands Agents](https://strandsagents.com/)
  + **Amazon Bedrock** Claude) that turns questions into Trino queries via MCP.

## 🏗 Architecture

```
  ┌─────────────┐   orders    ┌──────────┐  Kafka Connect   ┌──────────────┐
  │ live-orders │ ──────────► │  Kafka   │ ───────────────► │ Iceberg / S3 │
  │ (Go worker) │  ~100/min   │ (Aiven)  │  Iceberg sink    │  (us-west-2) │
  └─────────────┘             └──────────┘                  └──────┬───────┘
                                          registered in            │ metadata
                                    Snowflake Open Catalog ◄────────┘ (REST catalog)
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
> `query-app` pins `s3.region=us-west-2`. Details in [`PLAN-SIMPLIFIED.md`](PLAN-SIMPLIFIED.md).
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

Stand up Kafka, the Kafka Connect Iceberg sink, S3, and Snowflake Open Catalog by
following [`aiven-iceberg-tutorial`](../aiven-iceberg-tutorial/) (AWS setup →
Open Catalog → Aiven Kafka). The only change here: instead of its one-shot
producer, you'll run **`live-orders`** to stream continuously into the same
`order` topic. Everything downstream (sink → S3 → Open Catalog) is unchanged.

<a id="the-three-apps"></a>
## 📦 The three apps

Each app is self-contained with its own README, `Containerfile`, and a prefixed
`*-docker-compose.yml` so it's easy to pick during Aiven Apps deployment. **No
secrets are committed or baked into images** — all config is supplied via
environment variables (Aiven Apps secrets / a local git-ignored `.env`).

| App | What it does | Deploy as | Details |
|-----|--------------|-----------|---------|
| [`live-orders/`](live-orders/) | Streams live orders to Kafka | worker (no port) | [README](live-orders/README.md) |
| [`query-app/`](query-app/) | Trino + Trino MCP (read-only) | service (MCP `:9097`) | [README](query-app/README.md) |
| [`query-agent/`](query-agent/) | Web chat over the Trino MCP | web app (`:8000`) | [README](query-agent/README.md) |

<a id="run-it-locally"></a>
## 💻 Run it locally

After the base pipeline exists and Snowflake Open Catalog is wired:

1. **Bedrock identity** (one-time) — provision the scoped IAM user, then create
   its access key:
   ```bash
   cd query-agent && ./setup-bedrock.sh
   aws iam create-access-key --user-name query-agent-bedrock   # capture the keys
   ```

2. **Stream live orders:**
   ```bash
   cd live-orders && cp .env.example .env   # fill Kafka creds
   docker compose -f live-orders-docker-compose.yml up --build
   ```

3. **Start Trino + MCP:**
   ```bash
   cd query-app && cp .env.example .env     # fill Open Catalog creds
   docker compose -f query-app-docker-compose.yml up
   ```

4. **Start the chat agent:**
   ```bash
   cd query-agent && cp .env.example .env   # fill Bedrock keys; MCP URL=http://localhost:9097/mcp
   docker compose -f query-agent-docker-compose.yml up --build
   ```

Open <http://localhost:8000> and ask: *“Top 5 products by total revenue”*,
*“How many orders in the last hour?”*, *“Average order amount by status.”*

<a id="deploy-to-aiven-apps"></a>
## 🚀 Deploy to Aiven Apps (eu-west-1)

Deploy each app from its `*-docker-compose.yml`, supplying the env vars/secrets in
the Aiven Apps setup. Notes:

- **Pin image tags** before deploying (`trinodb/trino:<version>`,
  `ghcr.io/tuannvm/mcp-trino:<tag>`) — `:latest` is for local dev.
- **Expose `query-app`'s MCP port** (`9097`) so `query-agent` can reach
  `https://<query-app-host>/mcp`; enable `MCP_OAUTH_ENABLED` + `MCP_JWT_SECRET`
  and set the matching `TRINO_MCP_JWT` on `query-agent`.
- **`query-agent`** serves the web UI on port `8000`; set `TRINO_MCP_URL` to the
  exposed MCP endpoint.

<a id="configuration-reference"></a>
## ⚙️ Configuration reference

Per-app variables are documented in each app's README. The secrets you supply at
deploy time:

- **Kafka** (`live-orders`): `KAFKA_SERVICE_URI`, `KAFKA_USERNAME`, `KAFKA_PASSWORD`.
- **Open Catalog** (`query-app`): `ICEBERG_CATALOG_URI`, `ICEBERG_OAUTH_CREDENTIAL`,
  `ICEBERG_OAUTH_SCOPE`, `ICEBERG_WAREHOUSE`; optional MCP `MCP_JWT_SECRET`.
- **Bedrock** (`query-agent`): `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`,
  `AWS_REGION`, `BEDROCK_MODEL_ID`; plus `TRINO_MCP_URL`, `TRINO_MCP_JWT`.

<a id="cleanup"></a>
## 🧹 Cleanup

- Stop/delete the three Aiven Apps (`live-orders`, `query-app`, `query-agent`).
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
