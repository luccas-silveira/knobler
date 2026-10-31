#!/bin/bash
# Compila e renderiza os snapshots da NotchView em Snapshots/*.png
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build Snapshots
FONTES=$(grep -v '^#' tools/notchview-fontes.txt)
# `-F` das privadas só no linker: passado ao compilador, o clang acha o
# Network.framework privado antes do SDK e o módulo `Network` não compila
# (macOS 27). O MonitorControl.h declara os símbolos à mão, sem header privado.
# shellcheck disable=SC2086
swiftc -O -o build/snapshot $FONTES -import-objc-header Vendor/MonitorControl/MonitorControl.h \
  -Xlinker -F/System/Library/PrivateFrameworks -framework DisplayServices -framework CoreDisplay \
  Knobler/NotchWindow.swift tools/main.swift
./build/snapshot Snapshots
