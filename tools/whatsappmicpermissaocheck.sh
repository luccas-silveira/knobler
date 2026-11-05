#!/usr/bin/env bash
# Gate da etapa 15 do WhatsApp: o texto de permissão do microfone fala de
# ditado e de gravação de áudio, em termos genéricos (sem citar o WhatsApp).
#
# Confere o que o usuário lê:
#   - project.yml e Knobler/Info.plist têm UM NSMicrophoneUsageDescription
#     cada, igual a $SISTEMA (o do Info.plist lido pelo plutil, como o sistema
#     lê; o do project.yml pela linha da chave, aspas YAML opcionais);
#   - o texto antigo ($ANTIGO) não aparece em nenhum dos dois arquivos;
#   - Permission.microfone.why (Knobler/Permissions.swift compilado de verdade,
#     não grep) é igual a $PAINEL;
#   - nenhum dos três textos contém "WhatsApp" (A11/A41).
# O permissioncheck (mais acima no check.sh) segue provando o resto do arquivo.
# Cada falta imprime `FALHOU: <o quê>` e o gate sai 1. Antes da checagem real,
# um autoteste num repo falso prova que a verificação reprova.
#
# Uso: bash tools/whatsappmicpermissaocheck.sh
set -uo pipefail
cd "$(dirname "$0")/.."

SISTEMA='Knobler grava sua voz no ditado, para transcrever onde o cursor estiver, e nas mensagens de áudio que você grava no notch.'
PAINEL='Grava sua voz no ditado (segurando a ⌥ direita) e nas mensagens de áudio que você grava no notch.'
ANTIGO='enquanto você segura a tecla de ditado'
CHAVE='NSMicrophoneUsageDescription'

T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
mkdir -p "$T/cache"

# why_microfone <Permissions.swift>: imprime Permission.microfone.why do
# arquivo compilado; sai 1 se não compila. Binário em cache pelo hash do
# arquivo (o autoteste reusa o mesmo Permissions.swift em vários casos).
why_microfone() {
  local src="$1" h bin
  h=$(shasum "$src" | cut -d' ' -f1)
  bin="$T/cache/$h"
  if [ ! -x "$bin" ]; then
    mkdir -p "$T/cache/$h.d"
    cat > "$T/cache/$h.d/harness.swift" <<'EOF'
@main
enum WhyMicrofone {
    static func main() { print(Permission.microfone.why, terminator: "") }
}
EOF
    if ! xcrun swiftc -parse-as-library -swift-version 5 \
        "$src" "$T/cache/$h.d/harness.swift" -o "$bin" > "$T/cache/$h.log" 2>&1; then
      sed 's/^/    | /' "$T/cache/$h.log"
      return 1
    fi
  fi
  "$bin"
}

# valor_yml <project.yml>: valor da chave, sem indentação nem aspas YAML.
valor_yml() {
  grep -F "$CHAVE:" "$1" | head -1 \
    | sed -E "s/^[[:space:]]*$CHAVE:[[:space:]]*//; s/[[:space:]]+\$//" \
    | sed -E "s/^\"(.*)\"\$/\\1/; s/^'(.*)'\$/\\1/"
}

# verificar <raiz>
verificar() {
  local r="$1" erro=0
  local yml="$r/project.yml" plist="$r/Knobler/Info.plist" perm="$r/Knobler/Permissions.swift"
  local f n v

  for f in "$yml" "$plist" "$perm"; do
    if [ ! -f "$f" ]; then
      echo "FALHOU: ${f#"$r"/} não existe"
      erro=1
    fi
  done

  if [ -f "$yml" ]; then
    n=$(grep -cF "$CHAVE:" "$yml")
    if [ "$n" != 1 ]; then
      echo "FALHOU: project.yml tem $CHAVE $n vez(es), esperado exatamente 1"
      erro=1
    fi
    v=$(valor_yml "$yml")
    if [ "$v" != "$SISTEMA" ]; then
      echo "FALHOU: $CHAVE do project.yml é '$v', esperado '$SISTEMA'"
      erro=1
    fi
    if printf '%s' "$v" | grep -qi whatsapp; then
      echo "FALHOU: $CHAVE do project.yml cita WhatsApp: '$v'"
      erro=1
    fi
    if grep -qF -- "$ANTIGO" "$yml"; then
      echo "FALHOU: project.yml ainda tem o texto antigo '$ANTIGO'"
      erro=1
    fi
  fi

  if [ -f "$plist" ]; then
    n=$(grep -cF "<key>$CHAVE</key>" "$plist")
    if [ "$n" != 1 ]; then
      echo "FALHOU: Knobler/Info.plist tem $CHAVE $n vez(es), esperado exatamente 1"
      erro=1
    fi
    if ! v=$(plutil -extract "$CHAVE" raw -o - "$plist" 2>&1); then
      echo "FALHOU: Knobler/Info.plist não dá $CHAVE pelo plutil: $v"
      erro=1
      v=""
    fi
    if [ "$v" != "$SISTEMA" ]; then
      echo "FALHOU: $CHAVE do Knobler/Info.plist é '$v', esperado '$SISTEMA' (o mesmo do project.yml)"
      erro=1
    fi
    if grep -A1 -F "$CHAVE" "$plist" | grep -qi whatsapp; then
      echo "FALHOU: $CHAVE do Knobler/Info.plist cita WhatsApp"
      erro=1
    fi
    if grep -qF -- "$ANTIGO" "$plist"; then
      echo "FALHOU: Knobler/Info.plist ainda tem o texto antigo '$ANTIGO'"
      erro=1
    fi
  fi

  if [ -f "$perm" ]; then
    if ! v=$(why_microfone "$perm"); then
      printf '%s\n' "$v"
      echo "FALHOU: Knobler/Permissions.swift não compila sozinho para ler Permission.microfone.why"
      erro=1
    else
      if [ "$v" != "$PAINEL" ]; then
        echo "FALHOU: Permission.microfone.why é '$v', esperado '$PAINEL'"
        erro=1
      fi
      if printf '%s' "$v" | grep -qi whatsapp; then
        echo "FALHOU: Permission.microfone.why cita WhatsApp: '$v'"
        erro=1
      fi
    fi
  fi

  return "$erro"
}

