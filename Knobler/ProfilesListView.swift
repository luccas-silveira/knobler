//
//  ProfilesListView.swift
//  Knobler
//
//  A aba "Notificações externas" lista os PERFIS de webhook: cada perfil tem seu
//  próprio link público. Aqui dá pra adicionar, copiar o link, rotacionar (link
//  novo, o antigo para de funcionar), mapear (abre a MappingEditorView) e excluir.
//

import SwiftUI
import AppKit

struct ProfilesListView: View {
    @ObservedObject var client: WebhookClient
    @State private var profiles: [WebhookClient.WebhookProfile] = []
    @State private var editing: WebhookClient.WebhookProfile?
    @State private var rotating: WebhookClient.WebhookProfile?
    @State private var novoNome = ""

    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                TextField("Nome do perfil (ex.: GitHub)", text: $novoNome)
                    .onSubmit(adicionar)
                Button("Adicionar", action: adicionar)
            }
            List(profiles) { p in
                HStack {
                    Text(p.icon ?? "🔔").frame(width: 22)
                    VStack(alignment: .leading) {
                        Text(p.name)
                        Text(p.hasMapping ? "mapeado" : "sem mapa (captura)")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    // ponytail: .borderless em cada botão — numa List row do macOS,
                    // botões bordered fazem a linha inteira virar um alvo de toque só.
                    if let l = client.link(for: p.id) {
                        Button("Copiar link") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(l, forType: .string)
                        }
                        .buttonStyle(.borderless)
                    }
                    Button("Mapear") { editing = p }
                        .buttonStyle(.borderless)
                    Button("Rotacionar", role: .destructive) { rotating = p }
                        .buttonStyle(.borderless)
                    Button(role: .destructive) {
                        Task { await client.deleteProfile(p.id); await recarregar() }
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.borderless)
                }
            }
        }
        .padding()
        .task { await recarregar() }
        .sheet(item: $editing) { p in
            MappingEditorView(client: client, profile: p,
                              onClose: { editing = nil; Task { await recarregar() } })
        }
        .confirmationDialog("Gerar um link novo para este perfil? O link antigo para de funcionar.",
                            isPresented: Binding(get: { rotating != nil },
                                                 set: { if !$0 { rotating = nil } }),
                            titleVisibility: .visible) {
            Button("Gerar link novo", role: .destructive) {
                if let p = rotating {
                    Task { await client.rotateProfile(p.id); await recarregar() }
                }
                rotating = nil
            }
            Button("Cancelar", role: .cancel) { rotating = nil }
        }
    }

    private func adicionar() {
        let nome = novoNome.trimmingCharacters(in: .whitespaces)
        guard !nome.isEmpty else { return }
        novoNome = ""
        Task { _ = await client.createProfile(name: nome); await recarregar() }
    }

    private func recarregar() async { profiles = await client.listProfiles() }
}
