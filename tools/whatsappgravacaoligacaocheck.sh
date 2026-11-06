#!/usr/bin/env bash
# Gate da etapa 18 do WhatsApp: a nota de voz gravando pelo gravador do
# ditado, ligada nos arquivos que só o app compila.
#
# O ./tools/check.sh não compila o app: o `MicRecorder` mora em
# Knobler/Dictation.swift, que importa FluidAudio, e o WhatsAppPeca.swift
# arrasta o Plugin.swift. O whatsappgravacaocheck prova o store com uma fonte
# de microfone falsa, não que o app entrega a fonte de verdade. Confere:
#   - Knobler/WhatsApp/WhatsAppMicrofone.swift tem
#     `final class MicrofoneDoDitado: WAFonteDeMicrofone`, cria um
#     `MicRecorder()` e liga o `onLevel` dele;
#   - Knobler/WhatsApp/WhatsAppPeca.swift tem
#     `WhatsAppStore.shared.fonteDeMicrofone = MicrofoneDoDitado()` numa linha
#     ANTES de `WhatsAppStore.shared.start()` (número da linha).
# Linha de comentário (`//`) não conta como ligação.
# Cada falta imprime `FALHOU: <o quê>` e o gate sai 1. Antes da checagem real,
# um autoteste num repo falso prova que a verificação reprova.
#
# Uso: bash tools/whatsappgravacaoligacaocheck.sh
set -uo pipefail
cd "$(dirname "$0")/.."

CLASSE='final class MicrofoneDoDitado: WAFonteDeMicrofone'
GRAVADOR='MicRecorder()'
NIVEL='onLevel'
FONTE='WhatsAppStore.shared.fonteDeMicrofone = MicrofoneDoDitado()'
START='WhatsAppStore.shared.start()'

# linha <arquivo> <texto fixo>: número da primeira linha de código (não
# comentário) que contém o texto; vazio se não houver.
linha() {
  grep -nF -- "$2" "$1" 2>/dev/null | grep -vE '^[0-9]+:[[:space:]]*//' | head -1 | cut -d: -f1
}

tem() { [ -n "$(linha "$1" "$2")" ]; }

# verificar <raiz>
verificar() {
  local r="$1" erro=0
  local mic="$r/Knobler/WhatsApp/WhatsAppMicrofone.swift"
  local peca="$r/Knobler/WhatsApp/WhatsAppPeca.swift"
  local f lf ls

  for f in "$mic" "$peca"; do
    if [ ! -f "$f" ]; then
      echo "FALHOU: ${f#"$r"/} não existe"
      erro=1
    fi
  done

  if [ -f "$mic" ]; then
    for f in "$CLASSE" "$GRAVADOR" "$NIVEL"; do
      if ! tem "$mic" "$f"; then
        echo "FALHOU: Knobler/WhatsApp/WhatsAppMicrofone.swift sem '$f'"
        erro=1
      fi
    done
  fi

  if [ -f "$peca" ]; then
    lf=$(linha "$peca" "$FONTE")
    ls=$(linha "$peca" "$START")
    if [ -z "$lf" ]; then
      echo "FALHOU: Knobler/WhatsApp/WhatsAppPeca.swift sem '$FONTE'"
      erro=1
    fi
    if [ -z "$ls" ]; then
      echo "FALHOU: Knobler/WhatsApp/WhatsAppPeca.swift sem '$START'"
      erro=1
    fi
    if [ -n "$lf" ] && [ -n "$ls" ] && [ "$lf" -ge "$ls" ]; then
      echo "FALHOU: Knobler/WhatsApp/WhatsAppPeca.swift: '$FONTE' (linha $lf) tem que vir antes de '$START' (linha $ls)"
      erro=1
    fi
  fi

  return "$erro"
}

# --- autoteste ---------------------------------------------------------------
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT

