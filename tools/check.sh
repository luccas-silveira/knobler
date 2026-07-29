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
    # "command not found" some no meio de um heredoc ecoado — puxa pra cima.
    printf '%s\n' "$out" | grep -iE "command not found|No such file|not installed" \
      | sort -u | sed 's/^/      ⚠ /'
    # saída inteira: é curta, e truncar já escondeu a causa uma vez
    printf '%s\n' "$out" | sed 's/^/      /'
    # `test`/`jq -e` sob `set -e` falham em silêncio: sem o trace não dá pra
    # saber QUAL asserção caiu. Re-roda o gate com -x só pra colher isso.
    if [ "$1" = "bash" ] || [ "${1##*/}" = "bash" ]; then
      echo "      --- trace (bash -x) ---"
      # só as linhas de comando do trace: heredoc ecoado (sem '+') afogaria o fim.
      bash -x "${@:2}" 2>&1 | grep '^+' | tail -25 | sed 's/^/      /'
    fi
    FAILED+=("$name")
  fi
}

# Dependências que não vêm no macOS limpo (nem no runner da CI).
for dep in jq node; do
  command -v "$dep" >/dev/null || {
    echo "❌ falta '$dep' — os gates de integração precisam dele (brew install $dep)"
    exit 1
  }
done

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
swift_check webhookcheck      Knobler/WebhookKeychainStore.swift tools/webhookcheck.swift
swift_check colorpickercheck  Knobler/ColorPicker.swift tools/colorpickercheck.swift
CONVERSAO="Knobler/FileConverter.swift Knobler/ImageConverter.swift Knobler/DocumentConverter.swift Knobler/VideoConverter.swift"
swift_check imageconvertercheck    $CONVERSAO tools/imageconvertercheck.swift
swift_check documentconvertercheck $CONVERSAO tools/documentconvertercheck.swift
swift_check sharingcheck          Knobler/Sharing.swift Knobler/NotificationRules.swift tools/sharingcheck.swift
swift_check historycheck          Knobler/NotchNotification.swift Knobler/NotificationHistory.swift Knobler/NotchGesture.swift tools/historycheck.swift
# Reminders traz o próprio @main atrás de -D (molde do Pomodoro), sem harness.
run reminderscheck bash -c "xcrun swiftc -parse-as-library -swift-version 5 \
  -D REMINDERS_SELFCHECK Knobler/Reminders.swift -o /tmp/reminderscheck && /tmp/reminderscheck"

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
