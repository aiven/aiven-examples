"""Unit tests for the pure helpers — no third-party deps required."""

import base64
import hashlib
import hmac
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(__file__)))

from helpers import auth_headers, extract_sql, mint_jwt, resolve_token


def test_auth_headers_with_token():
    assert auth_headers("abc.def.ghi") == {"Authorization": "Bearer abc.def.ghi"}


def test_auth_headers_without_token():
    assert auth_headers(None) is None
    assert auth_headers("") is None


def _b64url_decode(seg: str) -> bytes:
    return base64.urlsafe_b64decode(seg + "=" * (-len(seg) % 4))


def test_mint_jwt_has_three_segments_and_claims():
    token = mint_jwt("s3cret", "trino-mcp", "aiven-query-agent")
    parts = token.split(".")
    assert len(parts) == 3  # header.payload.signature — the bug we hit was a non-JWT value
    payload = json.loads(_b64url_decode(parts[1]))
    assert payload["aud"] == "trino-mcp"
    assert payload["iss"] == "aiven-query-agent"
    assert payload["exp"] > payload["iat"]


def test_mint_jwt_signature_validates():
    token = mint_jwt("s3cret", "trino-mcp", "aiven-query-agent")
    signing_input, sig = token.rsplit(".", 1)
    expected = hmac.new(b"s3cret", signing_input.encode(), hashlib.sha256).digest()
    assert _b64url_decode(sig) == expected


def test_resolve_token_prefers_static():
    assert resolve_token("static.tok.en", "secret", "aud", "iss") == "static.tok.en"


def test_resolve_token_mints_from_secret():
    token = resolve_token(None, "secret", "trino-mcp", "aiven-query-agent")
    assert token and len(token.split(".")) == 3


def test_resolve_token_none_when_no_auth():
    assert resolve_token(None, None, "aud", "iss") is None
    assert resolve_token("", "", "aud", "iss") is None


def test_extract_sql_query_key():
    messages = [
        {"role": "user", "content": [{"text": "how many orders?"}]},
        {
            "role": "assistant",
            "content": [
                {"toolUse": {"name": "execute_query", "input": {"query": "SELECT count(*) FROM iceberg.x.order"}}}
            ],
        },
    ]
    calls = extract_sql(messages)
    assert len(calls) == 1
    assert calls[0]["tool"] == "execute_query"
    assert calls[0]["sql"] == "SELECT count(*) FROM iceberg.x.order"


def test_extract_sql_accepts_sql_key():
    """Some mcp-trino builds use `sql` instead of `query`."""
    messages = [{"role": "assistant", "content": [{"toolUse": {"name": "execute_query", "input": {"sql": "SELECT 1"}}}]}]
    assert extract_sql(messages)[0]["sql"] == "SELECT 1"


def test_extract_sql_non_query_tool():
    messages = [{"role": "assistant", "content": [{"toolUse": {"name": "list_schemas", "input": {"catalog": "iceberg"}}}]}]
    calls = extract_sql(messages)
    assert len(calls) == 1
    assert calls[0]["tool"] == "list_schemas"
    assert calls[0]["sql"] is None


def test_extract_sql_ignores_non_tool_blocks_and_empty():
    assert extract_sql([]) == []
    assert extract_sql(None) == []
    assert extract_sql([{"role": "assistant", "content": [{"text": "hi"}]}]) == []
    assert extract_sql(["not a dict"]) == []
