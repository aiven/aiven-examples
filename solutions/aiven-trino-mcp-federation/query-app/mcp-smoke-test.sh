#!/usr/bin/env bash
#
# mcp-smoke-test.sh — validate the MCP layer (mcp-trino) end-to-end over its
# StreamableHTTP endpoint: initialize -> tools/list -> execute_query (real data
# through Trino -> Open Catalog -> S3) -> write-denial. This complements
# smoke-test.sh, which talks to Trino directly and bypasses MCP entirely.
#
# Usage:
#   ./mcp-smoke-test.sh                       # handshake + tools/list + SELECT 1 + write-denial
#   ./mcp-smoke-test.sh <namespace>           # + count rows in <namespace>.orders via MCP
#   ./mcp-smoke-test.sh <namespace> <table>   # + count rows in that table (default table: orders)
#
# Env:
#   MCP_URL           MCP endpoint (default: http://localhost:9097/mcp)
#   MCP_JWT           A ready-made bearer token. If set, used as-is.
#   MCP_JWT_SECRET    HMAC secret. If MCP_JWT is unset and this is set, the script
#                     mints a short-lived HS256 token (needs openssl). Matches the
#                     server's OAUTH_PROVIDER=hmac. Source query-app/.env to get it.
#   MCP_JWT_AUDIENCE  aud claim (default: trino-mcp)  — must match server OIDC_AUDIENCE
#   MCP_JWT_ISSUER    iss claim (default: aiven-query-agent) — must match OIDC_ISSUER
#   MCP_JWT_SUB       sub claim (default: mcp-smoke)
#   MCP_JWT_TTL       token lifetime in seconds (default: 300)
#
# When OAuth is off, leave all MCP_JWT* unset — the script just runs unauthenticated.
#
# Notes on the protocol (the things that trip up hand-testing):
#   - StreamableHTTP is session-based: `initialize` returns an `Mcp-Session-Id`
#     response header that MUST be replayed on every subsequent request.
#   - The `Accept` header must include `text/event-stream`, or the server 406s.
#   - With OAuth on, `initialize` returns 200 even for a bad/forged token — the
#     handshake is pre-auth. The signature is only enforced at `tools/call`, which
#     is exactly why this script exercises execute_query, not just initialize.
set -euo pipefail

URL="${MCP_URL:-http://localhost:9097/mcp}"
ACCEPT='Accept: application/json, text/event-stream'
CT='Content-Type: application/json'
HDRS="$(mktemp)"
trap 'rm -f "$HDRS"' EXIT

fail() { echo "FAIL: $*" >&2; exit 1; }

# base64url with no padding, as JWT requires.
b64url() { openssl base64 -A | tr '+/' '-_' | tr -d '='; }

# mint_jwt <secret> <aud> <iss> — emit a short-lived HS256 JWT (the hmac provider's format).
mint_jwt() {
  local now exp hdr pl h p sig
  now="$(date +%s)"; exp="$((now + ${MCP_JWT_TTL:-300}))"
  hdr='{"alg":"HS256","typ":"JWT"}'
  pl="{\"sub\":\"${MCP_JWT_SUB:-mcp-smoke}\",\"aud\":\"$2\",\"iss\":\"$3\",\"iat\":$now,\"exp\":$exp}"
  h="$(printf '%s' "$hdr" | b64url)"; p="$(printf '%s' "$pl" | b64url)"
  sig="$(printf '%s' "$h.$p" | openssl dgst -sha256 -hmac "$1" -binary | b64url)"
  printf '%s.%s.%s' "$h" "$p" "$sig"
}

# Auth: use MCP_JWT verbatim if given, else mint one from MCP_JWT_SECRET, else none.
TOKEN="${MCP_JWT:-}"
if [ -z "$TOKEN" ] && [ -n "${MCP_JWT_SECRET:-}" ]; then
  command -v openssl >/dev/null || fail "openssl is required to mint a token from MCP_JWT_SECRET"
  TOKEN="$(mint_jwt "$MCP_JWT_SECRET" "${MCP_JWT_AUDIENCE:-trino-mcp}" "${MCP_JWT_ISSUER:-aiven-query-agent}")"
  echo "==> minted HS256 token (aud=${MCP_JWT_AUDIENCE:-trino-mcp}, iss=${MCP_JWT_ISSUER:-aiven-query-agent}, ttl=${MCP_JWT_TTL:-300}s)"
