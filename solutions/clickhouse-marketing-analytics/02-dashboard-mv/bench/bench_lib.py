"""Shared "time it + capture query_log" wrapper — every consumer of the query
suite (the harness, the report page's proxy, ad-hoc runs) measures through
this so the article's numbers, the page's badges and the CSVs are one source.

Stdlib only (urllib): no dependency on the datagen venv.

Connection via env (same names as the repo's .env):
  CH_URL      e.g. http://localhost:8123 or https://<service>.aivencloud.com:<port>
  CH_USER     default 'default' (Aiven: 'avnadmin')
  CH_PASSWORD
  CH_DATABASE default 'default'
"""

from __future__ import annotations

import json
import os
import ssl
import time
import urllib.error
import urllib.parse
import urllib.request
import uuid


class ClickHouse:
    def __init__(self, url: str | None = None, user: str | None = None,
                 password: str | None = None, database: str | None = None):
        self.url = (url or os.environ.get("CH_URL", "http://localhost:8123")).rstrip("/")
        self.user = user or os.environ.get("CH_USER", "default")
        self.password = password or os.environ.get("CH_PASSWORD", "")
        self.database = database or os.environ.get("CH_DATABASE", "default")
        self._ctx = ssl.create_default_context() if self.url.startswith("https") else None

    def raw(self, sql: str, *, fmt: str | None = None, query_id: str | None = None,
            settings: dict | None = None, timeout: float = 600) -> bytes:
        params = {"database": self.database}
        if query_id:
            params["query_id"] = query_id
        if settings:
            params.update({k: str(v) for k, v in settings.items()})
        body = sql if fmt is None else f"{sql.rstrip().rstrip(';')} FORMAT {fmt}"
        req = urllib.request.Request(
            f"{self.url}/?{urllib.parse.urlencode(params)}",
            data=body.encode(),
            headers={"X-ClickHouse-User": self.user,
                     "X-ClickHouse-Key": self.password},
            method="POST")
        # Transient-network retry: a multi-hour benchmark makes hundreds of
        # sequential WAN calls, and one silently dropped connection used to
        # hang or kill the whole run. HTTP errors (server responded) are
        # never retried; neither are calls pinned to a query_id — the server
        # may still be running that id, so the CALLER owns the retry with a
        # fresh id (see run_measured).
        attempts = 1 if query_id else 3
        for attempt in range(1, attempts + 1):
            try:
                with urllib.request.urlopen(req, timeout=timeout, context=self._ctx) as resp:
                    return resp.read()
            except urllib.error.HTTPError:
                raise
            except (TimeoutError, OSError) as e:
                if attempt == attempts:
                    raise
                print(f"    (retry {attempt}/{attempts - 1}: {type(e).__name__} "
                      f"on {sql[:50]!r})", flush=True)
                time.sleep(2 * attempt)

    def json(self, sql: str, **kw) -> dict:
        return json.loads(self.raw(sql, fmt="JSON", **kw))

    def run_measured(self, sql: str, tag: str, keep_result: bool = False) -> dict:
        """Run sql once under a unique query_id; return wall time + the
        query_log record (duration, read_rows/bytes, peak memory).
        keep_result=True also returns the parsed rows (the report page's
        proxy uses this so the chart and its badge come from ONE run)."""
        # Measurement retry: on a transient network error the whole attempt
        # restarts under a FRESH query_id and a fresh clock — a half-measured
        # sample must never leak into the medians.
        for attempt in range(2):
            qid = f"{tag}-{uuid.uuid4().hex[:12]}"
            t0 = time.perf_counter()
            try:
                body = self.raw(sql, fmt="JSON", query_id=qid, timeout=600)
                break
            except urllib.error.HTTPError:
                raise                    # server answered; not a network flake
            except (TimeoutError, OSError) as e:
                if attempt == 1:
                    raise
                print(f"    (re-measuring {tag}: {type(e).__name__})", flush=True)
                time.sleep(3)
        wall_s = time.perf_counter() - t0
        parsed = json.loads(body)
        result_rows = parsed.get("rows", None)

        log = self._query_log(qid)
        record = {
            "tag": tag,
            "query_id": qid,
            "wall_s": round(wall_s, 4),
            "server_ms": log.get("query_duration_ms"),
            "read_rows": log.get("read_rows"),
            "read_bytes": log.get("read_bytes"),
            "memory_usage": log.get("memory_usage"),
            "result_rows": result_rows,
        }
        if keep_result:
            record["data"] = parsed.get("data", [])
        return record

    def _query_log(self, qid: str, attempts: int = 10) -> dict:
        probe = (
            "SELECT query_duration_ms, read_rows, read_bytes, memory_usage "
            "FROM clusterAllReplicas(default, system.query_log) "
            f"WHERE query_id = '{qid}' AND type = 'QueryFinish' LIMIT 1"
        )
        local = probe.replace("clusterAllReplicas(default, system.query_log)",
                              "system.query_log")
        for i in range(attempts):
            try:
                self.raw("SYSTEM FLUSH LOGS")
            except Exception:
                pass  # not always permitted on managed services; the log flushes itself
            for q in (local, probe):
                try:
                    data = json.loads(self.raw(q, fmt="JSON"))
                    if data.get("rows"):
                        row = data["data"][0]
                        return {k: int(v) for k, v in row.items()}
                except Exception:
                    continue
            time.sleep(0.5 + 0.5 * i)
        return {}

    def version(self) -> str:
        return self.json("SELECT version() AS v")["data"][0]["v"]
