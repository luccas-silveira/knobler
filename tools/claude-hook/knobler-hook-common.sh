#!/bin/bash
# Small shared primitives for the safe Claude hooks. They never print secrets.

knobler_hook_id() { # $1=prefix $2=session id
    local session
    session="$(printf '%s' "${2:-session}" | tr -cs 'A-Za-z0-9._-' '-')"
    session="${session:0:48}"
    printf '%s-%s-%s-%s\n' "$1" "${session:-session}" "$$" "$(date +%s)"
}

knobler_hook_deadline() { # $1=seconds from now
    printf '%s\n' "$(( $(date +%s) + $1 ))"
}

knobler_hook_token() {
    local token_file="${KNOBLER_AGENT_REQUEST_TOKEN:-$HOME/Library/Application Support/Knobler/agent-request-token}"
    [ -r "$token_file" ] || return 1
    KNOBLER_AGENT_TOKEN="$(<"$token_file")"
    [ -n "$KNOBLER_AGENT_TOKEN" ]
}

# Long-poll: o app segura o GET até o estado ficar final ou o prazo do
# X-Knobler-Wait vencer (teto de 25 s). O app antigo ignora o header e
# responde na hora; aí o sleep do laço vira o polling de antes.
# `KNOBLER_LONGPOLL_WAIT` só existe pro e2e encurtar a espera.
KNOBLER_HOOK_WAIT="${KNOBLER_LONGPOLL_WAIT:-25}"

knobler_hook_poll() { # $1=url $2=deadline epoch [$3=bearer token]
    local state espera rc header=()
    [ -n "${3:-}" ] && header=(-H "Authorization: Bearer $3")
    while [ "$(date +%s)" -lt "$2" ]; do
        # nunca pede espera além do deadline: o cancel do timeout precisa caber
        espera=$(( $2 - $(date +%s) ))
        if [ "$espera" -gt "$KNOBLER_HOOK_WAIT" ]; then espera="$KNOBLER_HOOK_WAIT"; fi
        if [ "$espera" -lt 1 ]; then espera=1; fi
        # `${header[@]+…}`: no bash 3.2 do macOS, array vazio com `set -u`
        # aborta com "unbound variable" (o poll sem token do Ask sempre falhava)
        state="$(curl -sf -m "$((espera + 5))" -H "X-Knobler-Wait: $espera" \
            ${header[@]+"${header[@]}"} "$1" 2>/dev/null)"
        rc=$?
        if [ "$rc" -eq 28 ]; then
            # Timeout do curl não é "API caiu": o -m dele conta o tempo em que
            # o Mac dormiu e o prazo do app não, então um sono no meio da espera
            # estoura o curl com o card ainda pendente. Uma leitura sem espera
            # separa os dois casos — o app responde (segue o laço) ou está
            # travado de verdade (desiste, como antes).
            state="$(curl -sf -m 2 ${header[@]+"${header[@]}"} "$1" 2>/dev/null)" || return 1
        elif [ "$rc" -ne 0 ]; then
            return 1
        fi
        if [ "$(printf '%s' "$state" | jq -r '(.answered // false) or (.cancelled // false) or ((.state // "pending") != "pending")' 2>/dev/null)" = "true" ]; then
            printf '%s' "$state"
            return 0
        fi
        sleep 0.3
    done
    return 2
}
