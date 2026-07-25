#!/bin/bash
# Instala o hook do Knobler no Claude Code (global, idempotente):
# copia o script pra ~/.claude/hooks/ e registra o matcher AskUserQuestion
# com timeout de 600s em ~/.claude/settings.json.
set -euo pipefail
HOOK_DIR="$HOME/.claude/hooks"
HOOK="$HOOK_DIR/knobler-ask.sh"
PERMISSION_HOOK="$HOOK_DIR/knobler-permission.sh"
SETTINGS="$HOME/.claude/settings.json"

mkdir -p "$HOOK_DIR"
cp "$(dirname "$0")/knobler-ask.sh" "$HOOK"
cp "$(dirname "$0")/knobler-permission.sh" "$PERMISSION_HOOK"
cp "$(dirname "$0")/knobler-hook-common.sh" "$HOOK_DIR/knobler-hook-common.sh"
chmod +x "$HOOK" "$PERMISSION_HOOK"

[ -f "$SETTINGS" ] || echo '{}' > "$SETTINGS"
TMP="$(mktemp)"
jq --arg cmd "$HOOK" --arg permissionCmd "$PERMISSION_HOOK" '
    .hooks.PreToolUse = (
        ((.hooks.PreToolUse // [])
            | map(select(((.hooks // []) | any(.command == $cmd)) | not)))
        + [{matcher: "AskUserQuestion",
            hooks: [{type: "command", command: $cmd, timeout: 600}]}]
    )
    | .hooks.PermissionRequest = (
        ((.hooks.PermissionRequest // [])
            | map(select(((.hooks // []) | any(.command == $permissionCmd)) | not)))
        + [{matcher: ".*",
            hooks: [{type: "command", command: $permissionCmd, timeout: 600}]}]
    )
' "$SETTINGS" > "$TMP" && mv "$TMP" "$SETTINGS"
echo "hooks instalados: AskUserQuestion e PermissionRequest (timeout 600s)"
echo "vale a partir da PRÓXIMA sessão do Claude Code"
