#!/usr/bin/env bash
# Prova de ponta a ponta da regra "a instância mais nova vence"
# (Knobler/InstanciaUnica*.swift) com o AppKit e o LaunchServices de verdade.
# Empacota tools/instancia-e2e.swift num .app-brinquedo com bundle id próprio
# (com.zoi.knobler.instanciateste): NÃO toca no Knobler instalado nem na
# instância aberta. Precisa de sessão gráfica (`open -n`), por isso só roda em
# `./tools/check.sh --com-ambiente`. A decisão pura tem o gate hermético
# tools/instanciacheck.swift.
#
# Uso: ./tools/instancia-e2e.sh
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

DIR=$(mktemp -d /tmp/instancia-e2e.XXXXXX)
APP="$DIR/InstanciaTeste.app"
BIN="$APP/Contents/MacOS/InstanciaTeste"
SOLTO="$DIR/solto"
LOG="$DIR/log.txt"
LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister

limpa() {
  pkill -f "$BIN" 2>/dev/null || true
  pkill -f "$SOLTO" 2>/dev/null || true
  "$LSREGISTER" -u "$APP" 2>/dev/null || true
  rm -rf "$DIR"
}
trap limpa EXIT

mkdir -p "$APP/Contents/MacOS"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleIdentifier</key><string>com.zoi.knobler.instanciateste</string>
  <key>CFBundleExecutable</key><string>InstanciaTeste</string>
  <key>CFBundleName</key><string>InstanciaTeste</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>LSUIElement</key><true/>
</dict></plist>
PLIST
xcrun swiftc -parse-as-library -swift-version 5 \
  Knobler/InstanciaUnica.swift Knobler/InstanciaUnicaPartida.swift tools/instancia-e2e.swift \
  -o "$BIN"
codesign -s - --force "$APP" 2>/dev/null

falha() { echo "FALHOU: $1"; echo "--- log"; cat "$LOG" 2>/dev/null || true; exit 1; }
vivos() { pgrep -f "$BIN" | sort -n | tr '\n' ' ' | sed 's/ $//'; }
# espera_ate <segundos> <comando...>: true assim que o comando passar
espera_ate() {
  local limite=$1; shift
  local fim=$(( $(date +%s) + limite ))
  until "$@"; do
    [ "$(date +%s)" -ge "$fim" ] && return 1
    sleep 0.1
  done
}
montaram() { grep -c " montou$" "$LOG" 2>/dev/null || true; }
ultimo_montou() { grep " montou$" "$LOG" | tail -1 | cut -d' ' -f1; }
evento() { grep -q "^$1 $2$" "$LOG" 2>/dev/null; }
so_viva() { [ "$(vivos)" = "$1" ]; }
reinicia() { pkill -f "$BIN" 2>/dev/null || true; espera_ate 5 bash -c "! pgrep -f '$BIN' >/dev/null"; : > "$LOG"; }
sobe() { # sobe <n de "montou" esperado> <comando...>
  local n=$1; shift
  "$@"
  espera_ate 10 bash -c "[ \$(grep -c ' montou\$' '$LOG' 2>/dev/null) -ge $n ]" \
    || falha "não montou ($*)"
}

: > "$LOG"

echo "1. open -n com uma aberta: a antiga sai pelo quit normal"
sobe 1 open -n "$APP"; A=$(ultimo_montou)
sobe 2 open -n "$APP"; B=$(ultimo_montou)
espera_ate 5 so_viva "$B" || falha "esperava só $B viva, tem: $(vivos)"
evento "$A" saiu-limpo || falha "$A não passou pelo applicationWillTerminate"

echo "2. binário executado direto (a evidência do bug): mesma coisa"
sobe 3 bash -c "('$BIN' >/dev/null 2>&1 &)"; C=$(ultimo_montou)
espera_ate 5 so_viva "$C" || falha "esperava só $C viva, tem: $(vivos)"
evento "$B" saiu-limpo || falha "$B não saiu limpo"

