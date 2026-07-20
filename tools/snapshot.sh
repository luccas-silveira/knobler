#!/bin/bash
# Compila e renderiza os snapshots da NotchView em Snapshots/*.png
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build Snapshots
swiftc -O -o build/snapshot \
  Knobler/NotchShape.swift \
  Knobler/NotchView.swift \
  Knobler/NotchViewModel.swift \
  Knobler/AirPodsBattery.swift \
  Knobler/Pomodoro.swift \
  Knobler/Ask.swift \
  Knobler/MediaController.swift \
  Knobler/AudioLevelTap.swift \
  Knobler/NotificationInterceptor.swift \
  Knobler/AppSettings.swift \
  Knobler/Reminders.swift \
  Knobler/RemindersView.swift \
  Knobler/Descanso.swift \
  Knobler/DescansoView.swift \
  Knobler/Shelf.swift \
  Knobler/ShelfThumbnailDragView.swift \
  Knobler/Mirror.swift \
  tools/main.swift
./build/snapshot Snapshots
