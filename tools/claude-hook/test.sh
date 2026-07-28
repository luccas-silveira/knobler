#!/bin/bash
# Contract check for the Claude PermissionRequest adapter.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
FIXTURE="$ROOT/fixtures/permission-request.json"
TMP="$(mktemp -d)"
trap 'status=$?; kill "${SERVER_PID:-}" 2>/dev/null || true; rm -rf "$TMP"; exit "$status"' EXIT
TOKEN_FILE="$TMP/token"
printf '%s' hook-test-token > "$TOKEN_FILE"

start_api() { # $1=agent action $2=payload file
    local action="$1" payload="$2" port_file="$TMP/port"
    rm -f "$port_file"
    python3 - "$action" "$payload" "$port_file" <<'PY' &
import json, sys, time
from http.server import BaseHTTPRequestHandler, HTTPServer

action, payload, port_file = sys.argv[1:]
class Handler(BaseHTTPRequestHandler):
    def log_message(self, *args): pass
    def do_POST(self):
        if self.path != "/agent-requests" or self.headers.get("Authorization") != "Bearer hook-test-token":
            self.send_error(401); return
        if action == "timeout":
            time.sleep(2)
            return
        size = int(self.headers["Content-Length"])
        with open(payload, "wb") as out:
            out.write(self.rfile.read(size))
        self.send_response(200); self.end_headers(); self.wfile.write(b'{"ok":true}')
    def do_GET(self):
        response = {"state": "resolved", "result": {"action": action, "responder": "nob", "state": "resolved"}}
        body = json.dumps(response).encode()
        self.send_response(200); self.end_headers(); self.wfile.write(body)
server = HTTPServer(("127.0.0.1", 0), Handler)
with open(port_file, "w") as out:
    out.write(str(server.server_address[1]))
server.serve_forever()
PY
    SERVER_PID=$!
    # ~10s de folga. Eram 20×0.05s = 1s, que basta numa máquina quente mas não
    # num runner de CI frio: o interpretador leva mais que isso só pra subir, e
    # o gate reprovava sem dizer por quê.
    for _ in {1..100}; do
        if [ -s "$port_file" ]; then
            SERVER_PORT="$(<"$port_file")"
            curl -sf -m 1 "http://127.0.0.1:$SERVER_PORT/ready" >/dev/null 2>&1 && return
        fi
        sleep 0.1
    done
    echo "servidor de teste não subiu a tempo" >&2
    return 1
}

run_case() { # $1=action $2=expected JSON
    local action="$1" expected="$2" payload output expected_details
    payload="$TMP/$action.json"
    start_api "$action" "$payload"
    output="$(KNOBLER_PORT="$SERVER_PORT" KNOBLER_AGENT_REQUEST_TOKEN="$TOKEN_FILE" "$ROOT/knobler-permission.sh" < "$FIXTURE")"
    kill "$SERVER_PID" 2>/dev/null || true
    wait "$SERVER_PID" 2>/dev/null || true
    unset SERVER_PID
    test "$output" = "$expected"
    expected_details="$(jq -c '{session_id, tool_name, tool_input, permission_suggestions}' "$FIXTURE")"
    jq -e --argjson details "$expected_details" '
        .agent == "claude" and .kind == "permission" and .source == "terminal"
        and .title == "Bash" and .summary == "Run test suite"
        and ((.details | fromjson) == $details)
        and .actions == [{"action":"allow"},{"action":"allowForSession"},{"action":"deny"}]' "$payload" >/dev/null
}

run_case allow '{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"allow"}}}'
run_case deny '{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"deny"}}}'
run_case allowForSession '{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"allow","updatedPermissions":[{"type":"addRules","rules":[{"toolName":"Bash","ruleContent":"npm test"}],"behavior":"allow","destination":"session"}]}}}'

DOWN="$(KNOBLER_PORT=1 KNOBLER_AGENT_REQUEST_TOKEN="$TOKEN_FILE" "$ROOT/knobler-permission.sh" < "$FIXTURE")"
test -z "$DOWN"

TIMEOUT_PAYLOAD="$TMP/timeout.json"
start_api timeout "$TIMEOUT_PAYLOAD"
TIMEOUT="$(KNOBLER_PORT="$SERVER_PORT" KNOBLER_AGENT_REQUEST_TOKEN="$TOKEN_FILE" "$ROOT/knobler-permission.sh" < "$FIXTURE")"
kill "$SERVER_PID" 2>/dev/null || true
wait "$SERVER_PID" 2>/dev/null || true
unset SERVER_PID
test -z "$TIMEOUT"

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
