//
//  WebhookSettingsView.swift
//  Knobler
//
//  Aba "Notificações externas": liga/desliga, mostra o link do device + status
//  da conexão, e permite copiar/rotacionar o link.
//

import SwiftUI

struct WebhookSettingsView: View {
    @ObservedObject var settings = AppSettings.shared
    @ObservedObject var client: WebhookClient
    @State private var confirmRotate = false

    var body: some View {
        Form {
            Section {
                Toggle("Receber notificações externas", isOn: $settings.webhookNotifications)
            } footer: {
                Text("Um webhook no seu link vira um card no notch. Ligado = o app mantém uma conexão com o relay.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            if settings.webhookNotifications {
                Section("Seu link") {
                    HStack {
                        Circle().fill(client.connected ? .green : .secondary)
                            .frame(width: 8, height: 8)
                        Text(client.connected ? "Conectado" : "Offline")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    if let link = client.link {
                        HStack {
                            Text(link).font(.caption.monospaced())
                                .textSelection(.enabled).lineLimit(1).truncationMode(.middle)
                            Spacer()
                            Button("Copiar") {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(link, forType: .string)
                            }
                        }
                    } else {
                        Text("Gerando link…").font(.caption).foregroundStyle(.secondary)
                    }
                    Button("Rotacionar link", role: .destructive) { confirmRotate = true }
                        .confirmationDialog("Gerar um link novo? O link antigo para de funcionar.",
                                            isPresented: $confirmRotate, titleVisibility: .visible) {
                            Button("Gerar link novo", role: .destructive) { client.rotate() }
                            Button("Cancelar", role: .cancel) {}
                        }
                }
                Section {
                    Toggle("Carregar imagens remotas", isOn: $settings.loadRemoteImages)
                } footer: {
                    Text("Baixa o avatar da notificação. Desligue para não expor o IP do seu Mac a quem envia o webhook.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section {
                    Text("curl -X POST \(client.link ?? "<link>") -d 'title=Oi&body=Tudo bem'")
                        .font(.caption.monospaced()).textSelection(.enabled)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
    }
}
