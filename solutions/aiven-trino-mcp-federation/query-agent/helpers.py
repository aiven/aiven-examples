"""Pure helpers for query-agent, with no third-party dependencies, so they can
be unit-tested in isolation (no Strands / MCP / AWS imports required)."""

from typing import Optional


def auth_headers(jwt: Optional[str]) -> Optional[dict]:
    """Bearer auth headers for the MCP endpoint, or None when no token is set."""
    if jwt:
        return {"Authorization": f"Bearer {jwt}"}
    return None


def extract_sql(messages: list) -> list:
    """Pull the tool/SQL calls the agent made out of a Strands conversation, so
    the UI can show what actually ran against Trino.

    Each Strands message is ``{"role": ..., "content": [block, ...]}``; a tool
    call is a block ``{"toolUse": {"name": ..., "input": {...}}}``. mcp-trino's
    execute_query takes the SQL under ``query`` (some builds use ``sql``), so we
    accept either.
    """
    calls = []
    for msg in messages or []:
        if not isinstance(msg, dict):
            continue
        for block in msg.get("content", []) or []:
            tool_use = block.get("toolUse") if isinstance(block, dict) else None
            if not tool_use:
                continue
            inp = tool_use.get("input") or {}
            sql = inp.get("query") or inp.get("sql")
            calls.append({"tool": tool_use.get("name"), "sql": sql, "input": inp})
    return calls
