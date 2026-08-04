//
//  WebhookAssistantView.swift
//  Knobler
//
//  O assistente de perfis de webhook: sheet sobre Ajustes, aberto sempre pelo
//  botão "Adicionar perfil" (013). Passos Nome → Serviço → Link → Primeiro envio
//  → Mapa (004). O conteúdo dos passos Serviço e Link é o preset (006/017); o
//  passo Mapa É o editor de sempre (`MappingEditorView`).
//
//  Fechar no meio não desfaz nada: o perfil nasce no passo Nome e um perfil sem
//  mapping é estado legítimo no relay (captura-only). A retomada é derivada em
//  `PassoAssistente.retomada` — nada de passo persistido.
//

import AppKit
import SwiftUI

struct WebhookAssistantView: View {
    @ObservedObject var client: WebhookClient
    /// Preenchido só na retomada; `nil` = perfil novo (nasce no passo Nome).
    var perfilExistente: WebhookClient.WebhookProfile?
    var passoInicial: PassoAssistente = .nome
    var onClose: () -> Void

    @State private var passo: PassoAssistente = .nome
    @State private var nome = ""
    @State private var presetID: String?          // nil = "Outro serviço (sem preset)"
    @State private var profileID: String?
    @State private var lastPayloadAt: Double?
    @State private var criando = false

    private var preset: WebhookPreset? { presetID.flatMap(WebhookPresets.by(id:)) }
    private var link: String? { profileID.flatMap { client.link(for: $0) } }

    var body: some View {
        VStack(spacing: 0) {
            if passo == .mapa, let id = profileID {
                // o passo Mapa é o editor completo — sem trilha nem rodapé duplicado
                MappingEditorView(
                    client: client,
                    profile: .init(id: id, name: nome, hasMapping: false, icon: nil),
                    preset: preset,
                    onClose: onClose)
            } else {
                trilha
                Divider()
                conteudo
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(24)
                Divider()
                rodape
            }
        }
        .frame(minWidth: 640, minHeight: 480)
        .onAppear {
            passo = passoInicial
            profileID = perfilExistente?.id
            nome = perfilExistente?.name ?? ""
        }
        .task(id: passo) { await esperarPrimeiroEnvio() }
    }

    // MARK: trilha e rodapé

    private var trilha: some View {
        HStack(spacing: 0) {
            ForEach(PassoAssistente.allCases, id: \.rawValue) { p in
                HStack(spacing: 6) {
                    ZStack {
                        Circle()
                            .fill(p.rawValue <= passo.rawValue ? Color.accentColor : Color.secondary.opacity(0.25))
                            .frame(width: 18, height: 18)
                        if p.rawValue < passo.rawValue {
                            Image(systemName: "checkmark")
                                .font(.system(size: 9, weight: .bold)).foregroundStyle(.white)
                        } else {
                            Text("\(p.rawValue + 1)").font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(p == passo ? Color.white : Color.secondary)
                        }
                    }
                    Text(p.titulo).font(.caption).foregroundStyle(p == passo ? .primary : .secondary)
                    if p.proximo != nil {
                        Rectangle().fill(.quaternary).frame(height: 1).frame(minWidth: 12)
                    }
                }
            }
        }
        .padding(.horizontal, 20).padding(.vertical, 14)
    }

    private var rodape: some View {
        HStack {
            Button("Fechar") { onClose() }
            Spacer()
            if let anterior = passo.anterior, passo != .nome || perfilExistente == nil {
                Button("Voltar") { passo = anterior }
                    .disabled(profileID != nil && anterior == .nome)   // nome já criado no relay
            }
            Button("Continuar") { Task { await continuar() } }
                .buttonStyle(.borderedProminent)
                .disabled(!podeContinuar)
        }
        .padding(16)
    }

    private var podeContinuar: Bool {
        switch passo {
        case .nome: return !nome.trimmingCharacters(in: .whitespaces).isEmpty && !criando
        case .primeiroEnvio: return lastPayloadAt != nil
        default: return true
        }
    }

    private func continuar() async {
        if passo == .nome, profileID == nil {
            criando = true
            defer { criando = false }
            guard let id = await client.createProfile(
                name: nome.trimmingCharacters(in: .whitespaces)) else { return }
            profileID = id
        }
        if let p = passo.proximo { passo = p }
    }

    // MARK: passos

