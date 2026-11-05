#!/usr/bin/env bash
# Typecheck de todas as fontes que o tools/snapshot.sh compila, sem renderizar
# nada (o snapshot exige sessão gráfica e fica fora do check.sh). Antes, confere
# que tools/notchview-fontes.txt só lista arquivo que existe e que toda
# Knobler/WhatsApp/*View.swift está nele.
#
# Uso: bash tools/notchfontescheck.sh
set -uo pipefail
cd "$(dirname "$0")/.."

FONTES=$(grep -v '^#' tools/notchview-fontes.txt)
erro=0
ausente=0

for f in $FONTES; do
  if [ ! -e "$f" ]; then
    echo "FALHOU: fonte listada e ausente: $f"
    erro=1; ausente=1
  fi
done

if [ -d Knobler/WhatsApp ]; then
  for v in Knobler/WhatsApp/*View.swift; do
    [ -e "$v" ] || continue
    if ! grep -qxF -- "$v" <<<"$FONTES"; then
      echo "FALHOU: view do WhatsApp fora do notchview-fontes.txt: $v"
      erro=1
    fi
  done
fi

# Com fonte faltando o swiftc só repetiria o "no such file".
[ "$ausente" = 0 ] || exit 1

# Mesmas fontes de tools/snapshot.sh, sem o -Xlinker (só vale no link).
# shellcheck disable=SC2086
if ! saida=$(xcrun swiftc -typecheck -swift-version 5 $FONTES \
  -import-objc-header Vendor/MonitorControl/MonitorControl.h \
  Knobler/NotchWindow.swift tools/main.swift 2>&1); then
  printf '%s\n' "$saida"
  echo "FALHOU: typecheck das fontes do snapshot"
  erro=1
fi

exit "$erro"
