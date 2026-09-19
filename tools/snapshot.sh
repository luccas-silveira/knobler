#!/bin/bash
# Compila e renderiza os snapshots da NotchView em Snapshots/*.png
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build Snapshots
FONTES=$(grep -v '^#' tools/notchview-fontes.txt)
# shellcheck disable=SC2086
swiftc -O -o build/snapshot $FONTES Knobler/NotchWindow.swift tools/main.swift
./build/snapshot Snapshots