    @ViewBuilder private var conteudo: some View {
        switch passo {
        case .nome: passoNome
        case .servico: passoServico
        case .link: passoLink
        case .primeiroEnvio: passoPrimeiroEnvio
        case .mapa: EmptyView()   // tratado no body (é o editor)
        }
    }

    private var passoNome: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Como você chama esse perfil?").font(.title3.weight(.semibold))
            Text("Cada perfil tem um link próprio. Um por serviço costuma bastar.")
                .font(.callout).foregroundStyle(.secondary)
            TextField("Nome do perfil", text: $nome)
                .textFieldStyle(.roundedBorder).frame(maxWidth: 320)
                .disabled(profileID != nil)
        }
    }

    private var passoServico: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text("De onde vêm as notificações?").font(.title3.weight(.semibold))
                Text("Isso define as instruções e a sugestão de mapa. Dá pra mudar depois.")
                    .font(.callout).foregroundStyle(.secondary)
                ForEach(WebhookPresets.todos, id: \.id) { p in
                    opcao(id: p.id, icone: p.icone, titulo: p.servico, detalhe: p.caminho)
                }
                opcao(id: nil, icone: "bell", titulo: "Outro serviço (sem preset)",
                      detalhe: "Você mesmo monta o mapa depois do primeiro envio")
            }
        }
    }

    private func opcao(id: String?, icone: String, titulo: String, detalhe: String) -> some View {
        let selecionado = presetID == id
        return Button {
            presetID = id
        } label: {
            HStack(spacing: 10) {
                Image(systemName: icone).frame(width: 22)
                VStack(alignment: .leading, spacing: 2) {
                    Text(titulo)
                    Text(detalhe).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if selecionado { Image(systemName: "checkmark.circle.fill").foregroundStyle(.tint) }
            }
            .padding(.vertical, 8).padding(.horizontal, 12)
            .frame(maxWidth: 460, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 8)
                .fill(selecionado ? Color.accentColor.opacity(0.12) : Color.secondary.opacity(0.06)))
        }
        .buttonStyle(.plain)
    }

    private var passoLink: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Cole este link no \(preset?.servico ?? "serviço")")
                .font(.title3.weight(.semibold))
            if let link {
                HStack {
                    Text(link).font(.callout.monospaced()).lineLimit(1).truncationMode(.middle)
                    Spacer()
                    Button("Copiar") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(link, forType: .string)
                    }
                }
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 8).fill(.quinary))
                .frame(maxWidth: 520)
            } else {
                Label("O link deste perfil não está neste Mac — gere um link novo no painel.",
                      systemImage: "exclamationmark.triangle")
                    .font(.callout).foregroundStyle(.orange)
            }
            if let preset {
                Label(preset.instrucao, systemImage: "info.circle")
                    .font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 520, alignment: .leading)
                if let r = preset.ressalva {
                    Label(r, systemImage: "exclamationmark.triangle")
                        .font(.caption).foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: 520, alignment: .leading)
                }
            } else {
                Label("Cole o link onde o serviço pedir a URL do webhook (método POST).",
                      systemImage: "info.circle")
                    .font(.callout).foregroundStyle(.secondary)
            }
        }
    }

    private var passoPrimeiroEnvio: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Dispare um evento de teste").font(.title3.weight(.semibold))
            HStack(spacing: 10) {
                if lastPayloadAt != nil {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                    Text("Recebido — dá pra montar o mapa a partir do que chegou.").font(.callout)
                } else {
                    ProgressView().controlSize(.small)
                    Text("Esperando o primeiro envio nesse link…")
                        .font(.callout).foregroundStyle(.secondary)
                }
            }
            .padding(12)
            .frame(maxWidth: 520, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 8).fill(.quinary))
            Text("Não precisa ficar olhando: pode fechar, o perfil continua esperando e o "
                 + "painel retoma daqui.")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Árvore ao vivo por polling enquanto o passo está na tela (007) — o
    /// `.task(id: passo)` cancela sozinho ao trocar de passo ou fechar o sheet.
    private func esperarPrimeiroEnvio() async {
        guard passo == .primeiroEnvio, let id = profileID else { return }
        while !Task.isCancelled {
            if let d = await client.getProfile(id), let at = d.lastPayloadAt {
                lastPayloadAt = at
                return
            }
            try? await Task.sleep(nanoseconds: 2_000_000_000)
        }
    }
}
