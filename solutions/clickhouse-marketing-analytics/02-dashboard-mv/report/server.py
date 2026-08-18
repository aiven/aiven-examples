#!/usr/bin/env python3
"""Thin proxy for the staged-reveal report page.

Serves the static page and one API:
  GET /api/query?name=q3&track=optimized
    -> {"data": [...], "wall_s": ..., "read_rows": ..., ...}

ClickHouse credentials stay HERE (env CH_URL/CH_USER/CH_PASSWORD/CH_DATABASE,
see bench_lib) — never in client JS. Each call runs the canonical query file
under a tagged query_id through bench_lib, so the badge on every revealed
panel is a real measured number from the same run that drew the chart.

  CH_DATABASE=campaign_analytics CH_PASSWORD=local python3 server.py [port]
"""

from __future__ import annotations

import json
import re
import sys
import urllib.parse
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

HERE = Path(__file__).parent
sys.path.insert(0, str(HERE.parent / "bench"))
from bench_lib import ClickHouse  # noqa: E402

QUERIES = HERE.parent / "queries"
NAME_RE = re.compile(r"^q[1-8]$")
ch = ClickHouse()


class Handler(SimpleHTTPRequestHandler):
    def __init__(self, *a, **kw):
        super().__init__(*a, directory=str(HERE), **kw)

    def do_GET(self):
        u = urllib.parse.urlparse(self.path)
        if u.path != "/api/query":
            return super().do_GET()
        qs = urllib.parse.parse_qs(u.query)
        name = qs.get("name", [""])[0]
        track = qs.get("track", ["optimized"])[0]
        if track not in ("naive", "optimized") or not NAME_RE.match(name):
            return self.send_error(400, "bad name/track")
        matches = sorted((QUERIES / track).glob(f"{name}_*.sql"))
        if not matches:
            return self.send_error(404, f"no {track}/{name}_*.sql")
        try:
            rec = ch.run_measured(matches[0].read_text(),
                                  tag=f"report-{track}-{name}", keep_result=True)
        except Exception as e:  # surface CH errors to the panel
            body = json.dumps({"error": str(e)}).encode()
            self.send_response(500)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
            return
        body = json.dumps(rec).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, fmt, *args):
        sys.stderr.write("%s - %s\n" % (self.address_string(), fmt % args))


if __name__ == "__main__":
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 8088
    print(f"report page on http://localhost:{port}  (ClickHouse: {ch.url}, db {ch.database})")
    ThreadingHTTPServer(("127.0.0.1", port), Handler).serve_forever()
