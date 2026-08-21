#!/bin/bash
# Compila e roda o harness de transição da NotchView (tools/cortecheck/main.swift).
# Mede, por quadro, se a moldura desenhada cobre o conteúdo desenhado.
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build
FONTES=$(grep -v '^#' tools/notchview-fontes.txt)
# shellcheck disable=SC2086
swiftc -O -o build/cortecheck $FONTES tools/cortecheck/main.swift
./build/cortecheck
