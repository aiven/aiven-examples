"""query-agent: a web chat that answers natural-language questions about the
live ecommerce orders by driving Trino through the Trino MCP server.

Flow:  user question -> Strands agent (Amazon Bedrock / Claude) -> Trino MCP tools
       (list schemas/tables, run read-only SELECTs) -> natural-language answer.

The agent only talks to the Trino MCP; Trino owns the Snowflake Open Catalog /
Iceberg connection. All config comes from environment variables (Aiven Apps
secrets / local .env) — see .env.example.
"""

import json
import logging
import os
import queue
import threading
from pathlib import Path

from fastapi import FastAPI
from fastapi.responses import FileResponse, JSONResponse, StreamingResponse
from pydantic import BaseModel

from strands import Agent
from strands.models import BedrockModel
from strands.tools.mcp import MCPClient
from mcp.client.streamable_http import streamablehttp_client

from helpers import auth_headers, describe_auth, extract_sql, resolve_token

logging.basicConfig(level=logging.INFO)
log = logging.getLogger("query-agent")

# --- Configuration (env) ---
AWS_REGION = os.getenv("AWS_REGION", "eu-west-1")
BEDROCK_MODEL_ID = os.getenv("BEDROCK_MODEL_ID", "eu.anthropic.claude-sonnet-4-6")
TRINO_MCP_URL = os.getenv("TRINO_MCP_URL", "http://localhost:9097/mcp")
# Auth on the MCP endpoint. Either present a ready-made bearer token
# (TRINO_MCP_JWT), or — preferred for a long-running deployment — supply the
# shared HMAC secret and mint a fresh short-lived token per request, so it can
# never expire. aud/iss must match query-app's OIDC_AUDIENCE/OIDC_ISSUER.
TRINO_MCP_JWT = os.getenv("TRINO_MCP_JWT")  # optional ready-made bearer token
MCP_JWT_SECRET = os.getenv("MCP_JWT_SECRET")  # shared HMAC secret; mint per request
MCP_JWT_AUDIENCE = os.getenv("MCP_JWT_AUDIENCE", "trino-mcp")
MCP_JWT_ISSUER = os.getenv("MCP_JWT_ISSUER", "aiven-query-agent")

# Surface the MCP target and auth mode once at startup so a 401 is debuggable
# from the logs alone (compare the secret fingerprint against query-app's).
log.info(
    "MCP endpoint: %s | %s",
    TRINO_MCP_URL,
    describe_auth(TRINO_MCP_JWT, MCP_JWT_SECRET, MCP_JWT_AUDIENCE, MCP_JWT_ISSUER),
)

SYSTEM_PROMPT = """\
You are a data analyst assistant for an ecommerce business. You answer questions
about live customer orders by querying Trino through the available MCP tools.

The data lives in Trino's `iceberg` catalog (Apache Iceberg tables backed by
Snowflake Open Catalog). Orders stream in continuously via CDC from Postgres,
so the data is live. The main table is `ecommerce.live_orders` with fields:
order_id, customer_id, product, quantity, amount, status
(PENDING/PAID/SHIPPED/DELIVERED/CANCELLED), order_date, updated_at.

IMPORTANT — live_orders is an append-only CDC change log: every status change
of an order adds a NEW row, so one order_id can appear multiple times. For
questions about the CURRENT state of orders (counts by status, totals, "how
many are shipped"), first reduce to the latest row per order:
    SELECT * FROM (
      SELECT *, row_number() OVER (PARTITION BY order_id ORDER BY updated_at DESC) AS rn
      FROM iceberg.ecommerce.live_orders
    ) WHERE rn = 1
For questions about history or lifecycle (time from PENDING to PAID,
cancellation rates, status transitions), use the full change log directly.

How to work:
- Discover the schema first when unsure: use list_schemas, list_tables, and
  get_table_schema on the `iceberg` catalog rather than guessing names.
- Write standard Trino SQL. Only read: SELECT and metadata queries. The engine
  is configured read-only and will reject any write/DDL — never attempt them.
- Keep result sets small (use aggregation, LIMIT) and prefer a single query.
- Answer the user's question directly and concisely in plain language, citing the
  concrete numbers you retrieved. Do not paste raw tool output verbatim.
"""

_model = None


def get_model() -> BedrockModel:
    """Lazily build the Bedrock model so importing this module needs no AWS
    credentials (keeps the app unit-testable)."""
    global _model
    if _model is None:
        _model = BedrockModel(model_id=BEDROCK_MODEL_ID, region_name=AWS_REGION)
    return _model


