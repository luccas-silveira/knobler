import AppKit
import SwiftUI

// Uma bolha da conversa do WhatsApp (mockup, variante A): recebida a 10%,
// enviada a 22%, canto 8, texto 10 pt com hora e tique à direita; citação
// dentro da bolha, reação numa cápsula embaixo, mídia pelo tipo e a falha de
// envio em laranja embaixo da bolha (sem bolha vermelha). O que o clique na
// mídia faz sai de `WAConversaModelo.acao(bolha:)`. Com o mouse em cima (ou a
// barra aberta), reagir e citar aparecem ao lado; a barra de 6 reações abre
// acima da bolha e é estado por tela (`vm.whatsappReacoesEm`).

struct WhatsAppBolhaView: View {
    @ObservedObject var vm: NotchViewModel
    let bolha: WABolha
    let chave: WAChave
    let mostraRemetente: Bool
    /// Reagir e citar.
    let podeAgir: Bool
    let larguraMaxima: CGFloat
    /// Quem escreveu a mensagem citada, já resolvido pela conversa.
    let nomeDaCitacao: String?
    @ObservedObject var store: WhatsAppStore
    @State private var hover = false

    private var m: WAMensagem { bolha.mensagem }
    private var barraAberta: Bool { podeAgir && vm.whatsappReacoesEm == m.id }
    private var estado: WAEstadoDaBolha { store.estado.estadoDaBolha(bolha) }
    private var falhou: Bool { estado == .falhou }
    private var midia: WAMostraMidia { WAConversaModelo.mostraMidia(bolha: bolha) }

