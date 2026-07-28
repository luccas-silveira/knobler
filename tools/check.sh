#!/usr/bin/env bash
# Roda todos os self-checks do projeto. É o que a CI executa — rode antes de
# abrir PR pra ver o mesmo resultado localmente.
#
# Uso: ./tools/check.sh [--com-ambiente]
#   --com-ambiente: inclui os gates que dependem de ferramenta externa
#                   (hoje: codex CLI). Sem a flag, eles são pulados.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

WITH_ENV=0
[ "${1:-}" = "--com-ambiente" ] && WITH_ENV=1

FAILED=()
PASSED=0
SKIPPED=()

# ponytail: o binário vai pro /tmp; nenhum check precisa de artefato persistente.
run() {
  local name="$1"; shift
  printf "  %-26s " "$name"
  if out=$("$@" 2>&1); then
    echo "ok"
    PASSED=$((PASSED + 1))
  else
    echo "FALHOU"
    printf '%s\n' "$out" | tail -15 | sed 's/^/      /'
    FAILED+=("$name")
  fi
}

# Compila os fontes indicados junto do harness e roda o binário.
# `main.swift` traz código top-level e por isso NÃO aceita -parse-as-library.
swift_check() {
  local name="$1"; shift
  local flags="-swift-version 5"
  case " $* " in
    *"main.swift "*) ;;
    *) flags="-parse-as-library $flags" ;;
  esac
  run "$name" bash -c "xcrun swiftc $flags $* -o /tmp/$name && /tmp/$name"
}

echo "== self-checks Swift =="
swift_check askcheck          Knobler/AskModels.swift Knobler/AskFeature.swift tools/askcheck.swift
swift_check updatercheck      Knobler/Updater.swift tools/updatercheck.swift
swift_check agentrequestcheck Knobler/AgentRequestModels.swift Knobler/AgentRequestStore.swift tools/agentrequestcheck.swift
swift_check airpodscheck      Knobler/AirPodsBattery.swift tools/airpods_selfcheck.swift
swift_check wirecheck         Knobler/Wire.swift tools/wirecheck/main.swift

echo "== gates de integração =="
run claude-hook          bash tools/claude-hook/test.sh
run codex-bridge         node tools/codex-agent-bridge-check.mjs
run agent-requests-e2e   node tools/agent-requests-e2e.mjs

if [ "$WITH_ENV" -eq 1 ]; then
  echo "== gates que dependem do ambiente =="
  if command -v codex >/dev/null; then
    run codex-integration node tools/codex-integration-check.mjs
  else
    SKIPPED+=("codex-integration (codex CLI não instalado)")
  fi
else
  SKIPPED+=("codex-integration (rode com --com-ambiente)")
fi

echo
for s in ${SKIPPED+"${SKIPPED[@]}"}; do echo "  pulado: $s"; done
if [ ${#FAILED[@]} -gt 0 ]; then
  echo "❌ $PASSED ok, ${#FAILED[@]} falhou: ${FAILED[*]}"
  exit 1
fi
echo "✅ $PASSED checks ok"
