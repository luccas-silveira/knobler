#!/usr/bin/env bash
# Gate da etapa 13 do WhatsApp: o filtro do banner ligado nos arquivos que só o
# app compila.
#
# O ./tools/check.sh não compila o app; o whatsappbannercheck prova a regra
# pura, não que o interceptor a chama nem que o AppDelegate entrega o estado
# da ponte. Confere:
#   - Knobler/NotificationInterceptor.swift tem
#     `var ponteWhatsAppConectada: () -> Bool = { false }`;
#   - Knobler/NotificationInterceptor.swift chama
#     `NotificationRules.descartaBannerDoWhatsApp(appName: parsed.appName, bundleID: appAberto, ponteConectada: ponteWhatsAppConectada())`
#     numa linha DEPOIS de `switch AirDropRegras.faseDoAlerta` e ANTES de
#     `let buttons = actionButtons(in: banner)` (números de linha), e entre a
#     chamada e o `let buttons` há `close(banner)` e `return` (o banner some,
#     mesmo com botão, e não vira card);
#   - Knobler/KnoblerApp.swift tem
#     `interceptor.ponteWhatsAppConectada = { MainActor.assumeIsolated { WhatsAppStore.shared.ponteConectada } }`.
# Linha de comentário (`//`) não conta como ligação.
# Cada falta imprime `FALHOU: <o quê>` e o gate sai 1. Antes da checagem real,
# um autoteste num repo falso prova que a verificação reprova.
#
# Uso: bash tools/whatsappbannerligacaocheck.sh
set -uo pipefail
cd "$(dirname "$0")/.."

PROP='var ponteWhatsAppConectada: () -> Bool = { false }'
CHAMADA='NotificationRules.descartaBannerDoWhatsApp(appName: parsed.appName, bundleID: appAberto, ponteConectada: ponteWhatsAppConectada())'
AIRDROP='switch AirDropRegras.faseDoAlerta'
BOTOES='let buttons = actionButtons(in: banner)'
LIGACAO='interceptor.ponteWhatsAppConectada = { MainActor.assumeIsolated { WhatsAppStore.shared.ponteConectada } }'

# linha <arquivo> <texto fixo>: número da primeira linha de código (não
# comentário) que contém o texto; vazio se não houver.
linha() {
  grep -nF -- "$2" "$1" 2>/dev/null | grep -vE '^[0-9]+:[[:space:]]*//' | head -1 | cut -d: -f1
}

# tem <arquivo> <texto fixo>: existe linha de código com o texto.
tem() { [ -n "$(linha "$1" "$2")" ]; }

# trecho_tem <arquivo> <de> <até (exclusivo)> <texto fixo>: alguma linha de
# código no intervalo contém o texto.
trecho_tem() {
  sed -n "$2,$(($3 - 1))p" "$1" | grep -vE '^[[:space:]]*//' | grep -qF -- "$4"
}

