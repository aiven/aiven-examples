"""Pure helpers for query-agent, with no third-party dependencies, so they can
be unit-tested in isolation (no Strands / MCP / AWS imports required)."""

import base64
import hashlib
import hmac
import json
import time
from typing import Optional


def _b64url(raw: bytes) -> str:
    """base64url with no padding, as JWT requires."""
    return base64.urlsafe_b64encode(raw).rstrip(b"=").decode("ascii")


def mint_jwt(
    secret: str,
    audience: str,
    issuer: str,
    sub: str = "query-agent",
    ttl: int = 300,
) -> str:
    """Mint a short-lived HS256 JWT in the format mcp-trino's HMAC provider
    expects. The validator requires aud/iss to match its OIDC_AUDIENCE/
    OIDC_ISSUER, so callers must pass the same values configured on query-app.

    Minting per request (rather than baking a static token) means the token
    can never expire out from under a long-running deployment.
    """
    now = int(time.time())
    header = {"alg": "HS256", "typ": "JWT"}
    payload = {"sub": sub, "aud": audience, "iss": issuer, "iat": now, "exp": now + ttl}
    signing_input = (
        _b64url(json.dumps(header, separators=(",", ":")).encode())
        + "."
        + _b64url(json.dumps(payload, separators=(",", ":")).encode())
    )
    sig = hmac.new(secret.encode(), signing_input.encode(), hashlib.sha256).digest()
    return f"{signing_input}.{_b64url(sig)}"


def resolve_token(
    static_jwt: Optional[str],
    secret: Optional[str],
    audience: str,
    issuer: str,
) -> Optional[str]:
    """Decide which bearer token (if any) to present to the MCP endpoint:
    an explicit static JWT wins; otherwise mint a fresh one from the shared
    secret; otherwise None (MCP auth disabled)."""
    if static_jwt:
        return static_jwt
    if secret:
        return mint_jwt(secret, audience, issuer)
    return None


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
