//
//  WebhookSettingsView.swift
//  Knobler
//
//  Aba "Notificações externas": master toggle + status da conexão no topo e, quando
//  ligado, a lista de perfis (ProfilesListView) — cada perfil tem seu link próprio,
//  com copiar/rotacionar/mapear/excluir por item.
//

import SwiftUI

struct WebhookSettingsView: View {
    @ObservedObject var settings = AppSettings.shared
    @ObservedObject var client: WebhookClient

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                Toggle("Receber notificações externas", isOn: $settings.webhookNotifications)
                Text("Um webhook no seu link vira um card no notch. Ligado = o app mantém uma conexão com o relay.")
                    .font(.caption).foregroundStyle(.secondary)

                if settings.webhookNotifications {
                    HStack {
                        Circle().fill(client.connected ? .green : .secondary)
                            .frame(width: 8, height: 8)
                        Text(client.connected ? "Conectado" : "Offline")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Toggle("Carregar imagens remotas", isOn: $settings.loadRemoteImages)
                    Text("Baixa o avatar da notificação. Desligue para não expor o IP do seu Mac a quem envia o webhook.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding([.horizontal, .top])

            if settings.webhookNotifications {
                Divider()
                ProfilesListView(client: client)
            } else {
                Spacer()
            }
        }
    }
}