# verificar <raiz>
verificar() {
  local r="$1" erro=0
  local inter="$r/Knobler/NotificationInterceptor.swift"
  local app="$r/Knobler/KnoblerApp.swift"
  local a b c f

  for f in "$inter" "$app"; do
    if [ ! -f "$f" ]; then
      echo "FALHOU: ${f#"$r"/} não existe"
      erro=1
    fi
  done

  if [ -f "$inter" ]; then
    if ! tem "$inter" "$PROP"; then
      echo "FALHOU: Knobler/NotificationInterceptor.swift sem '$PROP'"
      erro=1
    fi
    a=$(linha "$inter" "$AIRDROP")
    b=$(linha "$inter" "$CHAMADA")
    c=$(linha "$inter" "$BOTOES")
    if [ -z "$a" ]; then
      echo "FALHOU: Knobler/NotificationInterceptor.swift sem '$AIRDROP'"
      erro=1
    fi
    if [ -z "$c" ]; then
      echo "FALHOU: Knobler/NotificationInterceptor.swift sem '$BOTOES'"
      erro=1
    fi
    if [ -z "$b" ]; then
      echo "FALHOU: Knobler/NotificationInterceptor.swift sem '$CHAMADA'"
      erro=1
    elif [ -n "$a" ] && [ -n "$c" ]; then
      if ! { [ "$a" -lt "$b" ] && [ "$b" -lt "$c" ]; }; then
        echo "FALHOU: a chamada do filtro (linha $b) tem que vir depois de '$AIRDROP' (linha $a) e antes de '$BOTOES' (linha $c)"
        erro=1
      else
        if ! trecho_tem "$inter" "$b" "$c" 'close(banner)'; then
          echo "FALHOU: o filtro (linha $b) não fecha o banner com close(banner) antes de '$BOTOES' (linha $c)"
          erro=1
        fi
        if ! trecho_tem "$inter" "$b" "$c" 'return'; then
          echo "FALHOU: o filtro (linha $b) não sai com return antes de '$BOTOES' (linha $c)"
          erro=1
        fi
      fi
    fi
  fi

  if [ -f "$app" ] && ! tem "$app" "$LIGACAO"; then
    echo "FALHOU: Knobler/KnoblerApp.swift sem '$LIGACAO'"
    erro=1
  fi

  return "$erro"
}

# --- autoteste ---------------------------------------------------------------
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT

# repo falso com a ligação certa; cada caso estraga uma coisa
montar() {
  rm -rf "$T/r"
  mkdir -p "$T/r/Knobler"
  cat > "$T/r/Knobler/NotificationInterceptor.swift" <<'EOF'
final class NotificationInterceptor {
    var ponteWhatsAppConectada: () -> Bool = { false }

    private func process(_ banner: AXUIElement) {
        guard let parsed = parse(banner) else { return }
        let appAberto = parsed.appName.flatMap { nome in nome }
        switch AirDropRegras.faseDoAlerta(appName: parsed.appName, title: parsed.title) {
        case .recebendo: return
        case .concluido: close(banner); return
        case nil: break
        }
        if NotificationRules.descartaBannerDoWhatsApp(appName: parsed.appName, bundleID: appAberto, ponteConectada: ponteWhatsAppConectada()) {
            close(banner)
            log.notice("banner do WhatsApp descartado: a ponte está conectada")
            return
        }
        let buttons = actionButtons(in: banner)
        if buttons.isEmpty { close(banner) }
    }
}
EOF
  cat > "$T/r/Knobler/KnoblerApp.swift" <<'EOF'
func applicationDidFinishLaunching() {
    let interceptor = NotificationInterceptor { [weak self] notch in
        self?.publicar(notch)
    }
    interceptor.ponteWhatsAppConectada = { MainActor.assumeIsolated { WhatsAppStore.shared.ponteConectada } }
    interceptor.start()
}
EOF
}

AUTO=0
# caso <nome> <código esperado> <texto esperado ou vazio> -- monta $T/r antes
caso() {
  local nome="$1" esperado="$2" texto="$3" saida codigo
  saida=$(verificar "$T/r" 2>&1); codigo=$?
  if [ "$codigo" != "$esperado" ]; then
    echo "autoteste ($nome): saiu com $codigo, esperado $esperado"
    printf '%s\n' "$saida" | sed 's/^/    | /'
    AUTO=1
  elif [ -n "$texto" ] && ! printf '%s\n' "$saida" | grep -qF -- "$texto"; then
    echo "autoteste ($nome): saída sem '$texto'"
    printf '%s\n' "$saida" | sed 's/^/    | /'
    AUTO=1
  fi
}

INTER="$T/r/Knobler/NotificationInterceptor.swift"
APP="$T/r/Knobler/KnoblerApp.swift"

montar
caso "ligação certa" 0 ""

montar
# a forma de uma linha só também vale
perl -0pi -e 's/ponteWhatsAppConectada\(\)\) \{\n\s*close\(banner\)\n\s*log\.notice\("[^"]*"\)\n\s*return\n\s*\}/ponteWhatsAppConectada()) { close(banner); return }/' "$INTER"
caso "filtro numa linha só" 0 ""

