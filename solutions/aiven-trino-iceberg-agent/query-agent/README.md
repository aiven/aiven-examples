# query-agent

A web chat that answers natural-language questions about the live orders. It uses
the [Strands Agents SDK](https://strandsagents.com/) with an **Amazon Bedrock**
model (Claude) and drives **Trino** through the **Trino MCP** server exposed by
[`query-app`](../query-app/).

```
browser ──► query-agent (FastAPI + Strands) ──► Amazon Bedrock (Claude)
                       │
                       └── MCP/HTTP ──► query-app (mcp-trino → Trino → Iceberg/S3)
```

The agent only talks to the Trino MCP; Trino owns the Snowflake Open Catalog /
Iceberg connection. The UI shows both the answer and the **SQL the agent ran**.

## Layout

```
query-agent/
├── app.py                          # FastAPI + Strands agent
├── static/index.html               # chat UI (self-contained)
├── requirements.txt
├── Containerfile
├── query-agent-docker-compose.yml
├── setup-bedrock.sh                # provisions the Bedrock IAM user (one-time)
└── .env.example
```

## Prerequisites

1. **Bedrock IAM identity** — run [`setup-bedrock.sh`](setup-bedrock.sh) once to
   create the scoped `query-agent-bedrock` user, then create its access key. The
   key/secret become this app's `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY`.
2. **A reachable Trino MCP endpoint** — `query-app` running locally
   (`http://localhost:9097/mcp`) or deployed (its exposed `…/mcp` URL).

## Configuration

| Variable | Required | Default | Notes |
|----------|----------|---------|-------|
| `AWS_ACCESS_KEY_ID` | yes | — | `query-agent-bedrock` key (secret). |
| `AWS_SECRET_ACCESS_KEY` | yes | — | (secret). |
| `AWS_REGION` | no | `eu-west-1` | Bedrock region. |
| `BEDROCK_MODEL_ID` | no | `eu.anthropic.claude-sonnet-4-6` | EU inference profile. |
| `TRINO_MCP_URL` | no | `http://localhost:9097/mcp` | query-app's MCP endpoint. |
| `TRINO_MCP_JWT` | when MCP auth on | — | Bearer token (HMAC JWT) for the MCP endpoint. |

## Run locally

```bash
python -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
cp .env.example .env      # fill in Bedrock keys + MCP URL
source .env
python app.py             # serves on http://localhost:8000
```

Or via Compose:

```bash
docker compose -f query-agent-docker-compose.yml up --build   # reads .env
```

Open <http://localhost:8000> and ask, e.g.:
- “How many orders in the last hour?”
- “Top 5 products by total revenue.”
- “Average order amount by status.”

## Deploy to Aiven Apps (eu-west-1)

Deploy `query-agent-docker-compose.yml` and supply the variables above as
env/secrets. Point `TRINO_MCP_URL` at query-app's externally-exposed MCP URL and
set `TRINO_MCP_JWT` if query-app has MCP auth enabled. The web UI is on port 8000.

## Tests

Unit tests with Strands + MCP mocked (no AWS creds, no live Trino):

```bash
pip install -r requirements.txt -r requirements-dev.txt
pytest
```

- `tests/test_helpers.py` — the pure helpers (`extract_sql`, `auth_headers`);
  needs no third-party deps.
- `tests/test_api.py` — `/healthz` and `/api/chat` via FastAPI `TestClient` with
  a fake agent + MCP (skips automatically if the app deps aren't installed).

## Notes

- **Stateless** single-turn Q&A: a fresh agent + MCP connection per request
  (simple/robust for a demo). Multi-turn memory is a possible enhancement.
- **Read-only** is enforced by query-app's Trino (`access-control.name=read-only`);
  the system prompt also tells the agent never to attempt writes.
