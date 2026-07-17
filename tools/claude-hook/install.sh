#!/bin/bash
# Instala o hook do Knobler no Claude Code (global, idempotente):
# copia o script pra ~/.claude/hooks/ e registra o matcher AskUserQuestion
# com timeout de 600s em ~/.claude/settings.json.
set -euo pipefail
HOOK="$HOME/.claude/hooks/knobler-ask.sh"
SETTINGS="$HOME/.claude/settings.json"

mkdir -p "$HOME/.claude/hooks"
cp "$(dirname "$0")/knobler-ask.sh" "$HOOK"
chmod +x "$HOOK"

[ -f "$SETTINGS" ] || echo '{}' > "$SETTINGS"
TMP="$(mktemp)"
jq --arg cmd "$HOOK" '
    .hooks.PreToolUse = (
        ((.hooks.PreToolUse // [])
            | map(select(((.hooks // []) | any(.command == $cmd)) | not)))
        + [{matcher: "AskUserQuestion",
            hooks: [{type: "command", command: $cmd, timeout: 600}]}]
    )
' "$SETTINGS" > "$TMP" && mv "$TMP" "$SETTINGS"
echo "hook instalado: $HOOK (matcher AskUserQuestion, timeout 600s)"
echo "vale a partir da PRÓXIMA sessão do Claude Code"
