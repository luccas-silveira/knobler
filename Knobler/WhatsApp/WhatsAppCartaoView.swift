import AppKit
import SwiftUI

// Card de chegada do WhatsApp (mockup, aba "Card de chegada": `.cm`,
// `.cm-acct`, `.cm-head`, `.cm-thumb`, `.cmp`), no molde do card de
// Mensagens (IncomingMessageView): linha da conta, cabeçalho que abre a
// conversa nesta tela, X que fecha o card em todas as telas, quadro da mídia
// e o campo "Responder…" ligado ao rascunho da conversa. Responder pelo card
// marca a conversa como lida (o store faz depois do envio).
//
// Quadro da mídia (mockup 2026-11-10-whatsapp-cartao-nitido): a miniatura
// entra na hora e a foto inteira a substitui quando chega; vídeo fica na
// miniatura, com play e duração. A imagem aparece inteira, num quadro de
// 120…200 pt que segue a proporção dela, sobre uma cópia desfocada e escura.

struct WhatsAppCartaoView: View {
    @ObservedObject var vm: NotchViewModel
    let notificacao: NotchNotification
    @ObservedObject var store = WhatsAppStore.shared
    @StateObject private var foto = WAFotoLoader()
    @FocusState private var campoFocado: Bool
    @State private var miniatura: NSImage?
    @State private var fotoInteira: NSImage?

    /// Largura útil do card (360 − 2 × 20): a mesma do `.frame` na NotchView.
    private static let larguraUtil = NotchMetrics.whatsappCartaoLargura - 40
    /// Lado maior da foto inteira decodificada: o quadro tem no máximo
    /// 320 × 200 pt, então 800 px dá folga para tela Retina sem guardar a foto cheia.
    private static let ladoMaximoDaFoto = 800

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
                quadro(c)
                    .frame(maxWidth: .infinity)
                    .frame(height: alturaDoQuadro)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    // a mensagem entra na comparação: card novo da mesma conversa
                    // com a mesma altura também precisa avisar o VM
                    .onChange(of: MedidaDoQuadro(mensagemID: c.mensagemID, altura: alturaDoQuadro),
                              initial: true) { _, m in
                        vm.medirMidiaWhatsApp(mensagemID: m.mensagemID, altura: m.altura)
                    }
                    .task(id: c.mensagemID) {
                        // o card é o mesmo para a conversa (`.id(chave)`): a
                        // imagem da mensagem anterior não fica no quadro
                        if fotoInteira != nil || miniatura != nil {
                            fotoInteira = nil
                            miniatura = nil
                        }
                        async let mini: Void = carregarMiniatura(c, chave: k)
                        async let inteira: Void = carregarFotoInteira(c, chave: k)
                        _ = await (mini, inteira)
                    }
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

    /// A foto inteira quando chegou; antes dela (e sempre no vídeo), a miniatura.
    private var imagemDoQuadro: NSImage? { fotoInteira ?? miniatura }

    private var alturaDoQuadro: CGFloat {
        let tamanho = imagemDoQuadro?.size ?? .zero
        let proporcao = tamanho.height > 0 ? tamanho.width / tamanho.height : 0
        return WACartaoMidia.altura(larguraDisponivel: Self.larguraUtil, proporcao: proporcao)
    }

    /// Fundo desfocado e escurecido (preenche o que a foto em pé deixa vazio),
    /// a imagem inteira na frente e, no vídeo, o play e a duração.
    @ViewBuilder
    private func quadro(_ c: CartaoWhatsApp) -> some View {
        if let img = imagemDoQuadro {
            Color(white: 0.067)
                .overlay {
                    Image(nsImage: img).resizable().scaledToFill()
                        .blur(radius: 14, opaque: true)
                        .overlay(Color.black.opacity(0.45))
                }
                .overlay { Image(nsImage: img).resizable().scaledToFit() }
                .overlay { if c.ehVideo { play } }
                .overlay(alignment: .bottomLeading) {
                    if c.ehVideo, let d = WACartaoMidia.duracao(segundos: c.segundosDoVideo) {
                        Text(d)
                            .font(.system(size: 10).monospacedDigit())
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(.black.opacity(0.55)))
                            .padding(6)
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(rotuloDoQuadro(c))
        } else {
            Rectangle().fill(.white.opacity(0.08))
                .overlay(Image(systemName: c.ehVideo ? "video" : "photo")
                    .font(.system(size: 14)).foregroundStyle(.white.opacity(0.45)))
        }
    }

    /// Círculo escuro de 34 pt com o triângulo: diz "vídeo" sem abrir nada.
    private var play: some View {
        Circle().fill(.black.opacity(0.55))
            .frame(width: 34, height: 34)
            .overlay(Image(systemName: "play.fill").font(.system(size: 14)).offset(x: 1))
    }

    private func rotuloDoQuadro(_ c: CartaoWhatsApp) -> String {
        guard c.ehVideo else { return "Foto" }
        if let d = WACartaoMidia.duracao(segundos: c.segundosDoVideo) { return "Vídeo, \(d)" }
        return "Vídeo"
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

    private func mensagem(_ c: CartaoWhatsApp, chave k: WAChave) -> WAMensagem? {
        store.estado.bolhas(de: k).first(where: { $0.id == c.mensagemID })?.mensagem
    }

    /// A miniatura embutida da mensagem, se a mensagem já está no estado.
    private func carregarMiniatura(_ c: CartaoWhatsApp, chave k: WAChave) async {
        guard let m = mensagem(c, chave: k),
              let d = await store.midia.miniatura(chave: k, mensagem: m),
              let img = NSImage(data: d) else { return }
        miniatura = img
    }

    /// Foto: pede o arquivo inteiro e troca a miniatura por ele. `.aguardando`
    /// (recuperação pedida ao celular) tenta de novo a cada segundo enquanto
    /// o card existir; o resto fica na miniatura. Vídeo nunca baixa.
    private func carregarFotoInteira(_ c: CartaoWhatsApp, chave k: WAChave) async {
        guard let m = mensagem(c, chave: k), WACartaoMidia.baixaArquivo(tipo: m.tipo) else { return }
        while !Task.isCancelled {
            let r = await store.midia.arquivo(chave: k, mensagem: m)
            if case .arquivo(let url) = r {
                if let img = await Self.decodificar(url) { fotoInteira = img }
                return
            }
            guard WACartaoMidia.tentarDeNovo(r) else { return }
            try? await Task.sleep(for: .seconds(1))
        }
    }

    /// Decodifica fora da main, já reduzida ao tamanho do quadro e com a
    /// orientação do EXIF aplicada.
    private static func decodificar(_ url: URL) async -> NSImage? {
        let lado = ladoMaximoDaFoto
        return await Task.detached(priority: .userInitiated) { () -> NSImage? in
            guard let dados = try? Data(contentsOf: url),
                  let cg = RemoteAvatarLoader.miniatura(de: dados, ladoMaximo: lado) else { return nil }
            return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
        }.value
    }
}

private struct MedidaDoQuadro: Equatable {
    let mensagemID: String
    let altura: CGFloat
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