    var body: some View {
        VStack(alignment: m.deMim ? .trailing : .leading, spacing: 0) {
            if barraAberta {
                // linha própria acima da bolha: empurra o layout em vez de
                // cobrir esta mensagem ou a de cima
                barraDeReacoes.padding(.bottom, 4)
            }
            if mostraRemetente {
                Text(remetente)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.62))
                    .lineLimit(1)
                    .padding(.leading, 8)
                    .padding(.top, 4)
                    .padding(.bottom, 2)
            }
            corpoComReacao
                .overlay(alignment: m.deMim ? .leading : .trailing) {
                    if podeAgir && (hover || barraAberta) {
                        // ao lado da bolha, 4 pt de folga, centradas na altura;
                        // por offset, que não mexe no tamanho da bolha
                        let passo = Self.larguraDasAcoes + 4
                        acoes.offset(x: m.deMim ? -passo : passo)
                    }
                }
                .frame(maxWidth: larguraMaxima, alignment: m.deMim ? .trailing : .leading)
            if falhou { falha }
        }
        .frame(maxWidth: .infinity, alignment: m.deMim ? .trailing : .leading)
        .contentShape(Rectangle())
        .onHover { hover = $0 }
        .zIndex(barraAberta ? 1 : 0)
    }

    // MARK: - reagir e citar

    /// A minha reação atual, se houver.
    private var minhaReacao: String? {
        m.reacoes.last { $0.deMim && !$0.emoji.isEmpty }?.emoji
    }

    /// Dois botões de 22 pt com 2 pt entre eles.
    private static let larguraDasAcoes: CGFloat = 22 * 2 + 2

    private var acoes: some View {
        HStack(spacing: 2) {
            WABotaoDeAcao(icone: "face.smiling", ajuda: "Reagir") {
                vm.whatsappReacoesEm = barraAberta ? nil : m.id
            }
            WABotaoDeAcao(icone: "arrowshape.turn.up.left", ajuda: "Responder citando") {
                store.citar(m, em: chave)
                vm.fecharReacoesWhatsApp()
            }
        }
        .fixedSize()
    }

    /// Cápsula preta com fundo branco 15%: 6 botões de 26 pt, a minha marcada.
    private var barraDeReacoes: some View {
        let atual = minhaReacao
        return HStack(spacing: 2) {
            ForEach(WACompositor.reacoes, id: \.self) { e in
                Button {
                    let emoji = WACompositor.emojiParaEnviar(escolhido: e, atual: atual)
                    let (alvo, k) = (m.id, chave)
                    vm.fecharReacoesWhatsApp()
                    Task { await store.reagir(emoji, a: alvo, em: k) }
                } label: {
                    Text(e)
                        .font(.system(size: 15))
                        .frame(width: 26, height: 26)
                        .background(Circle().fill(.white.opacity(e == atual ? 0.25 : 0)))
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Reagir com \(e)")
                .accessibilityAddTraits(e == atual ? .isSelected : [])
            }
        }
        .padding(3)
        .background(Capsule().fill(.white.opacity(0.15)))
        .background(Capsule().fill(.black))
        .fixedSize()
        .focusable()
        .focusEffectDisabled()
        .onKeyPress(.escape) {
            vm.fecharReacoesWhatsApp()
            store.cancelarCitacao(chave)
            return .handled
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Reações")
    }

    private var remetente: String {
        if let nome = m.remetenteNome?.trimmingCharacters(in: .whitespaces), !nome.isEmpty { return nome }
        return m.remetente.split(separator: "@", maxSplits: 1).first.map(String.init) ?? m.remetente
    }

    // MARK: - bolha e reação

    @ViewBuilder
    private var corpoComReacao: some View {
        let emojis = reacoes
        if emojis.isEmpty {
            corpo
        } else {
            corpo
                .overlay(alignment: m.deMim ? .bottomTrailing : .bottomLeading) {
                    WACapsulaDeReacao(texto: emojis)
                        .offset(x: m.deMim ? -6 : 6, y: 14)
                }
                .padding(.bottom, 10)
        }
    }

    /// Emojis distintos, na ordem em que chegaram.
    private var reacoes: String {
        var vistos: [String] = []
        for r in m.reacoes where !r.emoji.isEmpty && !vistos.contains(r.emoji) { vistos.append(r.emoji) }
        return vistos.joined()
    }

    @ViewBuilder
    private var corpo: some View {
        if m.apagada != nil {
            apagada
        } else if midia == .figurinha {
            // figurinha não tem bolha: a imagem e a hora soltas
            VStack(alignment: .trailing, spacing: 4) {
                WAMidiaDaBolha(bolha: bolha, chave: chave, tipo: .figurinha, store: store)
                meta
            }
        } else {
            WAColunaDaBolha {
                if let c = m.citacao { citacao(c).waEstica() }
                conteudo
            }
            .padding(.vertical, 5)
            .padding(.horizontal, 8)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(.white.opacity(m.deMim ? 0.22 : 0.10)))
        }
    }

    @ViewBuilder
    private var conteudo: some View {
        switch midia {
        case .nenhuma, .figurinha:
            textoComMeta(m.texto)
        case .imagem, .video:
            WAMidiaDaBolha(bolha: bolha, chave: chave, tipo: midia, store: store)
            if m.texto.isEmpty { metaSolta } else { textoComMeta(m.texto) }
        case .documento, .audio, .indisponivel:
            WAMidiaDaBolha(bolha: bolha, chave: chave, tipo: midia, store: store)
            metaSolta
        }
    }

    /// Hora sozinha no canto de baixo da bolha (mídia sem legenda).
    private var metaSolta: some View {
        meta.frame(maxWidth: .infinity, alignment: .trailing).waEstica()
    }

    private var apagada: some View {
        WAColunaDaBolha { textoComMeta(nil) }
            .padding(.vertical, 5)
            .padding(.horizontal, 8)
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(.white.opacity(0.15), lineWidth: 1))
    }

    // MARK: - texto, hora e tique

    /// Texto com a hora "flutuando" no fim da última linha: um espaço
    /// transparente do tamanho da hora reserva o lugar, e a hora de verdade
    /// fica por cima, no canto de baixo. `nil` é a mensagem apagada.
    private func textoComMeta(_ texto: String?) -> some View {
        let reserva = Text("\u{2003}" + metaTexto + tiqueReserva).foregroundColor(.clear)
        let corpo: Text
        if texto == nil {
            corpo = Text("\(Image(systemName: "nosign")) \(Text(WATextos.apagada).italic())")
                .foregroundColor(.white.opacity(0.62))
        } else {
            corpo = Text(texto ?? "")
        }
        return Text("\(corpo)\(reserva)")
            .font(.system(size: 10))
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .bottomTrailing) { meta }
            .waEstica()
    }

    private var metaTexto: String {
        (m.editada != nil ? "editada · " : "") + WAConversaModelo.hora(ts: m.ts, calendario: .current)
    }

    private var tique: WATique {
        guard m.deMim, !falhou else { return .nenhum }
        return WAApresentacao.tique(estado)
    }

    /// Largura aproximada do tique em espaços largos, para a reserva do texto.
    private var tiqueReserva: String {
        switch tique {
        case .nenhum: return ""
        case .relogio, .um: return "\u{2002}\u{2002}"
        case .dois: return "\u{2002}\u{2002}\u{2002}"
        case .doisLida: return "\u{2002}\u{2002}\u{2002}\u{2002}"
        }
    }

    private var meta: some View {
        HStack(spacing: 3) {
            Text(metaTexto)
                .font(.system(size: 10).monospacedDigit())
                .foregroundStyle(.white.opacity(0.56))
            WATiqueView(tique: tique)
        }
        .lineLimit(1)
        .fixedSize()
    }

    // MARK: - citação

    private func citacao(_ c: WACitacao) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(nomeDaCitacao ?? "")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white.opacity(0.85))
                .lineLimit(1)
            Text(c.texto)
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.62))
                .lineLimit(2)
        }
        .padding(.vertical, 4)
        .padding(.leading, 10)
        .padding(.trailing, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white.opacity(0.08))
        .overlay(alignment: .leading) {
            Rectangle().fill(.white.opacity(0.6)).frame(width: 3)
        }
        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
    }

    // MARK: - falha

    private var falha: some View {
        HStack(spacing: 4) {
            Image(systemName: "exclamationmark.circle")
            Text(WATextos.falhaTitulo + " · ")
            Button {
                Task { await store.retentar(idLocal: bolha.id, em: chave) }
            } label: {
                Text(WATextos.falhaAcao).underline()
            }
            .buttonStyle(.plain)
        }
        .font(.system(size: 10))
        .foregroundStyle(.orange)
        .padding(.top, 3)
    }
}

