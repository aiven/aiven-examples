"""Unit tests for the pure helpers — no third-party deps required."""

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(__file__)))

from helpers import auth_headers, extract_sql


def test_auth_headers_with_token():
    assert auth_headers("abc.def.ghi") == {"Authorization": "Bearer abc.def.ghi"}


def test_auth_headers_without_token():
    assert auth_headers(None) is None
    assert auth_headers("") is None


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
