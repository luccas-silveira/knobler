#!/usr/bin/env bash
# Gate da etapa 12 do WhatsApp: a peça ligada nos arquivos que só o app compila.
#
# O ./tools/check.sh não compila o app; sem este gate uma ligação esquecida no
# AppDelegate passaria verde (o whatsapppecacheck prova a máquina de peças com
# efeitos falsos, não que o app atribui os efeitos de verdade). Confere:
#   - Knobler/KnoblerApp.swift tem
#     `plugins.whatsappEfeitos = WhatsAppEfeitos(nascer: { WhatsAppPeca.ligar() })`
#     ANTES da chamada `plugins.subir()` (número da linha);
#   - Knobler/KnoblerApp.swift tem `await WhatsAppSonda.shared.sondar()` DEPOIS
#     da chamada `plugins.subir()`;
#   - Knobler/WhatsApp/WhatsAppPeca.swift tem `extension WhatsAppStore: PluginServico`,
#     `WhatsAppStore.shared.start()` e `MainActor.assumeIsolated { stop() }`;
#   - Knobler/PluginsSettingsPane.swift tem `case .whatsapp: return .indigo`;
#   - nenhum .swift de Knobler/WhatsApp/ além do WhatsAppPeca.swift cita
#     `PluginServico` (a conformidade fica isolada para os gates do estado não
#     arrastarem Plugin.swift).
# Linha de comentário (`//`) não conta como ligação: o KnoblerApp.swift já cita
# `plugins.subir()` num comentário bem antes da chamada.
# Cada falta imprime `FALHOU: <o quê>` e o gate sai 1. Antes da checagem real,
# um autoteste num repo falso prova que a verificação reprova.
#
# Uso: bash tools/whatsapppecaligacaocheck.sh
set -uo pipefail
cd "$(dirname "$0")/.."

EFEITOS='plugins.whatsappEfeitos = WhatsAppEfeitos(nascer: { WhatsAppPeca.ligar() })'
SONDA='await WhatsAppSonda.shared.sondar()'

# linha <arquivo> <texto fixo>: número da primeira linha de código (não
# comentário) que contém o texto; vazio se não houver.
linha() {
  grep -nF -- "$2" "$1" 2>/dev/null | grep -vE '^[0-9]+:[[:space:]]*//' | head -1 | cut -d: -f1
}

# tem <arquivo> <texto fixo>: existe linha de código com o texto.
tem() { [ -n "$(linha "$1" "$2")" ]; }

# verificar <raiz>
verificar() {
  local r="$1" erro=0
  local app="$r/Knobler/KnoblerApp.swift"
  local peca="$r/Knobler/WhatsApp/WhatsAppPeca.swift"
  local ajustes="$r/Knobler/PluginsSettingsPane.swift"
  local a b c f t

  for f in "$app" "$peca" "$ajustes"; do
    if [ ! -f "$f" ]; then
      echo "FALHOU: ${f#"$r"/} não existe"
      erro=1
    fi
  done

  if [ -f "$app" ]; then
    b=$(grep -nE '^[[:space:]]*plugins\.subir\(\)' "$app" | head -1 | cut -d: -f1)
    a=$(linha "$app" "$EFEITOS")
    c=$(linha "$app" "$SONDA")
    if [ -z "$b" ]; then
      echo "FALHOU: Knobler/KnoblerApp.swift sem a chamada plugins.subir()"
      erro=1
    fi
    if [ -z "$a" ]; then
      echo "FALHOU: Knobler/KnoblerApp.swift sem '$EFEITOS'"
      erro=1
    elif [ -n "$b" ] && ! [ "$a" -lt "$b" ]; then
      echo "FALHOU: whatsappEfeitos (linha $a) tem que vir antes de plugins.subir() (linha $b)"
      erro=1
    fi
    if [ -z "$c" ]; then
      echo "FALHOU: Knobler/KnoblerApp.swift sem '$SONDA'"
      erro=1
    elif [ -n "$b" ] && ! [ "$c" -gt "$b" ]; then
      echo "FALHOU: a sonda (linha $c) tem que vir depois de plugins.subir() (linha $b)"
      erro=1
    fi
  fi

  if [ -f "$peca" ]; then
    for t in 'extension WhatsAppStore: PluginServico' \
             'WhatsAppStore.shared.start()' \
             'MainActor.assumeIsolated { stop() }'; do
      if ! tem "$peca" "$t"; then
        echo "FALHOU: Knobler/WhatsApp/WhatsAppPeca.swift sem '$t'"
        erro=1
      fi
    done
  fi

  if [ -f "$ajustes" ] && ! tem "$ajustes" 'case .whatsapp: return .indigo'; then
    echo "FALHOU: Knobler/PluginsSettingsPane.swift sem 'case .whatsapp: return .indigo'"
    erro=1
  fi

  while IFS= read -r f; do
    [ -n "$f" ] || continue
    [ "$(basename "$f")" = "WhatsAppPeca.swift" ] && continue
    echo "FALHOU: ${f#"$r"/} cita PluginServico (a conformidade mora só em WhatsAppPeca.swift)"
    erro=1
  done < <(find "$r/Knobler/WhatsApp" -name '*.swift' -exec grep -l PluginServico {} + 2>/dev/null)

  return "$erro"
}