// MARK: - Coluna da bolha

private struct WAEstica: LayoutValueKey {
    static let defaultValue = false
}

private extension View {
    /// Estica até a largura da bolha (citação, texto, hora solta), sem alargá-la.
    func waEstica() -> some View { layoutValue(key: WAEstica.self, value: true) }
}

/// Coluna da bolha com espaço de 4: a largura é a do filho mais largo (sem
/// passar da proposta), e os filhos marcados com `waEstica()` esticam até
/// ela, como o flex em coluna do mockup. Um `VStack` com `maxWidth: .infinity`
/// alargaria toda bolha até o limite.
private struct WAColunaDaBolha: Layout {
    var espaco: CGFloat = 4

    private func largura(_ proposta: ProposedViewSize, _ subviews: Subviews) -> CGFloat {
        let limite = proposta.width ?? .infinity
        return subviews.map { s -> CGFloat in
            if s[WAEstica.self] { return min(s.sizeThatFits(.unspecified).width, limite) }
            return s.sizeThatFits(ProposedViewSize(width: proposta.width, height: nil)).width
        }.max() ?? 0
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let w = largura(proposal, subviews)
        let p = ProposedViewSize(width: w, height: nil)
        let altura = subviews.map { $0.sizeThatFits(p).height }.reduce(0, +)
        return CGSize(width: w, height: altura + espaco * CGFloat(max(0, subviews.count - 1)))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let p = ProposedViewSize(width: bounds.width, height: nil)
        var y = bounds.minY
        for s in subviews {
            s.place(at: CGPoint(x: bounds.minX, y: y), anchor: .topLeading, proposal: p)
            y += s.sizeThatFits(p).height + espaco
        }
    }
}

