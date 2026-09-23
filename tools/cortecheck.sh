#!/bin/bash
# Compila e roda o harness de transição da NotchView (tools/cortecheck/main.swift).
# Mede, por quadro, se a moldura desenhada cobre o conteúdo desenhado.
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build
FONTES=$(grep -v '^#' tools/notchview-fontes.txt)
# NotchWindow não é fonte da NotchView (por isso fica FORA de
# notchview-fontes.txt, que o snapshot.sh também lê): entra só aqui, porque a
# medição 004 dirige `applyVisibility` contra o painel de verdade — nível
# `.mainMenu + 3`, `isOpaque = false`, `.canJoinAllSpaces` —, e não contra uma
# NSWindow comum.
# shellcheck disable=SC2086
swiftc -O -o build/cortecheck $FONTES -import-objc-header Vendor/MonitorControl/MonitorControl.h \
  -F/System/Library/PrivateFrameworks -framework DisplayServices -framework CoreDisplay \
  Knobler/NotchWindow.swift tools/cortecheck/main.swift
./build/cortecheck
