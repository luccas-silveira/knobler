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

knobler_hook_poll() { # $1=url $2=deadline epoch [$3=bearer token]
    local state header=()
    [ -n "${3:-}" ] && header=(-H "Authorization: Bearer $3")
    while [ "$(date +%s)" -lt "$2" ]; do
        state="$(curl -sf -m 2 "${header[@]}" "$1" 2>/dev/null)" || return 1
        if [ "$(printf '%s' "$state" | jq -r '(.answered // false) or (.cancelled // false) or ((.state // "pending") != "pending")' 2>/dev/null)" = "true" ]; then
            printf '%s' "$state"
            return 0
        fi
        sleep 0.3
    done
    return 2
}