# --- autoteste ---------------------------------------------------------------
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT

# repo falso com a ligação certa; cada caso estraga uma coisa
montar() {
  rm -rf "$T/r"
  mkdir -p "$T/r/Knobler/WhatsApp"
  cat > "$T/r/Knobler/KnoblerApp.swift" <<'EOF'
func applicationDidFinishLaunching() {
    // ⚠️ `placeWindows()` desceu pra DEPOIS do `plugins.subir()` (fim deste
    plugins.notaRapidaEfeitos = NotaRapidaEfeitos(nascer: { QuickNote.shared })
    plugins.whatsappEfeitos = WhatsAppEfeitos(nascer: { WhatsAppPeca.ligar() })
    plugins.subir()
    Task { @MainActor in await WhatsAppSonda.shared.sondar() }
    placeWindows()
}
EOF
  cat > "$T/r/Knobler/WhatsApp/WhatsAppPeca.swift" <<'EOF'
extension WhatsAppStore: PluginServico {
    nonisolated func parar() { MainActor.assumeIsolated { stop() } }
}
enum WhatsAppPeca {
    @MainActor static func ligar() -> PluginServico {
        WhatsAppStore.shared.start()
        return WhatsAppStore.shared
    }
}
EOF
  cat > "$T/r/Knobler/WhatsApp/WhatsAppStore.swift" <<'EOF'
@MainActor
final class WhatsAppStore { static let shared = WhatsAppStore(); func start() {}; func stop() {} }
EOF
  cat > "$T/r/Knobler/PluginsSettingsPane.swift" <<'EOF'
func corDaPeca(_ id: PluginID) -> Color {
    switch id {
    case .mensagens: return .green
    case .whatsapp: return .indigo
    }
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

APP="$T/r/Knobler/KnoblerApp.swift"
PECA="$T/r/Knobler/WhatsApp/WhatsAppPeca.swift"

montar
caso "ligação certa (comentário com plugins.subir() antes não conta)" 0 ""

montar
cat > "$APP" <<'EOF'
func applicationDidFinishLaunching() {
    plugins.subir()
    plugins.whatsappEfeitos = WhatsAppEfeitos(nascer: { WhatsAppPeca.ligar() })
    Task { @MainActor in await WhatsAppSonda.shared.sondar() }
}
EOF
caso "efeitos depois do subir" 1 "tem que vir antes de plugins.subir()"

montar
sed -i '' '/plugins.whatsappEfeitos/d' "$APP"
caso "efeitos ausentes" 1 "sem '$EFEITOS'"

montar
sed -i '' 's|^    plugins.whatsappEfeitos|    // plugins.whatsappEfeitos|' "$APP"
caso "efeitos só em comentário" 1 "sem '$EFEITOS'"

montar
cat > "$APP" <<'EOF'
func applicationDidFinishLaunching() {
    plugins.whatsappEfeitos = WhatsAppEfeitos(nascer: { WhatsAppPeca.ligar() })
    Task { @MainActor in await WhatsAppSonda.shared.sondar() }
    plugins.subir()
}
EOF
caso "sonda antes do subir" 1 "tem que vir depois de plugins.subir()"

montar
sed -i '' '/WhatsAppSonda/d' "$APP"
caso "sonda ausente" 1 "sem '$SONDA'"

montar
sed -i '' '/^    plugins.subir()/d' "$APP"
caso "subir ausente" 1 "sem a chamada plugins.subir()"

montar
sed -i '' 's/extension WhatsAppStore: PluginServico/extension WhatsAppStore/' "$PECA"
caso "conformidade ausente" 1 "sem 'extension WhatsAppStore: PluginServico'"

montar
sed -i '' '/WhatsAppStore.shared.start()/d' "$PECA"
caso "start ausente" 1 "sem 'WhatsAppStore.shared.start()'"

montar
sed -i '' 's/MainActor.assumeIsolated { stop() }/stop()/' "$PECA"
caso "parar sem assumeIsolated" 1 "sem 'MainActor.assumeIsolated { stop() }'"

montar
rm "$PECA"
caso "WhatsAppPeca.swift ausente" 1 "Knobler/WhatsApp/WhatsAppPeca.swift não existe"

montar
sed -i '' 's/case .whatsapp: return .indigo/case .whatsapp: return .green/' "$T/r/Knobler/PluginsSettingsPane.swift"
caso "cor errada" 1 "sem 'case .whatsapp: return .indigo'"

montar
echo 'extension WhatsAppStore: PluginServico {}' >> "$T/r/Knobler/WhatsApp/WhatsAppStore.swift"
caso "PluginServico fora do WhatsAppPeca" 1 "Knobler/WhatsApp/WhatsAppStore.swift cita PluginServico"

if [ "$AUTO" -ne 0 ]; then
  echo "FALHOU: autoteste do whatsapppecaligacaocheck"
  exit 1
fi

# --- checagem real -----------------------------------------------------------
verificar . || exit 1
echo "whatsapppecaligacaocheck ok"