echo "3. quit adiado (terminateLater): espera e sai limpo"
reinicia
sobe 1 open -n "$APP" --args --adia; A=$(ultimo_montou)
sobe 2 open -n "$APP"; B=$(ultimo_montou)
espera_ate 5 so_viva "$B" || falha "esperava só $B viva, tem: $(vivos)"
evento "$A" adiou && evento "$A" saiu-limpo || falha "$A não adiou e saiu limpo"

echo "4. quit recusado (Descanso): forceTerminate depois de ~5 s"
reinicia
sobe 1 open -n "$APP" --args --veta; A=$(ultimo_montou)
t0=$(date +%s)
sobe 2 open -n "$APP"; B=$(ultimo_montou)
dt=$(( $(date +%s) - t0 ))
[ "$dt" -ge 4 ] || falha "a nova montou em ${dt}s, antes do prazo do quit"
espera_ate 3 so_viva "$B" || falha "esperava só $B viva, tem: $(vivos)"
evento "$A" vetou || falha "$A não recebeu o quit"
! evento "$A" saiu-limpo || falha "$A não devia ter saído limpo (vetou)"

echo "5. três lançamentos simultâneos: sobra uma, e só ela montou"
reinicia
open -n "$APP" & open -n "$APP" & open -n "$APP" & wait
espera_ate 10 bash -c "[ \$(pgrep -f '$BIN' | wc -l) -eq 1 ] && grep -q ' montou\$' '$LOG'" \
  || falha "não convergiu pra uma: $(vivos)"
sleep 1
[ "$(vivos | wc -w | tr -d ' ')" = 1 ] || falha "mais de uma viva: $(vivos)"
[ "$(montaram)" = 1 ] || falha "montaram $(montaram), esperava 1"

echo "6. headless antes do app: convive (o --selfcheck faz check-in no LaunchServices)"
reinicia
"$BIN" --selfcheck >/dev/null 2>&1 &
CLI=$!
espera_ate 5 grep -q "^$CLI selfcheck$" "$LOG" || falha "headless não subiu"
t0=$(date +%s)
sobe 1 open -n "$APP"
dt=$(( $(date +%s) - t0 ))
# sem o filtro pelo argv, a app tratava o headless como instância antiga e só
# montava depois de esperar o quit (5 s) e derrubá-lo à força
[ "$dt" -lt 4 ] || falha "a app levou ${dt}s pra montar: esperou o headless sair"
sleep 1
kill -0 "$CLI" 2>/dev/null || falha "a instância nova derrubou o processo headless"
kill "$CLI" 2>/dev/null || true
wait "$CLI" 2>/dev/null || true

echo "7. headless logo depois do app: a app não sai achando que ele é mais nova"
reinicia
open -n "$APP" &
OPEN=$!
"$BIN" --selfcheck >/dev/null 2>&1 &
CLI=$!
wait "$OPEN" 2>/dev/null || true
sobe 1 true
espera_ate 5 grep -q "^$CLI selfcheck$" "$LOG" || falha "headless não subiu"
sleep 1
kill -0 "$CLI" 2>/dev/null || falha "a app derrubou o headless"
[ -n "$(vivos | tr ' ' '\n' | grep -vx "$CLI")" ] || falha "só o headless ficou vivo: a app saiu"
kill "$CLI" 2>/dev/null || true
wait "$CLI" 2>/dev/null || true

echo "8. sem bundle id (harness, binário solto): não derruba ninguém"
A=$(ultimo_montou)
cp "$BIN" "$SOLTO"
"$SOLTO" >/dev/null 2>&1 &
disown  # o pkill da limpeza não vira "Terminated" na saída
espera_ate 5 bash -c "[ \$(grep -c ' montou\$' '$LOG') -ge 2 ]" || falha "o solto não montou"
so_viva "$A" || falha "o solto derrubou a instância do bundle: $(vivos)"

echo "✅ instancia-e2e ok"
