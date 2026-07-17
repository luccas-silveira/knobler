#!/bin/bash
# Compila e renderiza os snapshots da NotchView em Snapshots/*.png
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build Snapshots
swiftc -O -o build/snapshot \
  Knobler/NotchShape.swift \
  Knobler/NotchView.swift \
  Knobler/NotchViewModel.swift \
  Knobler/MediaController.swift \
  Knobler/AudioLevelTap.swift \
  Knobler/NotificationInterceptor.swift \
  Knobler/AppSettings.swift \
  Knobler/Shelf.swift \
  Knobler/Mirror.swift \
  tools/main.swift
./build/snapshot Snapshots
