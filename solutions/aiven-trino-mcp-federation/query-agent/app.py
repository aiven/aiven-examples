"""query-agent: a web chat that answers natural-language questions about the
live ecommerce orders by driving Trino through the Trino MCP server.

Flow:  user question -> Strands agent (Amazon Bedrock / Claude) -> Trino MCP tools
       (list schemas/tables, run read-only SELECTs) -> natural-language answer.

The agent only talks to the Trino MCP; Trino owns the Snowflake Open Catalog /
Iceberg connection. All config comes from environment variables (Aiven Apps
secrets / local .env) — see .env.example.
"""

import logging
import os
from pathlib import Path

from fastapi import FastAPI
from fastapi.responses import FileResponse, JSONResponse
from pydantic import BaseModel

from strands import Agent
from strands.models import BedrockModel
from strands.tools.mcp import MCPClient
from mcp.client.streamable_http import streamablehttp_client

logging.basicConfig(level=logging.INFO)
log = logging.getLogger("query-agent")

# --- Configuration (env) ---
AWS_REGION = os.getenv("AWS_REGION", "eu-west-1")
BEDROCK_MODEL_ID = os.getenv("BEDROCK_MODEL_ID", "eu.anthropic.claude-sonnet-4-6")
TRINO_MCP_URL = os.getenv("TRINO_MCP_URL", "http://localhost:9097/mcp")
TRINO_MCP_JWT = os.getenv("TRINO_MCP_JWT")  # optional bearer token for the MCP endpoint

SYSTEM_PROMPT = """\
You are a data analyst assistant for an ecommerce business. You answer questions
about live customer orders by querying Trino through the available MCP tools.

The data lives in Trino's `iceberg` catalog (Apache Iceberg tables backed by
Snowflake Open Catalog). Orders stream in continuously, so the data is live.
The order records have these fields: orderId, customerId, product, quantity,
amount, status (PENDING/PAID/SHIPPED/DELIVERED/CANCELLED), orderDate (timestamp).

How to work:
- Discover the schema first when unsure: use list_schemas, list_tables, and
  get_table_schema on the `iceberg` catalog rather than guessing names.
- Write standard Trino SQL. Only read: SELECT and metadata queries. The engine
  is configured read-only and will reject any write/DDL — never attempt them.
- Keep result sets small (use aggregation, LIMIT) and prefer a single query.
- Answer the user's question directly and concisely in plain language, citing the
  concrete numbers you retrieved. Do not paste raw tool output verbatim.
"""

model = BedrockModel(model_id=BEDROCK_MODEL_ID, region_name=AWS_REGION)

app = FastAPI(title="query-agent")
STATIC_DIR = Path(__file__).parent / "static"


class ChatRequest(BaseModel):
    message: str


def _make_mcp_client() -> MCPClient:
    """Build an MCP client for the Trino MCP server, with optional JWT auth."""
    headers = {"Authorization": f"Bearer {TRINO_MCP_JWT}"} if TRINO_MCP_JWT else None
    return MCPClient(lambda: streamablehttp_client(TRINO_MCP_URL, headers=headers))


def _extract_sql(messages: list) -> list:
    """Pull the SQL/tool calls the agent made out of the conversation, so the UI
    can show what actually ran against Trino."""
    calls = []
    for msg in messages:
        for block in msg.get("content", []) or []:
            tool_use = block.get("toolUse") if isinstance(block, dict) else None
            if not tool_use:
                continue
            inp = tool_use.get("input") or {}
            sql = inp.get("query") or inp.get("sql")
            calls.append({"tool": tool_use.get("name"), "sql": sql, "input": inp})
    return calls


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
            agent = Agent(model=model, tools=tools, system_prompt=SYSTEM_PROMPT)
            result = agent(req.message)
            answer = str(result)
            sql_calls = _extract_sql(agent.messages)
        return {"answer": answer, "tool_calls": sql_calls}
    except Exception as exc:  # surface a friendly error to the UI
        log.exception("chat failed")
        return JSONResponse(
            status_code=500,
            content={"error": f"{type(exc).__name__}: {exc}"},
        )


if __name__ == "__main__":
    import uvicorn

    uvicorn.run(app, host="0.0.0.0", port=int(os.getenv("PORT", "8000")))
