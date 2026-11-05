#!/usr/bin/env bash
# Gate da etapa 3 do WhatsApp: exceção de ATS só para 127.0.0.1.
#
# A ponte fala em http://127.0.0.1 (docs/whatsapp-ponte.md:17-18). No macOS 14+
# o ATS recusa IP sem exceção (URLError -1022), e o cliente cairia em "ponte
# fora" para sempre. O teste do cliente roda sem Info.plist e não vê isso;
# quem prova é este gate:
#   - Knobler/Info.plist tem NSAppTransportSecurity › NSExceptionDomains ›
#     127.0.0.1 › NSExceptionAllowsInsecureHTTPLoads == true;
#   - não tem NSAllowsArbitraryLoads nem NSAllowsLocalNetworking (a exceção é
#     só desse IP);
#   - project.yml tem o mesmo bloco em info.properties (senão o próximo
#     `xcodegen generate` apaga a exceção do Info.plist).
# Cada falta imprime `FALHOU: <o quê>` e o gate sai 1. Antes da checagem real,
# um autoteste em pasta temporária prova que a verificação reprova.
#
# Uso: bash tools/whatsappatscheck.sh
set -uo pipefail
cd "$(dirname "$0")/.."

PB=/usr/libexec/PlistBuddy

# verificar <Info.plist> <project.yml>
verificar() {
  local plist="$1" yml="$2" erro=0 v chave

  # PlistBuddy separa por `:`, então o ponto do IP não atrapalha
  # (`plutil -extract` separaria por `.`).
  v=$("$PB" -c 'Print :NSAppTransportSecurity:NSExceptionDomains:127.0.0.1:NSExceptionAllowsInsecureHTTPLoads' \
    "$plist" 2>/dev/null)
  if [ "$v" != "true" ]; then
    echo "FALHOU: $plist sem NSAppTransportSecurity › NSExceptionDomains › 127.0.0.1 › NSExceptionAllowsInsecureHTTPLoads = true (achei: '${v}')"
    erro=1
  fi
  for chave in NSAllowsArbitraryLoads NSAllowsLocalNetworking; do
    if "$PB" -c "Print :NSAppTransportSecurity:$chave" "$plist" >/dev/null 2>&1; then
      echo "FALHOU: $plist tem NSAppTransportSecurity › $chave (a exceção tem que ser só de 127.0.0.1)"
      erro=1
    fi
    if grep -qE "^[[:space:]]*$chave[[:space:]]*:" "$yml"; then
      echo "FALHOU: $yml tem $chave (a exceção tem que ser só de 127.0.0.1)"
      erro=1
    fi
  done

  # o bloco do project.yml, na ordem, cada chave aninhada abaixo da anterior
  if ! awk '
    function ind(s) { match(s, /^[ ]*/); return RLENGTH }
    /^[[:space:]]*#/ { next }
    passo == 0 && /^[ ]*NSAppTransportSecurity:[ ]*$/ { i0 = ind($0); passo = 1; next }
    passo == 1 && /^[ ]*NSExceptionDomains:[ ]*$/ && ind($0) > i0 { i1 = ind($0); passo = 2; next }
    passo == 2 && /^[ ]*"?127\.0\.0\.1"?:[ ]*$/ && ind($0) > i1 { i2 = ind($0); passo = 3; next }
    passo == 3 && /^[ ]*NSExceptionAllowsInsecureHTTPLoads:[ ]*true[ ]*$/ && ind($0) > i2 { passo = 4 }
    END { exit (passo == 4 ? 0 : 1) }' "$yml"; then
    echo "FALHOU: $yml sem o bloco NSAppTransportSecurity › NSExceptionDomains › 127.0.0.1 › NSExceptionAllowsInsecureHTTPLoads: true"
    erro=1
  fi
  if ! grep -qF 'NSExceptionAllowsInsecureHTTPLoads: true' "$yml"; then
    echo "FALHOU: $yml sem 'NSExceptionAllowsInsecureHTTPLoads: true'"
    erro=1
  fi
  if ! grep -qF '127.0.0.1:' "$yml"; then
    echo "FALHOU: $yml sem a chave '127.0.0.1:'"
    erro=1
  fi
  return "$erro"
}

# --- autoteste ---------------------------------------------------------------
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT

