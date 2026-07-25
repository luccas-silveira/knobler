#!/bin/bash
# PermissionRequest hook: mirrors a native Claude permission prompt in NOB.
# API failures deliberately emit nothing, leaving Claude's own prompt intact.
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$ROOT/knobler-hook-common.sh" || exit 0
PORT="${KNOBLER_PORT:-4477}"
INPUT="$(cat)"

knobler_hook_token || exit 0
ID="$(knobler_hook_id claude-permission "$(printf '%s' "$INPUT" | jq -r '.session_id // "session"' 2>/dev/null)")"
PAYLOAD="$(printf '%s' "$INPUT" | jq -c --arg id "$ID" '
    def text: if type == "string" then . else tojson end;
    {
        id: $id,
        agent: "claude",
        kind: "permission",
        title: (.tool_name // "Permission"),
        summary: (if (.tool_input | type) == "object" then
            (.tool_input.description // .tool_input.command // .tool_input.file_path // .tool_input.path // .tool_input | text)
        else .tool_input | text end),
        details: {session_id: (.session_id // ""), tool_name: (.tool_name // ""), tool_input: (.tool_input // {}), permission_suggestions: (.permission_suggestions // [])} | tojson,
        source: "terminal",
        actions: ([{"action":"allow"}]
            + (if any(.permission_suggestions[]?; .behavior == "allow") then [{"action":"allowForSession"}] else [] end)
            + [{"action":"deny"}])
    }')" || exit 0

curl -sf -m 1 -X POST -H "Authorization: Bearer $KNOBLER_AGENT_TOKEN" \
    --data-binary "$PAYLOAD" "http://127.0.0.1:$PORT/agent-requests" >/dev/null 2>&1 || exit 0

DEADLINE="$(knobler_hook_deadline 570)"
STATE="$(knobler_hook_poll "http://127.0.0.1:$PORT/agent-requests/$ID" "$DEADLINE" "$KNOBLER_AGENT_TOKEN")"
POLL_STATUS=$?
if [ "$POLL_STATUS" -ne 0 ]; then
    [ "$POLL_STATUS" -eq 2 ] && curl -sf -m 1 -X POST -H "Authorization: Bearer $KNOBLER_AGENT_TOKEN" \
        "http://127.0.0.1:$PORT/agent-requests/$ID/dismiss" >/dev/null 2>&1 || true
    exit 0
fi

case "$(printf '%s' "$STATE" | jq -r '.result.action // empty' 2>/dev/null)" in
allow)
    printf '%s\n' '{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"allow"}}}'
    ;;
allowForSession)
    SESSION_UPDATES="$(printf '%s' "$INPUT" | jq -c '[.permission_suggestions[]? | select(.behavior == "allow") | .destination = "session"]')" || exit 0
    [ "$SESSION_UPDATES" != '[]' ] || exit 0
    jq -cn --argjson updates "$SESSION_UPDATES" '{hookSpecificOutput:{hookEventName:"PermissionRequest",decision:{behavior:"allow",updatedPermissions:$updates}}}'
    ;;
deny)
    printf '%s\n' '{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"deny"}}}'
    ;;
esac
