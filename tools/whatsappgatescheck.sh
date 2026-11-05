#!/usr/bin/env bash
# Guarda dos gates do WhatsApp: todo tools/whatsapp*check.{swift,sh} entra no
# check.sh por swift_teste/bash_teste (nome do gate = nome do arquivo), toda
# entrada desses ajudantes aponta pra arquivo que existe, e nenhum gate do
# WhatsApp é registrado com swift_check/run (nome escrito à mão).
# Antes da checagem real, um autoteste prova que a verificação reprova.
#
# Uso: bash tools/whatsappgatescheck.sh
set -uo pipefail
cd "$(dirname "$0")/.."

# verificar <check.sh> <pasta-tools> [raiz]
# Os caminhos citados no check.sh (tools/…) são relativos à raiz.
verificar() {
  local check="$1" pasta="$2" raiz="${3:-.}"
  local erro=0 f nome ajudante ext caminho

  for ext in swift sh; do
    if [ "$ext" = swift ]; then ajudante=swift_teste; else ajudante=bash_teste; fi
    for f in "$pasta"/whatsapp*check."$ext"; do
      [ -e "$f" ] || continue
      nome="tools/$(basename "$f")"
      # a linha pode continuar com `\`; comentário não conta
      if ! grep -qE "^[[:space:]]*$ajudante[[:space:]]+${nome//./\\.}([[:space:]]|$)" "$check"; then
        echo "FALHOU: $nome sem entrada no check.sh"
        erro=1
      fi
    done
  done

  while read -r caminho; do
    [ -n "$caminho" ] || continue
    if [ ! -e "$raiz/$caminho" ]; then
      echo "FALHOU: check.sh cita $caminho, que não existe"
      erro=1
    fi
  done < <(grep -E '^[[:space:]]*(swift_teste|bash_teste)[[:space:]]+tools/' "$check" \
    | awk '{print $2}')

  while IFS= read -r linha; do
    echo "FALHOU: gate do WhatsApp fora dos ajudantes: $linha"
    erro=1
  done < <(grep -E '^[[:space:]]*(swift_check|run)[[:space:]]+whatsapp' "$check")

  return "$erro"
}

# --- autoteste ---------------------------------------------------------------
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT

AUTO=0
# caso <nome> <código esperado> <texto esperado ou vazio> -- monta $T/r antes
caso() {
  local nome="$1" esperado="$2" texto="$3" saida codigo
  saida=$(verificar "$T/r/tools/check.sh" "$T/r/tools" "$T/r" 2>&1); codigo=$?
  if [ "$codigo" != "$esperado" ]; then
    echo "autoteste ($nome): saiu com $codigo, esperado $esperado"
    printf '%s\n' "$saida" | sed 's/^/    | /'
    AUTO=1
  elif [ -n "$texto" ] && ! grep -qF -- "$texto" <<<"$saida"; then
    echo "autoteste ($nome): faltou '$texto'"
    printf '%s\n' "$saida" | sed 's/^/    | /'
    AUTO=1
  fi
}
repo() { # stdin = check.sh; argumentos = arquivos a criar em tools/
  rm -rf "$T/r"; mkdir -p "$T/r/tools"
  cat > "$T/r/tools/check.sh"
  local a; for a in "$@"; do touch "$T/r/tools/$a"; done
}

repo whatsappzzcheck.swift <<<'# nada'
caso "(a) .swift sem entrada" 1 'FALHOU: tools/whatsappzzcheck.swift sem entrada no check.sh'
repo whatsappzzcheck.swift <<<'swift_teste tools/whatsappzzcheck.swift'
caso "(b) .swift com swift_teste" 0 ''
repo <<<'swift_teste tools/whatsappsumiucheck.swift'
caso "(c) entrada sem arquivo" 1 'FALHOU: check.sh cita tools/whatsappsumiucheck.swift, que não existe'
repo whatsappzzcheck.swift <<<$'swift_teste tools/whatsappzzcheck.swift\nswift_check whatsappzzcheck tools/whatsappzzcheck.swift'
caso "(d) swift_check" 1 'FALHOU: gate do WhatsApp fora dos ajudantes'
repo whatsappzzcheck.sh <<<'# nada'
caso "(e) .sh sem entrada" 1 'FALHOU: tools/whatsappzzcheck.sh sem entrada no check.sh'
repo whatsappzzcheck.sh <<<'bash_teste tools/whatsappzzcheck.sh'
caso "(e) .sh com bash_teste" 0 ''

if [ "$AUTO" != 0 ]; then
  echo "FALHOU: autoteste do whatsappgatescheck"
  exit 1
fi

# --- checagem real -----------------------------------------------------------
verificar tools/check.sh tools .