AUTO=0
# caso <nome> <código esperado> <texto esperado ou vazio> — usa $T/Info.plist e $T/project.yml
caso() {
  local nome="$1" esperado="$2" texto="$3" saida codigo
  saida=$(verificar "$T/Info.plist" "$T/project.yml" 2>&1); codigo=$?
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
plist_bom() {
  rm -f "$T/Info.plist"
  "$PB" -c 'Add :CFBundleName string Knobler' \
        -c 'Add :NSAppTransportSecurity dict' \
        -c 'Add :NSAppTransportSecurity:NSExceptionDomains dict' \
        -c 'Add :NSAppTransportSecurity:NSExceptionDomains:127.0.0.1 dict' \
        -c 'Add :NSAppTransportSecurity:NSExceptionDomains:127.0.0.1:NSExceptionAllowsInsecureHTTPLoads bool true' \
        "$T/Info.plist" >/dev/null
}
YML_BOM='targets:
  Knobler:
    info:
      path: Knobler/Info.plist
      properties:
        LSUIElement: true
        # A ponte do WhatsApp fala em http://127.0.0.1 (loopback).
        NSAppTransportSecurity:
          NSExceptionDomains:
            127.0.0.1:
              NSExceptionAllowsInsecureHTTPLoads: true
        CFBundleIconFile: AppIcon'

plist_bom; printf '%s\n' "$YML_BOM" > "$T/project.yml"
caso "(a) tudo certo" 0 ''

rm -f "$T/Info.plist"; "$PB" -c 'Add :CFBundleName string Knobler' "$T/Info.plist" >/dev/null
caso "(b) Info.plist sem exceção" 1 'FALHOU: '"$T"'/Info.plist sem NSAppTransportSecurity'

plist_bom; "$PB" -c 'Set :NSAppTransportSecurity:NSExceptionDomains:127.0.0.1:NSExceptionAllowsInsecureHTTPLoads false' "$T/Info.plist"
caso "(c) exceção = false" 1 'NSExceptionAllowsInsecureHTTPLoads = true'

plist_bom; "$PB" -c 'Add :NSAppTransportSecurity:NSAllowsArbitraryLoads bool true' "$T/Info.plist"
caso "(d) NSAllowsArbitraryLoads" 1 'tem NSAppTransportSecurity › NSAllowsArbitraryLoads'

plist_bom; "$PB" -c 'Add :NSAppTransportSecurity:NSAllowsLocalNetworking bool true' "$T/Info.plist"
caso "(e) NSAllowsLocalNetworking" 1 'tem NSAppTransportSecurity › NSAllowsLocalNetworking'

plist_bom; rm -f "$T/Info.plist"; "$PB" -c 'Add :NSAppTransportSecurity dict' \
  -c 'Add :NSAppTransportSecurity:NSExceptionDomains dict' \
  -c 'Add :NSAppTransportSecurity:NSExceptionDomains:localhost dict' \
  -c 'Add :NSAppTransportSecurity:NSExceptionDomains:localhost:NSExceptionAllowsInsecureHTTPLoads bool true' \
  "$T/Info.plist" >/dev/null
caso "(f) exceção de outro domínio" 1 'sem NSAppTransportSecurity'

plist_bom; printf '%s\n' 'targets:
  Knobler:
    info:
      properties:
        LSUIElement: true' > "$T/project.yml"
caso "(g) project.yml sem o bloco" 1 'project.yml sem o bloco'

printf '%s\n' "$YML_BOM" \
  | awk '{ print } /^        NSAppTransportSecurity:$/ { print "          NSAllowsArbitraryLoads: true" }' \
  > "$T/project.yml"
caso "(h) project.yml com NSAllowsArbitraryLoads" 1 'project.yml tem NSAllowsArbitraryLoads'

printf '%s\n' "$YML_BOM" | sed 's/NSExceptionAllowsInsecureHTTPLoads: true/NSExceptionAllowsInsecureHTTPLoads: false/' > "$T/project.yml"
caso "(i) project.yml com false" 1 'project.yml sem o bloco'

# chaves soltas, fora do aninhamento: grep acharia, o bloco não
printf '%s\n' 'targets:
  Knobler:
    info:
      properties:
        NSAppTransportSecurity: {}
        # 127.0.0.1: comentado
        outro:
          127.0.0.1:
        NSExceptionAllowsInsecureHTTPLoads: true' > "$T/project.yml"
caso "(j) project.yml com chaves fora do bloco" 1 'project.yml sem o bloco'

if [ "$AUTO" -ne 0 ]; then
  echo "FALHOU: o autoteste do whatsappatscheck não reprovou o que devia"
  exit 1
fi

# --- checagem real -----------------------------------------------------------
verificar Knobler/Info.plist project.yml || exit 1
echo "ok"
