#!/usr/bin/env bash
# Gate da etapa 14 do WhatsApp: o desconto do uso próprio do microfone ligado
# nos arquivos que só o app compila.
#
# O ./tools/check.sh não compila o app (Dictation.swift importa FluidAudio e
# KnoblerApp.swift só compila com o app); o whatsappmicrofonecheck prova a
# regra pura, não que o MicRecorder marca o uso nem que o AppDelegate o entrega
# à regra. Confere:
#   - Knobler/Dictation.swift tem `UsoProprioDoMicrofone.shared.comecou()` e
#     `UsoProprioDoMicrofone.shared.terminou()`, cada um EXATAMENTE uma vez
#     (ditado e gravação do WhatsApp reusam o mesmo MicRecorder), e o
#     `comecou()` vem numa linha DEPOIS de `try engine.start()` (só conta uso
#     quando o microfone abriu de fato);
#   - Knobler/KnoblerApp.swift tem
#     `proprioAtivo: UsoProprioDoMicrofone.shared.ativo` e
#     `proprioTerminouEm: UsoProprioDoMicrofone.shared.terminouEm`;
#   - docs/notifications.md não tem mais "O ditado do próprio Knobler também
#     acende o microfone, mas dura menos que o limiar." (com qualquer quebra de
#     linha no meio da frase).
# Linha de comentário (`//`) não conta como ligação.
# Cada falta imprime `FALHOU: <o quê>` e o gate sai 1. Antes da checagem real,
# um autoteste num repo falso prova que a verificação reprova.
#
# Uso: bash tools/whatsappmicrofoneligacaocheck.sh
set -uo pipefail
cd "$(dirname "$0")/.."

COMECOU='UsoProprioDoMicrofone.shared.comecou()'
TERMINOU='UsoProprioDoMicrofone.shared.terminou()'
ENGINE='try engine.start()'
ATIVO='proprioAtivo: UsoProprioDoMicrofone.shared.ativo'
FIM='proprioTerminouEm: UsoProprioDoMicrofone.shared.terminouEm'
ANTIGO='O ditado do próprio Knobler também acende o microfone, mas dura menos que o limiar.'

# linhas_codigo <arquivo> <texto fixo>: "número:conteúdo" de cada linha de
# código (não comentário) que contém o texto.
linhas_codigo() {
  grep -nF -- "$2" "$1" 2>/dev/null | grep -vE '^[0-9]+:[[:space:]]*//'
}

# contar <arquivo> <texto fixo>: quantas linhas de código têm o texto.
contar() { linhas_codigo "$1" "$2" | grep -c . ; }

# linha <arquivo> <texto fixo>: número da primeira linha de código com o texto.
linha() { linhas_codigo "$1" "$2" | head -1 | cut -d: -f1; }

tem() { [ -n "$(linha "$1" "$2")" ]; }

# texto_corrido <arquivo>: o arquivo numa linha só, espaços em branco juntados.
texto_corrido() { tr '\n\t' '  ' < "$1" | tr -s ' '; }

