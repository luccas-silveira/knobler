#!/bin/bash
# Hook PreToolUse do Claude Code: intercepta AskUserQuestion e manda a
# pergunta pro card do Knobler. Respondida lá → devolve ao Claude via
# permissionDecision deny + reason (o modelo continua com a resposta).
# Knobler fechado, ✕ no card ou timeout → sai sem output e a pergunta
# aparece no terminal como sempre. Nunca falha a sessão: exit 0 em tudo.
set -uo pipefail
PORT="${KNOBLER_PORT:-4477}"
INPUT="$(cat)"
ID="ask-$$-$(date +%s)"

PAYLOAD="$(printf '%s' "$INPUT" | jq -c --arg id "$ID" \
    '{id: $id, questions: .tool_input.questions}')" || exit 0

# Knobler fora do ar → curl falha em ms → fluxo normal do terminal
curl -sf -m 1 -X POST "localhost:$PORT/ask" -d "$PAYLOAD" >/dev/null 2>&1 || exit 0

DEADLINE=$(( $(date +%s) + 570 ))  # < timeout de 600s do hook, folga pro cancel
while [ "$(date +%s)" -lt "$DEADLINE" ]; do
    STATE="$(curl -sf -m 2 "localhost:$PORT/ask/$ID" 2>/dev/null)" || exit 0
    if [ "$(printf '%s' "$STATE" | jq -r '.cancelled // false')" = "true" ]; then
        exit 0  # ✕ no card → pergunta vai pro terminal
    fi
    if [ "$(printf '%s' "$STATE" | jq -r '.answered // false')" = "true" ]; then
        printf '%s' "$STATE" | jq -c '{
            hookSpecificOutput: {
                hookEventName: "PreToolUse",
                permissionDecision: "deny",
                permissionDecisionReason: (
                    "O usuário respondeu via Knobler (card no notch): "
                    + (.answers | to_entries | map(
                        "\"" + .key + "\" = " + (
                            if (.value.text // "") != ""
                            then "\"" + .value.text + "\""
                            else (.value.labels | map("\"" + . + "\"") | join(", "))
                            end
                        )) | join("; "))
                    + ". Prossiga considerando essas respostas como a resposta "
                    + "do usuário; NÃO repita a pergunta."
                )
            }
        }'
        exit 0
    fi
    sleep 0.3
done
# timeout: remove o card órfão e devolve ao terminal
curl -sf -m 1 -X POST "localhost:$PORT/ask/$ID/cancel" >/dev/null 2>&1 || true
exit 0
