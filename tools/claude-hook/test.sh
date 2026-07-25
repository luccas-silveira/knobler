#!/bin/bash
# Contract check for the Claude PermissionRequest adapter.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
FIXTURE="$ROOT/fixtures/permission-request.json"
TMP="$(mktemp -d)"
trap 'status=$?; kill "${SERVER_PID:-}" 2>/dev/null || true; rm -rf "$TMP"; exit "$status"' EXIT
TOKEN_FILE="$TMP/token"
printf '%s' hook-test-token > "$TOKEN_FILE"

start_api() { # $1=agent action
    local port="$1" action="$2" payload="$3"
    python3 - "$port" "$action" "$payload" <<'PY' &
import json, sys
from http.server import BaseHTTPRequestHandler, HTTPServer

port, action, payload = int(sys.argv[1]), sys.argv[2], sys.argv[3]
class Handler(BaseHTTPRequestHandler):
    def log_message(self, *args): pass
    def do_POST(self):
        if self.path != "/agent-requests" or self.headers.get("Authorization") != "Bearer hook-test-token":
            self.send_error(401); return
        size = int(self.headers["Content-Length"])
        with open(payload, "wb") as out:
            out.write(self.rfile.read(size))
        self.send_response(200); self.end_headers(); self.wfile.write(b'{"ok":true}')
    def do_GET(self):
        response = {"state": "resolved", "result": {"action": action, "responder": "nob", "state": "resolved"}}
        body = json.dumps(response).encode()
        self.send_response(200); self.end_headers(); self.wfile.write(body)
HTTPServer(("127.0.0.1", port), Handler).serve_forever()
PY
    SERVER_PID=$!
    for _ in {1..20}; do
        curl -sf -m 1 "http://127.0.0.1:$port/ready" >/dev/null 2>&1 && return
        sleep 0.05
    done
    return 1
}

run_case() { # $1=action $2=expected JSON
    local action="$1" expected="$2" port payload output
    port=$((46000 + RANDOM % 1000))
    payload="$TMP/$action.json"
    start_api "$port" "$action" "$payload"
    output="$(KNOBLER_PORT="$port" KNOBLER_AGENT_REQUEST_TOKEN="$TOKEN_FILE" "$ROOT/knobler-permission.sh" < "$FIXTURE")"
    kill "$SERVER_PID" 2>/dev/null || true
    wait "$SERVER_PID" 2>/dev/null || true
    unset SERVER_PID
    test "$output" = "$expected"
    jq -e '
        .agent == "claude" and .kind == "permission" and .source == "terminal"
        and .title == "Bash" and .summary == "Run test suite"
        and (.details | contains("npm test"))
        and .actions == [{"action":"allow"},{"action":"allowForSession"},{"action":"deny"}]' "$payload" >/dev/null
}

run_case allow '{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"allow"}}}'
run_case deny '{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"deny"}}}'
run_case allowForSession '{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"allow","updatedPermissions":[{"type":"addRules","rules":[{"toolName":"Bash","ruleContent":"npm test"}],"behavior":"allow","destination":"session"}]}}}'

DOWN="$(KNOBLER_PORT=1 KNOBLER_AGENT_REQUEST_TOKEN="$TOKEN_FILE" "$ROOT/knobler-permission.sh" < "$FIXTURE")"
test -z "$DOWN"

HOME="$TMP/home"
mkdir -p "$HOME/.claude"
printf '%s' '{"hooks":{"PreToolUse":[{"matcher":"Write","hooks":[{"type":"command","command":"keep-me"}]}]}}' > "$HOME/.claude/settings.json"
HOME="$HOME" bash "$ROOT/install.sh" >/dev/null
HOME="$HOME" bash "$ROOT/install.sh" >/dev/null
jq -e '
    ([.hooks.PreToolUse[] | select(.hooks[]?.command == "keep-me")] | length == 1)
    and ([.hooks.PreToolUse[] | select(.hooks[]?.command == ($home + "/.claude/hooks/knobler-ask.sh"))] | length == 1)
    and ([.hooks.PermissionRequest[] | select(.hooks[]?.command == ($home + "/.claude/hooks/knobler-permission.sh"))] | length == 1)' \
    --arg home "$HOME" "$HOME/.claude/settings.json" >/dev/null
echo "claude-hook: OK"