fi
AUTH=()
[ -n "$TOKEN" ] && AUTH=(-H "Authorization: Bearer $TOKEN")

# mcp <json-payload> — send one JSON-RPC request on the established session.
mcp() {
  curl -s ${AUTH[@]+"${AUTH[@]}"} "$URL" -H "$CT" -H "$ACCEPT" -H "Mcp-Session-Id: $SID" -d "$1"
}

echo "==> Endpoint: $URL"

echo "==> 1) initialize (open session)"
INIT="$(curl -s -D "$HDRS" ${AUTH[@]+"${AUTH[@]}"} "$URL" -H "$CT" -H "$ACCEPT" \
  -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"mcp-smoke","version":"1"}}}')"
case "$INIT" in
  *'"serverInfo"'*) : ;;
  *) fail "no serverInfo in initialize response: $INIT" ;;
esac
SID="$(grep -i '^Mcp-Session-Id:' "$HDRS" | tr -d '\r' | awk '{print $2}')"
[ -n "$SID" ] || fail "server did not return an Mcp-Session-Id header"
echo "    session: $SID"

echo "==> 2) notifications/initialized"
mcp '{"jsonrpc":"2.0","method":"notifications/initialized"}' >/dev/null

echo "==> 3) tools/list"
TOOLS="$(mcp '{"jsonrpc":"2.0","id":2,"method":"tools/list"}')"
case "$TOOLS" in
  *'"execute_query"'*) echo "    execute_query present" ;;
  *) fail "execute_query not advertised: $TOOLS" ;;
esac

echo "==> 4) tools/call execute_query — keystone (Trino reachable through MCP)"
SEL="$(mcp '{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"execute_query","arguments":{"query":"SELECT 1 AS ok"}}}')"
case "$SEL" in
  *'"isError":true'*) fail "SELECT 1 errored: $SEL" ;;
  *'"ok": 1'*|*'\"ok\": 1'*) echo "    SELECT 1 -> ok" ;;
  *) fail "unexpected SELECT 1 result: $SEL" ;;
esac

NS="${1:-${ICEBERG_NAMESPACE:-}}"
if [ -n "$NS" ]; then
  TABLE="${2:-orders}"
  echo "==> 5) tools/call execute_query — count iceberg.\"$NS\".\"$TABLE\" (reads S3)"
  Q="SELECT count(*) AS n FROM iceberg.\\\"$NS\\\".\\\"$TABLE\\\""
  CNT="$(mcp "{\"jsonrpc\":\"2.0\",\"id\":4,\"method\":\"tools/call\",\"params\":{\"name\":\"execute_query\",\"arguments\":{\"query\":\"$Q\"}}}")"
  case "$CNT" in
    *'"isError":true'*) fail "count query errored: $CNT" ;;
    *'"n":'*|*'\"n\":'*) echo "    result: $(printf '%s' "$CNT" | grep -oE '[0-9]+' | tail -1) rows" ;;
    *) fail "unexpected count result: $CNT" ;;
  esac
else
  echo "==> 5) (pass a namespace to also count rows via MCP: ./mcp-smoke-test.sh <namespace> [table])"
fi

echo "==> 6) write-denial — CREATE TABLE must be rejected (read-only guarantee)"
WR="$(mcp '{"jsonrpc":"2.0","id":5,"method":"tools/call","params":{"name":"execute_query","arguments":{"query":"CREATE TABLE mcp_smoke_should_be_denied (x integer)"}}}')"
case "$WR" in
  *'"isError":true'*) echo "    write rejected as expected" ;;
  *) fail "write was NOT rejected — read-only guarantee broken: $WR" ;;
esac

echo "OK — MCP layer healthy: session, tools/list, execute_query (data), and write-denial all pass."