app = FastAPI(title="query-agent")
STATIC_DIR = Path(__file__).parent / "static"


class ChatRequest(BaseModel):
    message: str


def _make_mcp_client() -> MCPClient:
    """Build an MCP client for the Trino MCP server, with optional JWT auth.

    Resolves a fresh token on each call: a static TRINO_MCP_JWT if provided,
    otherwise one minted from MCP_JWT_SECRET, otherwise no auth."""
    token = resolve_token(TRINO_MCP_JWT, MCP_JWT_SECRET, MCP_JWT_AUDIENCE, MCP_JWT_ISSUER)
    headers = auth_headers(token)
    return MCPClient(lambda: streamablehttp_client(TRINO_MCP_URL, headers=headers))


@app.get("/healthz")
def healthz():
    return {"status": "ok"}


@app.get("/")
def index():
    return FileResponse(STATIC_DIR / "index.html")


@app.post("/api/chat")
def chat(req: ChatRequest):
    """Answer one question. Stateless: a fresh agent + MCP connection per request
    (simple and robust for a demo; multi-turn memory is a possible enhancement)."""
    try:
        mcp_client = _make_mcp_client()
        with mcp_client:
            tools = mcp_client.list_tools_sync()
            agent = Agent(model=get_model(), tools=tools, system_prompt=SYSTEM_PROMPT)
            result = agent(req.message)
            answer = str(result)
            sql_calls = extract_sql(agent.messages)
        return {"answer": answer, "tool_calls": sql_calls}
    except Exception as exc:  # surface a friendly error to the UI
        log.exception("chat failed")
        return JSONResponse(
            status_code=500,
            content={"error": f"{type(exc).__name__}: {exc}"},
        )


def _sse(event_type: str, **payload) -> str:
    """Format one Server-Sent Event line carrying a JSON object."""
    return f"data: {json.dumps({'type': event_type, **payload})}\n\n"


@app.post("/api/chat/stream")
def chat_stream(req: ChatRequest):
    """Same as /api/chat, but streams the agent's activity as Server-Sent Events
    so the UI can show what's happening live instead of a frozen 'Thinking…'.

    The Strands agent call is blocking, so it runs on a background thread and
    pushes events onto a queue; this generator drains the queue into SSE frames.
    Event types: `tool` (a tool the agent invoked, once per call), `token` (a
    chunk of the answer text), `done` (final answer + the full SQL/tool list),
    `error`.
    """
    events: "queue.Queue" = queue.Queue()

    def on_event(**kwargs):
        # Stream answer text as it's generated — the clearest "still working" signal.
        data = kwargs.get("data")
        if data:
            events.put(_sse("token", text=data))
        # Announce each tool the moment the agent commits to it. current_tool_use
        # is emitted repeatedly as its input streams in, so de-dupe by toolUseId.
        tool = kwargs.get("current_tool_use") or {}
        tool_id = tool.get("toolUseId")
        name = tool.get("name")
        if name and tool_id and tool_id not in on_event.seen:
            on_event.seen.add(tool_id)
            events.put(_sse("tool", name=name))

    on_event.seen = set()

    def run():
        try:
            events.put(_sse("status", text="Connecting to Trino MCP…"))
            mcp_client = _make_mcp_client()
            with mcp_client:
                tools = mcp_client.list_tools_sync()
                events.put(_sse("status", text="Asking the model…"))
                agent = Agent(
                    model=get_model(),
                    tools=tools,
                    system_prompt=SYSTEM_PROMPT,
                    callback_handler=on_event,
                )
                result = agent(req.message)
                events.put(_sse("done", answer=str(result), tool_calls=extract_sql(agent.messages)))
        except Exception as exc:
            log.exception("stream chat failed")
            events.put(_sse("error", error=f"{type(exc).__name__}: {exc}"))
        finally:
            events.put(None)  # sentinel: close the stream

    def generate():
        threading.Thread(target=run, daemon=True).start()
        while True:
            item = events.get()
            if item is None:
                break
            yield item

    # X-Accel-Buffering: no keeps proxies from buffering the stream (events arrive live).
    return StreamingResponse(
        generate(),
        media_type="text/event-stream",
        headers={"Cache-Control": "no-cache", "X-Accel-Buffering": "no"},
    )


if __name__ == "__main__":
    import uvicorn

    uvicorn.run(app, host="0.0.0.0", port=int(os.getenv("PORT", "8000")))
