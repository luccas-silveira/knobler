#!/bin/bash
# Coleta sob demanda; não instala nem reinicia o Knobler.
set -euo pipefail
cd "$(dirname "$0")/.."
trabalho=$(mktemp -d "${TMPDIR:-/tmp/}knobler-coletor.XXXXXX")
trap 'rm -rf "$trabalho"' EXIT
xcrun swiftc -parse-as-library -module-cache-path "$trabalho/cache" \
    tools/diagnostico-visual.swift -o "$trabalho/coletor"
"$trabalho/coletor"