// MARK: - Tique

/// Relógio, um tique, dois tiques, ou dois tiques pretos numa cápsula branca
/// (lida: a única forma branca cheia do notch).
struct WATiqueView: View {
    let tique: WATique

    var body: some View {
        switch tique {
        case .nenhum:
            EmptyView()
        case .relogio:
            Image(systemName: "clock").font(.system(size: 9)).foregroundStyle(.white.opacity(0.85))
        case .um:
            Image(systemName: "checkmark").font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.white.opacity(0.85))
        case .dois:
            WATiquesDuplos(tamanho: 9).foregroundStyle(.white.opacity(0.85))
        case .doisLida:
            WATiquesDuplos(tamanho: 8, peso: .heavy)
                .foregroundStyle(.black)
                .padding(.horizontal, 3)
                .frame(height: 12)
                .background(Capsule().fill(.white))
                .accessibilityLabel("lida")
        }
    }
}

/// Dois `checkmark` encavalados (o SF Symbols não tem o tique duplo).
struct WATiquesDuplos: View {
    let tamanho: CGFloat
    var peso: Font.Weight = .semibold

    var body: some View {
        HStack(spacing: -tamanho * 0.55) {
            Image(systemName: "checkmark")
            Image(systemName: "checkmark")
        }
        .font(.system(size: tamanho, weight: peso))
    }
}

// MARK: - Ações

/// Botão de ação ao lado da bolha: 22 pt, canto 8, fundo branco 8% (15% no hover).
private struct WABotaoDeAcao: View {
    let icone: String
    let ajuda: String
    let acao: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: acao) {
            Image(systemName: icone)
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.85))
                .frame(width: 22, height: 22)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(.white.opacity(hover ? 0.15 : 0.08)))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .help(ajuda)
        .accessibilityLabel(ajuda)
    }
}

// MARK: - Reação

/// Cápsula embaixo da bolha: fundo preto com borda branca 15%.
private struct WACapsulaDeReacao: View {
    let texto: String

    var body: some View {
        Text(texto)
            .font(.system(size: 11))
            .padding(.horizontal, 5)
            .frame(height: 16)
            .background(Capsule().fill(.black))
            .overlay(Capsule().strokeBorder(.white.opacity(0.15), lineWidth: 1))
            .padding(2)
            .background(Capsule().fill(.black))
            .accessibilityLabel("Reação \(texto)")
    }
}

// MARK: - Mídia

/// Foto, vídeo, documento, áudio, figurinha ou mídia indisponível. Carrega só
/// quando aparece: primeiro a miniatura, depois o arquivo (foto e figurinha).
private struct WAMidiaDaBolha: View {
    let bolha: WABolha
    let chave: WAChave
    let tipo: WAMostraMidia
    @ObservedObject var store: WhatsAppStore
    @State private var imagem: NSImage?
    /// A ponte pediu a mídia ao celular (`410`): spinner até o evento `midia`.
    @State private var aguardando = false

    private var m: WAMensagem { bolha.mensagem }

    var body: some View {
        switch tipo {
        case .imagem: foto
        case .video: video
        case .documento: documento
        case .audio: audio
        case .figurinha: figurinha
        case .indisponivel: indisponivel
        case .nenhuma: EmptyView()
        }
    }

    // MARK: foto e vídeo