# repo falso com a ligação certa; cada caso estraga uma coisa
montar() {
  rm -rf "$T/r"
  mkdir -p "$T/r/Knobler/WhatsApp"
  cat > "$T/r/Knobler/WhatsApp/WhatsAppMicrofone.swift" <<'EOF'
import AVFoundation

// A fonte de verdade da nota de voz: o gravador do ditado.
final class MicrofoneDoDitado: WAFonteDeMicrofone {
    private var gravador: MicRecorder?

    func comecar(nivel: @escaping (Float) -> Void) throws {
        let g = MicRecorder()
        g.onLevel = nivel
        try g.start()
        gravador = g
    }

    func parar() -> [Float] {
        defer { gravador = nil }
        return gravador?.stop() ?? []
    }
}
EOF
  cat > "$T/r/Knobler/WhatsApp/WhatsAppPeca.swift" <<'EOF'
import Foundation

extension WhatsAppStore: PluginServico {
    nonisolated func parar() { MainActor.assumeIsolated { stop() } }
}

enum WhatsAppPeca {
    @MainActor static func ligar() -> PluginServico {
        WhatsAppStore.shared.fonteDeMicrofone = MicrofoneDoDitado()
        WhatsAppStore.shared.start()
        return WhatsAppStore.shared
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

MIC="$T/r/Knobler/WhatsApp/WhatsAppMicrofone.swift"
PECA="$T/r/Knobler/WhatsApp/WhatsAppPeca.swift"

montar
caso "ligação certa" 0 ""

montar
# comentário citando o start antes da atribuição não conta
sed -i '' 's|^enum WhatsAppPeca {|// WhatsAppStore.shared.start() só depois da fonte\
enum WhatsAppPeca {|' "$PECA"
caso "comentário com o start antes" 0 ""

montar
sed -i '' 's|^final class MicrofoneDoDitado: WAFonteDeMicrofone {|final class MicrofoneDoDitado {|' "$MIC"
caso "classe sem a conformidade" 1 "sem '$CLASSE'"

montar
sed -i '' 's|^final class MicrofoneDoDitado: WAFonteDeMicrofone {|// final class MicrofoneDoDitado: WAFonteDeMicrofone {\
final class Outra {|' "$MIC"
caso "classe só em comentário" 1 "sem '$CLASSE'"

montar
sed -i '' 's|let g = MicRecorder()|let g = OutroGravador()|' "$MIC"
caso "sem o MicRecorder" 1 "sem '$GRAVADOR'"

montar
sed -i '' '/g.onLevel = nivel/d' "$MIC"
caso "sem o onLevel" 1 "sem '$NIVEL'"

montar
sed -i '' 's|^        g.onLevel = nivel|        // g.onLevel = nivel|' "$MIC"
caso "onLevel só em comentário" 1 "sem '$NIVEL'"

montar
sed -i '' '/fonteDeMicrofone = MicrofoneDoDitado()/d' "$PECA"
caso "peça sem entregar a fonte" 1 "sem '$FONTE'"

montar
sed -i '' 's|^        WhatsAppStore.shared.fonteDeMicrofone = MicrofoneDoDitado()|        // WhatsAppStore.shared.fonteDeMicrofone = MicrofoneDoDitado()|' "$PECA"
caso "fonte só em comentário" 1 "sem '$FONTE'"

montar
# a fonte depois do start: o canal já subiu sem microfone
cat > "$PECA" <<'EOF'
enum WhatsAppPeca {
    @MainActor static func ligar() -> PluginServico {
        WhatsAppStore.shared.start()
        WhatsAppStore.shared.fonteDeMicrofone = MicrofoneDoDitado()
        return WhatsAppStore.shared
    }
}
EOF
caso "fonte depois do start" 1 "tem que vir antes de"

montar
sed -i '' '/WhatsAppStore.shared.start()/d' "$PECA"
caso "peça sem start" 1 "sem '$START'"

montar
rm "$MIC"
caso "WhatsAppMicrofone.swift ausente" 1 "Knobler/WhatsApp/WhatsAppMicrofone.swift não existe"

montar
rm "$PECA"
caso "WhatsAppPeca.swift ausente" 1 "Knobler/WhatsApp/WhatsAppPeca.swift não existe"

if [ "$AUTO" -ne 0 ]; then
  echo "FALHOU: autoteste do whatsappgravacaoligacaocheck"
  exit 1
fi

# --- checagem real -----------------------------------------------------------
verificar . || exit 1
echo "whatsappgravacaoligacaocheck ok"