# --- autoteste ---------------------------------------------------------------
# repo falso com os textos certos; cada caso estraga uma coisa
montar() {
  rm -rf "$T/r"
  mkdir -p "$T/r/Knobler"
  cat > "$T/r/project.yml" <<EOF
targets:
  Knobler:
    info:
      path: Knobler/Info.plist
      properties:
        LSUIElement: true
        $CHAVE: $SISTEMA
        NSCameraUsageDescription: Knobler mostra o espelho da câmera no notch.
EOF
  cat > "$T/r/Knobler/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>LSUIElement</key>
	<true/>
	<key>$CHAVE</key>
	<string>$SISTEMA</string>
	<key>NSCameraUsageDescription</key>
	<string>Knobler mostra o espelho da câmera no notch.</string>
</dict>
</plist>
EOF
  cat > "$T/r/Knobler/Permissions.swift" <<EOF
enum Permission {
    case microfone, camera
    var why: String {
        switch self {
        case .microfone:
            return "$PAINEL"
        case .camera:
            return "Mostra o espelho no notch antes de reuniões."
        }
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

YML="$T/r/project.yml"
PLIST="$T/r/Knobler/Info.plist"
PERM="$T/r/Knobler/Permissions.swift"
VELHO_SIS='Knobler grava sua voz enquanto você segura a tecla de ditado, para transcrever onde o cursor estiver.'
VELHO_PAINEL='Grava sua voz enquanto você segura a ⌥ direita.'

# troca <arquivo> <de> <para>: troca literal (sem regex), primeira ocorrência
troca() {
  DE="$2" PARA="$3" perl -0pi -e 's/\Q$ENV{DE}\E/$ENV{PARA}/' "$1"
}

montar
caso "textos certos" 0 ""

montar
troca "$YML" "$CHAVE: $SISTEMA" "$CHAVE: \"$SISTEMA\""
caso "project.yml com aspas YAML" 0 ""

montar
troca "$YML" "$SISTEMA" "$VELHO_SIS"
caso "project.yml com o texto antigo" 1 "project.yml ainda tem o texto antigo"

montar
troca "$PLIST" "$SISTEMA" "$VELHO_SIS"
caso "Info.plist esquecido (só o project.yml mudou)" 1 "Knobler/Info.plist ainda tem o texto antigo"

montar
troca "$YML" "$SISTEMA" "Knobler grava sua voz no ditado e nas mensagens de áudio do WhatsApp que você grava no notch."
caso "project.yml citando o WhatsApp" 1 "do project.yml cita WhatsApp"

montar
troca "$PLIST" "$SISTEMA" "$SISTEMA (inclusive no WhatsApp)"
caso "Info.plist citando o WhatsApp" 1 "do Knobler/Info.plist cita WhatsApp"

montar
troca "$PLIST" "$SISTEMA" "Knobler grava sua voz no ditado e nas mensagens de áudio."
caso "Info.plist diferente do project.yml" 1 "do Knobler/Info.plist é"

montar
# texto antigo escondido numa segunda chave/linha também conta
troca "$YML" "        NSCameraUsageDescription" "        # era: $VELHO_SIS
        NSCameraUsageDescription"
caso "texto antigo num comentário do project.yml" 1 "project.yml ainda tem o texto antigo"

montar
troca "$PLIST" "<string>$SISTEMA</string>" "<string>$SISTEMA</string>
	<key>$CHAVE</key>
	<string>$SISTEMA</string>"
caso "chave duplicada no Info.plist" 1 "esperado exatamente 1"

montar
troca "$PERM" "$PAINEL" "$VELHO_PAINEL"
caso "painel com o texto antigo" 1 "Permission.microfone.why é"

montar
# texto novo no case errado: grep acharia, o valor de .microfone não
troca "$PERM" "Mostra o espelho no notch antes de reuniões." "$PAINEL"
troca "$PERM" "$PAINEL" "$VELHO_PAINEL"
caso "texto do painel no case errado" 1 "Permission.microfone.why é"

montar
troca "$PERM" "$PAINEL" "Grava sua voz no ditado (segurando a ⌥ direita) e nas mensagens de áudio do WhatsApp."
caso "painel citando o WhatsApp" 1 "Permission.microfone.why cita WhatsApp"

montar
rm "$PERM"
caso "Permissions.swift ausente" 1 "Knobler/Permissions.swift não existe"

if [ "$AUTO" != 0 ]; then
  echo "FALHOU: autoteste do whatsappmicpermissaocheck (a verificação não reprova o que devia)"
  exit 1
fi

# --- checagem real -------------------------------------------------------------
if ! verificar .; then
  exit 1
fi
echo "whatsappmicpermissaocheck: OK"