    private var foto: some View {
        Button(action: agir) {
            quadro
                .overlay { if aguardando { spinner } }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Foto")
        .task(id: bolha.id) { await carregar(arquivoInteiro: true) }
    }

    private var video: some View {
        quadro
            .overlay {
                Button(action: agir) {
                    ZStack {
                        Circle().fill(.black.opacity(0.55))
                        if aguardando {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(systemName: "play.fill").font(.system(size: 14))
                        }
                    }
                    .frame(width: 34, height: 34)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(m.midia?.segundos.map { "Vídeo de \(WAApresentacao.duracao($0))" } ?? "Vídeo")
            }
            .overlay(alignment: .bottomLeading) {
                if let s = m.midia?.segundos {
                    Text(WAApresentacao.duracao(s))
                        .font(.system(size: 10).monospacedDigit())
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(.black.opacity(0.55)))
                        .padding(6)
                }
            }
            .task(id: bolha.id) { await carregar(arquivoInteiro: false) }
    }

    /// 200 × 125, canto 6; sem imagem ainda, um fundo branco a 8%.
    private var quadro: some View {
        ZStack {
            Rectangle().fill(.white.opacity(0.08))
            if let imagem {
                Image(nsImage: imagem).resizable().scaledToFill()
            }
        }
        .frame(width: 200, height: 125)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .contentShape(Rectangle())
    }

    private var spinner: some View {
        ProgressView().controlSize(.small)
            .frame(width: 34, height: 34)
            .background(Circle().fill(.black.opacity(0.55)))
    }

    // MARK: documento

    private var documento: some View {
        HStack(spacing: 8) {
            Image(systemName: "doc.text")
                .font(.system(size: 15))
                .foregroundStyle(.white.opacity(0.85))
                .frame(width: 30, height: 30)
                .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(.white.opacity(0.08)))
            VStack(alignment: .leading, spacing: 0) {
                Text(m.midia?.nome.isEmpty == false ? m.midia!.nome : "Documento")
                    .font(.system(size: 10, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                if let md = m.midia {
                    Text(WAApresentacao.tamanho(mimetype: md.mimetype, bytes: md.tamanho))
                        .font(.system(size: 10).monospacedDigit())
                        .foregroundStyle(.white.opacity(0.56))
                }
            }
            Spacer(minLength: 0)
            Button(action: agir) {
                Group {
                    if aguardando {
                        ProgressView().controlSize(.mini)
                    } else {
                        Image(systemName: "arrow.down.to.line").font(.system(size: 13))
                    }
                }
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white.opacity(0.85))
            .accessibilityLabel("Baixar \(m.midia?.nome ?? "documento")")
        }
        .frame(width: 210)
    }

    // MARK: áudio

    private var audio: some View {
        WAAudioDaBolha(id: bolha.id, segundos: m.midia?.segundos, aguardando: aguardando, agir: agir)
    }

    // MARK: figurinha e indisponível

    private var figurinha: some View {
        Group {
            if let imagem {
                Image(nsImage: imagem).resizable().scaledToFit()
            } else {
                Color.clear
            }
        }
        .frame(width: 90, height: 90)
        .accessibilityLabel("Figurinha")
        .task(id: bolha.id) { await carregar(arquivoInteiro: true) }
    }

    private var indisponivel: some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle")
            Text(WATextos.midiaIndisponivel)
        }
        .font(.system(size: 10))
        .foregroundStyle(.white.opacity(0.62))
        .frame(width: 200, height: 56)
        .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(.white.opacity(0.06)))
    }

    // MARK: carga e clique

    /// Já no cache: o arquivo direto. Senão a miniatura e, para foto e
    /// figurinha, o arquivo inteiro depois.
    private func carregar(arquivoInteiro: Bool) async {
        guard bolha.envio == nil else { return }
        let caminho = store.midia.caminho(chave: chave, mensagem: m)
        if !FileManager.default.fileExists(atPath: caminho.path),
           let d = await store.midia.miniatura(chave: chave, mensagem: m), let img = NSImage(data: d) {
            imagem = img
        }
        guard arquivoInteiro || FileManager.default.fileExists(atPath: caminho.path) else { return }
        if case let .arquivo(url) = await store.midia.arquivo(chave: chave, mensagem: m),
           let d = try? Data(contentsOf: url), let img = NSImage(data: d) {
            imagem = img
        }
    }

    private func agir() {
        guard !aguardando else { return }
        let acao = WAConversaModelo.acao(bolha: bolha)
        if acao == .tocarAudio, WAPlayer.shared.tocando == bolha.id {
            WAPlayer.shared.pausar()
            return
        }
        guard acao != .nenhuma else { return }
        Task { await executar(acao) }
    }

    /// Pede o arquivo; com `.aguardando` (a ponte pediu ao celular), tenta de
    /// novo a cada segundo até o evento `midia` liberar ou dizer indisponível.
    private func executar(_ acao: WAAcaoDaBolha) async {
        for _ in 0..<180 {
            let r = await store.midia.arquivo(chave: chave, mensagem: m)
            switch r {
            case let .arquivo(url):
                aguardando = false
                switch acao {
                case .abrirArquivo: NSWorkspace.shared.open(url)
                case .mostrarNoFinder: NSWorkspace.shared.activateFileViewerSelecting([url])
                case .tocarAudio: WAPlayer.shared.tocar(url: url, id: bolha.id)
                case .nenhuma: break
                }
                return
            case .aguardando:
                aguardando = true
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            case .indisponivel, .contaDesconectada, .falhou:
                // ponytail: indisponível vira a bolha própria pelo evento `midia`;
                // o resto só para o spinner (o log já saiu no cache)
                aguardando = false
                return
            }
        }
        aguardando = false
    }
}

