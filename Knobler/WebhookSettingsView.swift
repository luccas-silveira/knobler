//
//  WebhookSettingsView.swift
//  Knobler
//
//  Painel "Notificações externas": master toggle + status da conexão e, quando
//  ligado, os PERFIS de webhook — cada perfil tem seu link próprio, com copiar,
//  mapear (MappingEditorView), rotacionar e excluir por item.
//

import AppKit
import SwiftUI

struct WebhookSettingsView: View {
    @ObservedObject var settings = AppSettings.shared
    @ObservedObject var client: WebhookClient
    @State private var profiles: [WebhookClient.WebhookProfile] = []
    @State private var editing: WebhookClient.WebhookProfile?
    @State private var rotating: WebhookClient.WebhookProfile?
    @State private var novoNome = ""
    @State private var loaded = false    // já teve UM fetch com sucesso
    @State private var loadSeq = 0       // descarta resposta atrasada de reload antigo

    var body: some View {
        Form {
            Section {
                SettingToggle(
                    title: "Receber notificações externas",
                    subtitle: "Um webhook no seu link vira um card no notch. Ligado, "
                        + "o app mantém uma conexão com o relay.",
                    isOn: $settings.webhookNotifications)
                if settings.webhookNotifications {
                    LabeledContent("Status") {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(client.connected ? Color.green : Color.secondary)
                                .frame(width: 8, height: 8)
                            Text(client.connected ? "Conectado" : "Offline")
                                .foregroundStyle(.secondary)
                        }
                    }
                    SettingToggle(
                        title: "Carregar imagens remotas",
                        subtitle: "Baixa o avatar da notificação. Desligue para não expor "
                            + "o IP do seu Mac a quem envia o webhook.",
                        isOn: $settings.loadRemoteImages)
                }
            }
            if settings.webhookNotifications {
                Section("Perfis") {
                    HStack {
                        TextField("Nome do novo perfil", text: $novoNome)
                            .onSubmit(adicionar)
                        Button("Adicionar", action: adicionar)
                            .disabled(novoNome.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                    if loaded && profiles.isEmpty {
                        Text("Cada perfil tem um link próprio de webhook — crie um por serviço.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    ForEach(profiles) { p in profileRow(p) }
                }
            }
        }
        .formStyle(.grouped)
        .toggleStyle(.switch)
        .task { if settings.webhookNotifications { await recarregar() } }
        .onChange(of: settings.webhookNotifications) { _, on in
            if on { Task { await recarregar() } }
        }
        .onChange(of: client.connected) { _, on in
            // reconectou → tenta de novo (um fetch que falhou offline não fica pra sempre)
            if on { Task { await recarregar() } }
        }
        .sheet(item: $editing) { p in
            MappingEditorView(client: client, profile: p,
                              onClose: { editing = nil; Task { await recarregar() } })
        }
        .confirmationDialog(
            "Gerar um link novo para este perfil? O link antigo para de funcionar.",
            isPresented: Binding(get: { rotating != nil },
                                 set: { if !$0 { rotating = nil } }),
            titleVisibility: .visible
        ) {
            Button("Gerar link novo", role: .destructive) {
                if let p = rotating {
                    Task { await client.rotateProfile(p.id); await recarregar() }
                }
                rotating = nil
            }
            Button("Cancelar", role: .cancel) { rotating = nil }
        }
    }

    private func profileRow(_ p: WebhookClient.WebhookProfile) -> some View {
        HStack(spacing: 8) {
            profileIcon(p.icon)
            VStack(alignment: .leading, spacing: 2) {
                Text(p.name)
                Text(p.hasMapping ? "Campos mapeados" : "Sem mapa — captura o payload cru")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if let link = client.link(for: p.id) {
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(link, forType: .string)
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .buttonStyle(.borderless)
                .help("Copiar o link do webhook")
            }
            Menu {
                Button("Mapear campos…") { editing = p }
                Button("Gerar link novo…") { rotating = p }
                Divider()
                Button("Apagar perfil", role: .destructive) {
                    Task { await client.deleteProfile(p.id); await recarregar() }
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .buttonStyle(.borderless)
            .menuIndicator(.hidden)
            .fixedSize()
        }
    }

    /// Emoji vira texto; ícone-URL (imagem) vira um glifo genérico — uma URL num
    /// Text de 22 pt embrulharia em coluna de 3 letras e explodiria a linha.
    @ViewBuilder private func profileIcon(_ icon: String?) -> some View {
        if let icon, !icon.isEmpty, !icon.lowercased().hasPrefix("http") {
            Text(icon).lineLimit(1).frame(width: 22)
        } else {
            Image(systemName: "bell.fill")
                .foregroundStyle(.secondary)
                .frame(width: 22)
        }
    }

    private func adicionar() {
        let nome = novoNome.trimmingCharacters(in: .whitespaces)
        guard !nome.isEmpty else { return }
        Task {
            // só limpa o campo se criou de verdade — falha não come o que foi digitado
            if await client.createProfile(name: nome) != nil { novoNome = "" }
            await recarregar()
        }
    }

    private func recarregar() async {
        loadSeq += 1
        let seq = loadSeq
        // nil = falha: preserva a lista atual; seq: last-request-wins entre reloads
        if let list = await client.listProfiles(), seq == loadSeq {
            profiles = list
            loaded = true
        }
    }
}
