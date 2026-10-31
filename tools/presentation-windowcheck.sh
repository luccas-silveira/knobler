#!/bin/bash
# Painéis sintéticos visíveis e capturas do compositor. Requer permissão de captura de tela.
set -euo pipefail
cd "$(dirname "$0")/.."
FONTES=$(sed '/^#/d' tools/notchview-fontes.txt)
# `-F` das privadas só no linker (ver tools/snapshot.sh).
xcrun swiftc -parse-as-library -swift-version 5 $FONTES -import-objc-header Vendor/MonitorControl/MonitorControl.h \
  -Xlinker -F/System/Library/PrivateFrameworks -framework DisplayServices -framework CoreDisplay \
  Knobler/NotchWindow.swift \
  tools/presentation-windowcheck.swift -o /tmp/presentation-windowcheck
/tmp/presentation-windowcheck