/// Play de 26 pt, forma de onda e duração. Só esta parte observa o player
/// (o progresso muda 10 vezes por segundo enquanto toca).
private struct WAAudioDaBolha: View {
    let id: String
    let segundos: Int?
    let aguardando: Bool
    let agir: () -> Void
    @ObservedObject private var player = WAPlayer.shared

    private var tocando: Bool { player.tocando == id }

    var body: some View {
        HStack(spacing: 8) {
            Button(action: agir) {
                ZStack {
                    Circle().fill(.white)
                    if aguardando {
                        ProgressView().controlSize(.mini)
                    } else {
                        Image(systemName: tocando ? "pause.fill" : "play.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(.black)
                    }
                }
                .frame(width: 26, height: 26)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(tocando ? "Pausar áudio" : "Tocar áudio")
            WAOndaDaBolha(semente: id, tocado: tocando ? player.progresso : 0)
                .frame(height: 22)
            if let segundos {
                Text(WAApresentacao.duracao(segundos))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.56))
            }
        }
        .frame(width: 210)
    }
}

/// 30 barras brancas a 60% (as já tocadas em branco cheio), alturas fixas por
/// mensagem: a ponte não manda a forma de onda de quem recebe.
private struct WAOndaDaBolha: View {
    let semente: String
    let tocado: Double

    private var alturas: [CGFloat] {
        var s: UInt64 = 1469598103934665603
        for b in semente.utf8 { s = (s ^ UInt64(b)) &* 1099511628211 }
        return (0..<30).map { _ in
            s = s &* 6364136223846793005 &+ 1442695040888963407
            return CGFloat(4 + Int((s >> 33) % 17))
        }
    }

    var body: some View {
        let hs = alturas
        let feitas = Int((tocado * 30).rounded(.down))
        HStack(alignment: .center, spacing: 2) {
            ForEach(0..<30, id: \.self) { i in
                Capsule()
                    .fill(.white.opacity(i < feitas ? 1 : 0.6))
                    .frame(width: 2, height: hs[i])
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityHidden(true)
    }
}
