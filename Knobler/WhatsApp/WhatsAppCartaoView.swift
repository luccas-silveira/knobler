import AppKit
import SwiftUI

// Card de chegada do WhatsApp (mockup, aba "Card de chegada": `.cm`,
// `.cm-acct`, `.cm-head`, `.cm-thumb`, `.cmp`), no molde do card de
// Mensagens (IncomingMessageView): linha da conta, cabeçalho que abre a
// conversa nesta tela, X que fecha o card em todas as telas, miniatura da foto
// e o campo "Responder…" ligado ao rascunho da conversa. Responder pelo card
// marca a conversa como lida (o store faz depois do envio).

struct WhatsAppCartaoView: View {
    @ObservedObject var vm: NotchViewModel
    let notificacao: NotchNotification
    @ObservedObject var store = WhatsAppStore.shared
    @StateObject private var foto = WAFotoLoader()
    @FocusState private var campoFocado: Bool
    @State private var miniatura: NSImage?

    private var cartao: CartaoWhatsApp? { notificacao.whatsapp }

    var body: some View {
        if let c = cartao {
            conteudo(c, chave: WAChave(conta: c.conta, jid: c.jid))
        }
    }

    private func conteudo(_ c: CartaoWhatsApp, chave k: WAChave) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            linhaDaConta(c)
            HStack(spacing: 8) {
                Button { vm.abrirWhatsApp(chave: c.chave, conta: c.conta) } label: { cabecalho(c) }
                    .buttonStyle(.plain)
                    .accessibilityHint("Abre a conversa")
                WABotaoDoCartao(icone: "xmark", ajuda: "Fechar") { store.dispensarCartao(chave: c.chave) }
            }
            if c.temMiniatura {
                miniaturaView
                    .frame(maxWidth: .infinity)
                    .frame(height: 120)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .task(id: c.mensagemID) { await carregarMiniatura(c, chave: k) }
            }
            HStack(spacing: 6) {
                campo(k, nome: notificacao.title)
                WABotaoDoCartao(icone: "paperplane.fill", ajuda: "Enviar") { responder(k) }
            }
        }
        .foregroundStyle(.white)
        .task(id: c.chave) { foto.carregar(conta: c.conta, jid: c.jid) }
        .onChange(of: campoFocado) { _, focado in
            vm.atualizarEdicaoWhatsApp(focado)
            if focado {
                store.campoEmUso = k
            } else if store.campoEmUso == k {
                store.campoEmUso = nil
            }
        }
        .onDisappear {
            if campoFocado { vm.atualizarEdicaoWhatsApp(false) }
            if store.campoEmUso == k { store.campoEmUso = nil }
        }
    }

    // MARK: - partes

    private func linhaDaConta(_ c: CartaoWhatsApp) -> some View {
        HStack(spacing: 5) {
            Image(systemName: "phone.bubble.fill")
            Text(c.rotuloDaConta).lineLimit(1)
            Spacer(minLength: 0)
            Text("agora")
        }
        .font(.system(size: 10))
        .foregroundStyle(.white.opacity(0.56))
    }

    private func cabecalho(_ c: CartaoWhatsApp) -> some View {
        HStack(spacing: 8) {
            avatar(c).frame(width: 30, height: 30)
            VStack(alignment: .leading, spacing: 1) {
                Text(notificacao.title)
                    .font(.system(size: 10, weight: .semibold))
                    .lineLimit(1)
                Text(corpo(c))
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.75))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
    }

    /// "3 mensagens novas" e o remetente do grupo em semibold e branco cheio;
    /// o texto da mensagem segue no 75% do corpo.
    private func corpo(_ c: CartaoWhatsApp) -> AttributedString {
        var resto = notificacao.body
        var saida = AttributedString()
        func destaque(_ s: String) {
            var a = AttributedString(s)
            a.font = .system(size: 10, weight: .semibold)
            a.foregroundColor = .white
            saida += a
        }
        let separador = " · "
        if c.contagem > 1, let r = resto.range(of: separador) {
            destaque(String(resto[..<r.lowerBound]))
            saida += AttributedString(separador)
            resto = String(resto[r.upperBound...])
        }
        if c.grupo != nil, let r = resto.range(of: ": ") {
            destaque(String(resto[..<r.upperBound]).trimmingCharacters(in: .whitespaces))
            saida += AttributedString(" ")
            resto = String(resto[r.upperBound...])
        }
        saida += AttributedString(resto)
        return saida
    }

    @ViewBuilder
    private func avatar(_ c: CartaoWhatsApp) -> some View {
        if let img = foto.imagem {
            Image(nsImage: img).resizable().scaledToFill().clipShape(Circle())
        } else {
            ZStack {
                Circle().fill(.gray.opacity(0.35))
                if c.grupo != nil {
                    Image(systemName: "person.2.fill").font(.system(size: 11))
                } else {
                    Text(String(notificacao.title.prefix(1)).uppercased())
                        .font(.system(size: 10, weight: .semibold))
                }
            }
        }
    }

    @ViewBuilder
    private var miniaturaView: some View {
        if let miniatura {
            Image(nsImage: miniatura).resizable().scaledToFill()
        } else {
            Rectangle().fill(.white.opacity(0.08))
                .overlay(Image(systemName: "photo").font(.system(size: 14)).foregroundStyle(.white.opacity(0.45)))
        }
    }

    private func campo(_ k: WAChave, nome: String) -> some View {
        let emUso = campoFocado || store.campoEmUso == k
        return ZStack(alignment: .leading) {
            if store.rascunho(k).isEmpty {
                Text("Responder…")
                    .foregroundStyle(.white.opacity(0.5))
                    .allowsHitTesting(false)
            }
            TextField("", text: Binding(
                get: { store.rascunho(k) },
                set: { store.definirRascunho($0, para: k) }))
                .textFieldStyle(.plain)
                .focused($campoFocado)
                .onSubmit { responder(k) }
                .accessibilityLabel("Responder a \(nome)")
        }
        .font(.system(size: 10))
        .padding(.horizontal, 8)
        .frame(height: 26)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(.white.opacity(0.10)))
        .overlay {
            // anel de foco: 2 pt, 1 pt para fora
            if emUso {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(.white.opacity(0.62), lineWidth: 2)
                    .padding(-3)
            }
        }
    }

    // MARK: - ações

    /// Avião e Enter: envia com a citação guardada, marca lida e fecha o card
    /// em todas as telas. Recusado, o card fica e o texto volta ao campo.
    private func responder(_ k: WAChave) {
        let t = store.rascunho(k).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        let store = store
        Task { await store.responderCartao(chave: k, texto: t) }
    }

    /// A miniatura embutida da mensagem, se a mensagem já está no estado.
    private func carregarMiniatura(_ c: CartaoWhatsApp, chave k: WAChave) async {
        guard let m = store.estado.bolhas(de: k).first(where: { $0.id == c.mensagemID })?.mensagem,
              let d = await store.midia.miniatura(chave: k, mensagem: m),
              let img = NSImage(data: d) else { return }
        miniatura = img
    }
}

/// Botão de ícone do card: 24 pt, canto 8, fundo só no hover (`.ib` do mockup).
private struct WABotaoDoCartao: View {
    let icone: String
    let ajuda: String
    let acao: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: acao) {
            Image(systemName: icone)
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(hover ? 1 : 0.85))
                .frame(width: 24, height: 24)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(.white.opacity(hover ? 0.08 : 0)))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .help(ajuda)
        .accessibilityLabel(ajuda)
    }
}