# verificar <raiz>
verificar() {
  local r="$1" erro=0
  local dit="$r/Knobler/Dictation.swift"
  local app="$r/Knobler/KnoblerApp.swift"
  local doc="$r/docs/notifications.md"
  local f n e c

  for f in "$dit" "$app" "$doc"; do
    if [ ! -f "$f" ]; then
      echo "FALHOU: ${f#"$r"/} não existe"
      erro=1
    fi
  done

  if [ -f "$dit" ]; then
    for f in "$COMECOU" "$TERMINOU"; do
      n=$(contar "$dit" "$f")
      if [ "$n" != 1 ]; then
        echo "FALHOU: Knobler/Dictation.swift tem '$f' $n vez(es), esperado exatamente 1"
        erro=1
      fi
    done
    e=$(linha "$dit" "$ENGINE")
    c=$(linha "$dit" "$COMECOU")
    if [ -z "$e" ]; then
      echo "FALHOU: Knobler/Dictation.swift sem '$ENGINE'"
      erro=1
    elif [ -n "$c" ] && [ "$c" -le "$e" ]; then
      echo "FALHOU: '$COMECOU' (linha $c) tem que vir depois de '$ENGINE' (linha $e)"
      erro=1
    fi
  fi

  if [ -f "$app" ]; then
    for f in "$ATIVO" "$FIM"; do
      if ! tem "$app" "$f"; then
        echo "FALHOU: Knobler/KnoblerApp.swift sem '$f'"
        erro=1
      fi
    done
  fi

  if [ -f "$doc" ] && texto_corrido "$doc" | grep -qF -- "$ANTIGO"; then
    echo "FALHOU: docs/notifications.md ainda diz '$ANTIGO'"
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
  mkdir -p "$T/r/Knobler" "$T/r/docs"
  cat > "$T/r/Knobler/Dictation.swift" <<'EOF'
final class MicRecorder {
    private var marcouUso = false

    func start() throws {
        engine.prepare()
        do {
            try engine.start()
        } catch {
            cleanup()
            throw error
        }
        UsoProprioDoMicrofone.shared.comecou()
        marcouUso = true
    }

    func stop() -> [Float] {
        cleanup()
        if marcouUso {
            UsoProprioDoMicrofone.shared.terminou()
            marcouUso = false
        }
        return []
    }
}
EOF
  cat > "$T/r/Knobler/KnoblerApp.swift" <<'EOF'
    /// Silêncio em curso. O uso do próprio Knobler (ditado, gravação de áudio)
    /// é descontado.
    private var silenciando: Bool {
        let settings = AppSettings.shared
        return settings.silenciarEmChamadas
            && NotificationRules.micIndicaChamada(
                desde: micDesde, agora: Date(),
                proprioAtivo: UsoProprioDoMicrofone.shared.ativo,
                proprioTerminouEm: UsoProprioDoMicrofone.shared.terminouEm)
    }
EOF
  cat > "$T/r/docs/notifications.md" <<'EOF'
"Chamada" é qualquer app usando o **microfone** há mais de 20 s. Os 20 s
existem porque testar o microfone acende ele por segundos. O uso do próprio
Knobler (ditado e gravação de áudio no notch) não conta.
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

DIT="$T/r/Knobler/Dictation.swift"
APP="$T/r/Knobler/KnoblerApp.swift"
DOC="$T/r/docs/notifications.md"

montar
caso "ligação certa" 0 ""

montar
# comentário citando as chamadas não conta como segunda ocorrência
sed -i '' 's|^    func stop() -> \[Float\] {|    // marca com UsoProprioDoMicrofone.shared.comecou() e UsoProprioDoMicrofone.shared.terminou()\
    func stop() -> [Float] {|' "$DIT"
caso "comentário citando as chamadas" 0 ""

montar
sed -i '' '/UsoProprioDoMicrofone.shared.comecou()/d' "$DIT"
caso "comecou ausente" 1 "'$COMECOU' 0 vez(es)"

montar
sed -i '' '/UsoProprioDoMicrofone.shared.terminou()/d' "$DIT"
caso "terminou ausente" 1 "'$TERMINOU' 0 vez(es)"

montar
sed -i '' 's|^        UsoProprioDoMicrofone.shared.comecou()|        // UsoProprioDoMicrofone.shared.comecou()|' "$DIT"
caso "comecou só em comentário" 1 "'$COMECOU' 0 vez(es)"

montar
# marcar em dois lugares (ditado e gravação do WhatsApp em separado)
sed -i '' 's|^        marcouUso = true|        marcouUso = true\
        UsoProprioDoMicrofone.shared.comecou()|' "$DIT"
caso "comecou duas vezes" 1 "'$COMECOU' 2 vez(es)"

montar
sed -i '' 's|^            marcouUso = false|            marcouUso = false\
            UsoProprioDoMicrofone.shared.terminou()|' "$DIT"
caso "terminou duas vezes" 1 "'$TERMINOU' 2 vez(es)"

montar
# marcar antes do engine abrir: se o start() falhar, o uso fica preso
cat > "$DIT" <<'EOF'
final class MicRecorder {
    private var marcouUso = false

    func start() throws {
        engine.prepare()
        UsoProprioDoMicrofone.shared.comecou()
        marcouUso = true
        do {
            try engine.start()
        } catch {
            cleanup()
            throw error
        }
    }

    func stop() -> [Float] {
        cleanup()
        if marcouUso { UsoProprioDoMicrofone.shared.terminou(); marcouUso = false }
        return []
    }
}
EOF
caso "comecou antes do engine.start" 1 "tem que vir depois de '$ENGINE'"

montar
sed -i '' 's|            try engine.start()|            try engine.start(); UsoProprioDoMicrofone.shared.comecou()|' "$DIT"
sed -i '' '/^        UsoProprioDoMicrofone.shared.comecou()$/d' "$DIT"
caso "comecou na mesma linha do engine.start" 1 "tem que vir depois de '$ENGINE'"

montar
sed -i '' '/try engine.start()/d' "$DIT"
caso "engine.start ausente" 1 "sem '$ENGINE'"

montar
rm "$DIT"
caso "Dictation ausente" 1 "Knobler/Dictation.swift não existe"

montar
sed -i '' '/proprioAtivo: UsoProprioDoMicrofone.shared.ativo/d' "$APP"
caso "AppDelegate sem proprioAtivo" 1 "sem '$ATIVO'"

montar
sed -i '' 's|proprioTerminouEm: UsoProprioDoMicrofone.shared.terminouEm)|proprioTerminouEm: nil)|' "$APP"
caso "AppDelegate sem proprioTerminouEm" 1 "sem '$FIM'"

montar
sed -i '' 's|proprioAtivo: UsoProprioDoMicrofone.shared.ativo|proprioAtivo: false|' "$APP"
caso "AppDelegate com proprioAtivo fixo" 1 "sem '$ATIVO'"

montar
sed -i '' 's|^                proprioAtivo:|                // proprioAtivo:|' "$APP"
caso "proprioAtivo só em comentário" 1 "sem '$ATIVO'"

montar
rm "$APP"
caso "KnoblerApp ausente" 1 "Knobler/KnoblerApp.swift não existe"

montar
cat >> "$DOC" <<'EOF'
O ditado do próprio Knobler também acende o microfone, mas dura menos que o limiar.
EOF
caso "doc com a frase antiga numa linha" 1 "ainda diz"

montar
# a frase antiga como está hoje no repo: quebrada em duas linhas
cat >> "$DOC" <<'EOF'
disso engoliria card à toa. O ditado do próprio Knobler também acende o
microfone, mas dura menos que o limiar.
EOF
caso "doc com a frase antiga quebrada" 1 "ainda diz"

montar
rm "$DOC"
caso "doc ausente" 1 "docs/notifications.md não existe"

if [ "$AUTO" -ne 0 ]; then
  echo "FALHOU: autoteste do whatsappmicrofoneligacaocheck"
  exit 1
fi

# --- checagem real -----------------------------------------------------------
verificar . || exit 1
echo "whatsappmicrofoneligacaocheck ok"
