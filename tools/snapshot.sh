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
  Knobler/Updater.swift \
  Knobler/AnnotationModel.swift \
  Knobler/AnnotationController.swift \
  Knobler/AnnotationDeckView.swift \
  Knobler/ColorPicker.swift \
  Knobler/Pomodoro.swift \
  Knobler/Plugin.swift \
  Knobler/CalendarAviso.swift \
  Knobler/Ask.swift \
  Knobler/AskModels.swift \
  Knobler/AskFeature.swift \
  Knobler/AskStore.swift \
  Knobler/AgentRequestModels.swift \
  Knobler/AgentRequestStore.swift \
  Knobler/AgentRequestCard.swift \
  Knobler/MediaController.swift \
  Knobler/MediaRemoteSource.swift \
  Knobler/AudioLevelTap.swift \
  Knobler/NotchNotification.swift \
  Knobler/NotificationHistory.swift \
  Knobler/HistoryListView.swift \
  Knobler/NotchGesture.swift \
  Knobler/NotchSectionOrder.swift \
  Knobler/QuickNote.swift \
  Knobler/NotificationInterceptor.swift \
  Knobler/NotificationRules.swift \
  Knobler/RemoteAvatarLoader.swift \
  Knobler/WebhookKeychainStore.swift \
  Knobler/WebhookClient.swift \
  Knobler/WebhookSettingsView.swift \
  Knobler/MappingEditorView.swift \
  Knobler/WebhookTemplate.swift \
  Knobler/WebhookExemplo.swift \
  Knobler/WebhookPresets.swift \
  Knobler/WebhookAutoMap.swift \
  Knobler/WebhookAssistant.swift \
  Knobler/WebhookAssistantView.swift \
  Knobler/AppSettings.swift \
  Knobler/Permissions.swift \
  Knobler/SettingsView.swift \
  Knobler/IdentitySettingsView.swift \
  Knobler/Reminders.swift \
  Knobler/RemindersView.swift \
  Knobler/Descanso.swift \
  Knobler/DescansoView.swift \
  Knobler/Shelf.swift \
  Knobler/ShelfPreview.swift \
  Knobler/ShelfDrop.swift \
  Knobler/LinkBrowser.swift \
  Knobler/LinkPreview.swift \
  Knobler/LinkPreviewView.swift \
  Knobler/ShelfPreviewView.swift \
  Knobler/ImageConverter.swift \
  Knobler/DocumentConverter.swift \
  Knobler/VideoConverter.swift \
  Knobler/FileConverter.swift \
  Knobler/Sharing.swift \
  Knobler/ShelfThumbnailDragView.swift \
  Knobler/Mirror.swift \
  Knobler/Peer.swift \
  Knobler/Wire.swift \
  Knobler/LANMessaging.swift \
  Knobler/MessageStore.swift \
  Knobler/MessageMedia.swift \
  Knobler/MessagesView.swift \
  Knobler/IncomingMessageView.swift \
  tools/main.swift
./build/snapshot Snapshots