montar
sed -i '' '/var ponteWhatsAppConectada/d' "$INTER"
caso "propriedade ausente" 1 "sem '$PROP'"

montar
sed -i '' 's/var ponteWhatsAppConectada: () -> Bool = { false }/var ponteWhatsAppConectada: () -> Bool = { true }/' "$INTER"
caso "propriedade nascendo true" 1 "sem '$PROP'"

montar
sed -i '' 's/ponteConectada: ponteWhatsAppConectada())/ponteConectada: true)/' "$INTER"
caso "chamada sem o estado da ponte" 1 "sem '$CHAMADA'"

montar
sed -i '' 's|^        if NotificationRules.descartaBannerDoWhatsApp|        // if NotificationRules.descartaBannerDoWhatsApp|' "$INTER"
caso "chamada só em comentário" 1 "sem '$CHAMADA'"

montar
cat > "$INTER" <<'EOF'
final class NotificationInterceptor {
    var ponteWhatsAppConectada: () -> Bool = { false }

    private func process(_ banner: AXUIElement) {
        if NotificationRules.descartaBannerDoWhatsApp(appName: parsed.appName, bundleID: appAberto, ponteConectada: ponteWhatsAppConectada()) {
            close(banner); return
        }
        switch AirDropRegras.faseDoAlerta(appName: parsed.appName, title: parsed.title) {
        case nil: break
        }
        let buttons = actionButtons(in: banner)
    }
}
EOF
caso "filtro antes do AirDrop" 1 "tem que vir depois de '$AIRDROP'"

montar
cat > "$INTER" <<'EOF'
final class NotificationInterceptor {
    var ponteWhatsAppConectada: () -> Bool = { false }

    private func process(_ banner: AXUIElement) {
        switch AirDropRegras.faseDoAlerta(appName: parsed.appName, title: parsed.title) {
        case nil: break
        }
        let buttons = actionButtons(in: banner)
        if NotificationRules.descartaBannerDoWhatsApp(appName: parsed.appName, bundleID: appAberto, ponteConectada: ponteWhatsAppConectada()) {
            close(banner); return
        }
    }
}
EOF
caso "filtro depois dos botões" 1 "antes de '$BOTOES'"

montar
sed -i '' '/^            close(banner)$/d' "$INTER"
caso "filtro sem fechar o banner" 1 "não fecha o banner"

montar
sed -i '' '/^            return$/d' "$INTER"
caso "filtro sem return" 1 "não sai com return"

montar
sed -i '' '/switch AirDropRegras.faseDoAlerta/d' "$INTER"
caso "switch do AirDrop ausente" 1 "sem '$AIRDROP'"

montar
sed -i '' '/let buttons = actionButtons/d' "$INTER"
caso "let buttons ausente" 1 "sem '$BOTOES'"

montar
rm "$INTER"
caso "interceptor ausente" 1 "Knobler/NotificationInterceptor.swift não existe"

montar
sed -i '' '/interceptor.ponteWhatsAppConectada/d' "$APP"
caso "ligação no AppDelegate ausente" 1 "sem '$LIGACAO'"

montar
sed -i '' 's/{ MainActor.assumeIsolated { WhatsAppStore.shared.ponteConectada } }/{ true }/' "$APP"
caso "AppDelegate entrega true fixo" 1 "sem '$LIGACAO'"

montar
sed -i '' 's|^    interceptor.ponteWhatsAppConectada|    // interceptor.ponteWhatsAppConectada|' "$APP"
caso "ligação só em comentário" 1 "sem '$LIGACAO'"

if [ "$AUTO" -ne 0 ]; then
  echo "FALHOU: autoteste do whatsappbannerligacaocheck"
  exit 1
fi

# --- checagem real -----------------------------------------------------------
verificar . || exit 1
echo "whatsappbannerligacaocheck ok"
