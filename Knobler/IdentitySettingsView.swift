//
//  IdentitySettingsView.swift
//  Knobler
//
//  Aba de Ajustes: nome e foto que os outros veem nas Mensagens LAN.
//

import AppKit
import SwiftUI

struct IdentitySettingsView: View {
    @ObservedObject var settings = AppSettings.shared
    @State private var avatar: NSImage?

    var body: some View {
        Form {
            Section {
                HStack(spacing: 14) {
                    avatarThumb
                    VStack(alignment: .leading, spacing: 8) {
                        TextField("Nome de exibição", text: $settings.displayName)
                        HStack {
                            Button("Escolher foto…") { pickPhoto() }
                            Button("Usar a do macOS") { useMacOSPhoto() }
                            if avatar != nil {
                                Button("Remover") {
                                    settings.removeMyAvatar()
                                    avatar = nil
                                }
                            }
                        }
                        .controlSize(.small)
                    }
                }
                .padding(.vertical, 4)
            } header: {
                Text("Como você aparece na rede")
            } footer: {
                Text("Outros Macs com Knobler na mesma rede veem este nome e esta foto.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear { avatar = loadAvatar() }
    }

    private var avatarThumb: some View {
        Group {
            if let avatar {
                Image(nsImage: avatar).resizable().scaledToFill()
            } else {
                ZStack {
                    Circle().fill(.gray.opacity(0.3))
                    Text(initials).font(.title2.weight(.semibold)).foregroundStyle(.white)
                }
            }
        }
        .frame(width: 64, height: 64)
        .clipShape(Circle())
    }

    private var initials: String {
        String(settings.displayName.prefix(1)).uppercased()
    }

    private func loadAvatar() -> NSImage? {
        settings.myAvatarJPEG().flatMap { NSImage(data: $0) }
    }

    private func pickPhoto() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .jpeg, .heic]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url,
              let image = NSImage(contentsOf: url) else { return }
        settings.setMyAvatar(image)
        avatar = loadAvatar()
    }

    private func useMacOSPhoto() {
        guard let image = AppSettings.macOSAvatar() else { return }
        settings.setMyAvatar(image)
        avatar = loadAvatar()
    }
}
