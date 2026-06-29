"""API tests for the FastAPI app with Strands + MCP mocked out.

Requires the app deps installed (see requirements.txt + requirements-dev.txt):
    pip install -r requirements.txt -r requirements-dev.txt
    pytest

The Strands Agent and the Trino MCP connection are replaced with fakes, so these
run with no AWS credentials and no live Trino.
"""

import json
import os
import sys

import pytest

sys.path.insert(0, os.path.dirname(os.path.dirname(__file__)))

# Skip cleanly if the heavy app deps aren't installed in this environment.
fastapi_testclient = pytest.importorskip("fastapi.testclient")
pytest.importorskip("strands")

import app as app_module
from fastapi.testclient import TestClient


class _FakeResult:
    def __str__(self):
        return "There were 5 orders in the last hour."


class _FakeAgent:
    """Stand-in for strands.Agent: records a tool call and returns an answer."""

    last_messages = [
        {"role": "user", "content": [{"text": "q"}]},
        {
            "role": "assistant",
            "content": [
                {"toolUse": {"name": "execute_query", "input": {"query": "SELECT count(*) FROM iceberg.s.order"}}}
            ],
        },
    ]

    def __init__(self, model=None, tools=None, system_prompt=None, callback_handler=None):
        self.messages = _FakeAgent.last_messages
        self._cb = callback_handler

    def __call__(self, message):
        # Simulate Strands streaming: emit a tool-use event (twice, to exercise
        # the toolUseId de-dupe) and a couple of text chunks before answering.
        if self._cb:
            tool = {"toolUseId": "t1", "name": "execute_query", "input": {}}
            self._cb(current_tool_use=tool)
            self._cb(current_tool_use=tool)
            self._cb(data="There were 5 ")
            self._cb(data="orders in the last hour.")
        return _FakeResult()


class _DummyMCP:
    def __enter__(self):
        return self

    def __exit__(self, *exc):
        return False

    def list_tools_sync(self):
        return []


@pytest.fixture
def client(monkeypatch):
    monkeypatch.setattr(app_module, "Agent", _FakeAgent)
    monkeypatch.setattr(app_module, "_make_mcp_client", lambda: _DummyMCP())
    monkeypatch.setattr(app_module, "get_model", lambda: None)
    return TestClient(app_module.app)


def test_healthz(client):
    res = client.get("/healthz")
    assert res.status_code == 200
    assert res.json() == {"status": "ok"}


def test_chat_returns_answer_and_sql(client):
    res = client.post("/api/chat", json={"message": "orders in the last hour?"})
    assert res.status_code == 200
    body = res.json()
    assert "5 orders" in body["answer"]
    assert body["tool_calls"][0]["tool"] == "execute_query"
    assert "count(*)" in body["tool_calls"][0]["sql"]


def _parse_sse(text):
    """Parse an SSE response body into a list of decoded JSON events."""
    events = []
    for frame in text.split("\n\n"):
        for line in frame.splitlines():
            if line.startswith("data:"):
                events.append(json.loads(line[len("data:"):].strip()))
    return events


def test_chat_stream_emits_tool_tokens_and_done(client):
    res = client.post("/api/chat/stream", json={"message": "orders in the last hour?"})
    assert res.status_code == 200
    assert res.headers["content-type"].startswith("text/event-stream")
    events = _parse_sse(res.text)
    types = [e["type"] for e in events]

    # The tool fires twice in the fake but must be announced once (toolUseId de-dupe).
    assert types.count("tool") == 1
    tool_evt = next(e for e in events if e["type"] == "tool")
    assert tool_evt["name"] == "execute_query"

    assert "token" in types  # answer streamed in chunks

    done = next(e for e in events if e["type"] == "done")
    assert "5 orders" in done["answer"]
    assert done["tool_calls"][0]["tool"] == "execute_query"


def test_chat_stream_error_path(client, monkeypatch):
    monkeypatch.setattr(app_module, "_make_mcp_client", lambda: (_ for _ in ()).throw(RuntimeError("MCP unreachable")))
    res = client.post("/api/chat/stream", json={"message": "hi"})
    assert res.status_code == 200  # stream opens, then carries an error event
    events = _parse_sse(res.text)
    err = next(e for e in events if e["type"] == "error")
    assert "MCP unreachable" in err["error"]


def test_chat_error_path(client, monkeypatch):
    def boom():
        raise RuntimeError("MCP unreachable")

    monkeypatch.setattr(app_module, "_make_mcp_client", boom)
    res = client.post("/api/chat", json={"message": "hi"})
    assert res.status_code == 500
    assert "MCP unreachable" in res.json()["error"]
