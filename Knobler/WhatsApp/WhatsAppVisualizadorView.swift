import AVKit
import SwiftUI

// Visualizador de foto e vídeo dentro do notch (mockup aprovado em
// docs/vesta/mockups/2026-11-10-whatsapp-visualizador): cobre só a coluna da
// conversa, por cima do cabeçalho, das bolhas e do compositor. Topo com quem
// mandou e quando, e os botões Abrir no Pré-Visualização, Mostrar no Finder e
// Fechar. Abre na hora do clique: enquanto o arquivo vem do celular, a
// miniatura desfocada e o spinner; o que mostrar sai de `WAVisualizador`.

struct WhatsAppVisualizadorView: View {
    @ObservedObject var vm: NotchViewModel
    let visto: WhatsAppVisto
    let chave: WAChave
    @ObservedObject var store: WhatsAppStore

    @State private var estado: WAEstadoDoVisualizador = .carregando
    @State private var miniatura: NSImage?
    @State private var imagem: NSImage?
    @State private var player: AVPlayer?

    private var mensagem: WAMensagem? {
        store.estado.bolhas(de: chave).first { $0.id == visto.mensagemID }?.mensagem
    }

    private var conversa: WAConversa {
        store.estado.conversas(da: chave.conta).first { $0.jid == chave.jid }
            ?? WAConversa(jid: chave.jid, jids: [chave.jid],
                          tipo: chave.jid.hasSuffix("@g.us") ? .grupo : .individual,
                          nome: chave.jid.split(separator: "@").first.map(String.init) ?? chave.jid,
                          naoLidas: 0, marcadaNaoLida: false, ts: 0, ultima: nil)
    }

    private var ehVideo: Bool { mensagem?.tipo == .video }

    /// O arquivo já no Mac, para os dois botões do topo.
    private var arquivo: URL? {
        switch estado {
        case let .foto(url), let .video(url): return url
        case .carregando, .indisponivel, .naoDeuParaAbrir: return nil
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            if let m = mensagem {
                topo(m)
                area(m)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.top, 8)
                if estado != .indisponivel, estado != .naoDeuParaAbrir, let legenda = WAVisualizador.legenda(m) {
                    Text(legenda)
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.85))
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .padding(.horizontal, 24)
                        .padding(.top, 8)
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color.black)
        // cobre a conversa inteira: o clique não atravessa para as bolhas
        .contentShape(Rectangle())
        .task(id: visto.mensagemID) { await carregar() }
        .onDisappear { pararVideo() }
    }

    // MARK: - topo

    private func topo(_ m: WAMensagem) -> some View {
        let nome = WAVisualizador.remetente(mensagem: m, conversa: conversa)
        return HStack(spacing: 8) {
            ZStack {
                Circle().fill(.gray.opacity(0.35))
                Text(String(nome.prefix(1)).uppercased())
                    .font(.system(size: 10, weight: .semibold))
            }
            .frame(width: 22, height: 22)
            VStack(alignment: .leading, spacing: 0) {
                Text(nome)
                    .font(.system(size: 10, weight: .semibold))
                    .lineLimit(1)
                Text(WAVisualizador.subtitulo(conversa: conversa.nome, ts: m.ts, agora: Date(), calendario: .current))
                    .font(.system(size: 10).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.56))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            Spacer(minLength: 0)
            HStack(spacing: 4) {
                WABotaoDoVisualizador(icone: "arrow.up.forward.square", ajuda: WATextos.abrirNoPreVisualizacao,
                                      ativo: arquivo != nil) {
                    guard let url = arquivo else { return }
                    pararVideo()
                    NSWorkspace.shared.open(url)
                }
                WABotaoDoVisualizador(icone: "folder", ajuda: WATextos.mostrarNoFinder, ativo: arquivo != nil) {
                    guard let url = arquivo else { return }
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                }
                WABotaoDoVisualizador(icone: "xmark", ajuda: WATextos.fechar, ativo: true) {
                    pararVideo()
                    vm.fecharVisualizadorWhatsApp()
                }
            }
        }
        .frame(height: 28)
    }

    // MARK: - área da mídia

    @ViewBuilder
    private func area(_ m: WAMensagem) -> some View {
        switch estado {
        case .carregando:
            ZStack {
                if let miniatura {
                    Image(nsImage: miniatura)
                        .resizable()
                        .scaledToFit()
                        .blur(radius: 6)
                        // escurece por cima (não por filtro): o texto do
                        // spinner fica legível mesmo onde o desfoque não pega
                        .overlay(Color.black.opacity(0.35))
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
                VStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(WATextos.buscandoNoCelular(video: ehVideo))
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.85))
                }
            }
        case .foto:
            if let imagem {
                Image(nsImage: imagem)
                    .resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            } else if let a = WAVisualizador.aviso(.naoDeuParaAbrir, mensagem: m, conversa: conversa) {
                // o arquivo veio, mas não é uma imagem que o NSImage lê
                aviso(a)
            }
        case .video:
            ZStack {
                // quadro parado enquanto o player ainda não pode tocar
                if let miniatura {
                    Image(nsImage: miniatura).resizable().scaledToFit()
                }
                if let player {
                    WAPlayerDeVideo(player: player, quadroParado: miniatura) { estado = .naoDeuParaAbrir }
                        .id(ObjectIdentifier(player))
                        .onAppear { player.play() }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        case .indisponivel, .naoDeuParaAbrir:
            if let a = WAVisualizador.aviso(estado, mensagem: m, conversa: conversa) {
                aviso(a)
            }
        }
    }

    private func aviso(_ a: WAAvisoDoVisualizador) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 22))
                .foregroundStyle(.orange)
            Text(a.titulo)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.85))
            if let apoio = a.apoio {
                Text(apoio)
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.62))
            }
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: 260)
    }

    // MARK: - carga

    /// Miniatura primeiro (o desfocado do carregando); depois o arquivo, com
    /// `.aguardando` tentando de novo a cada segundo como a bolha fazia, até o
    /// evento `midia` liberar ou dizer indisponível.
    private func carregar() async {
        pararVideo()
        estado = .carregando
        imagem = nil
        miniatura = nil
        guard let m = mensagem else { return }
        let midia = WAConversaModelo.mostraMidia(bolha: WABolha(mensagem: m))
        // a foto já baixada dispensa a miniatura; o vídeo a usa de quadro parado
        if midia == .video || !FileManager.default.fileExists(atPath: store.midia.caminho(chave: chave, mensagem: m).path),
           let d = await store.midia.miniatura(chave: chave, mensagem: m) {
            miniatura = NSImage(data: d)
        }
        for _ in 0..<180 {
            let r = await store.midia.arquivo(chave: chave, mensagem: m)
            guard !Task.isCancelled else { return }
            let novo = WAVisualizador.estado(resultado: r, midia: midia)
            switch novo {
            case let .foto(url):
                imagem = (try? Data(contentsOf: url)).flatMap(NSImage.init(data:))
            case let .video(url):
                player = AVPlayer(url: url)
            case .carregando, .indisponivel, .naoDeuParaAbrir:
                break
            }
            estado = novo
            guard r == .aguardando else { return }
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            guard !Task.isCancelled else { return }
        }
        estado = .naoDeuParaAbrir
    }

    /// Fechar (ou trocar de mídia) para o vídeo e solta o arquivo.
    private func pararVideo() {
        player?.pause()
        player?.replaceCurrentItem(with: nil)
        player = nil
    }
}

/// `AVPlayerView` com os controles do sistema numa barra embaixo (pausa,
/// tempo, volume). Escondido até o vídeo poder tocar; arquivo que o
/// AVFoundation não abre vira "Não deu para abrir o vídeo agora". O quadro
/// parado (miniatura) fica por cima do vídeo e embaixo dos controles até o
/// tempo andar, então o primeiro instante não pisca preto. O `VideoPlayer` do
/// SwiftUI derruba o harness de snapshot (compilado com swiftc, não acha o
/// `AVPlayerView` ao montar a view); o AppKit direto não.
private struct WAPlayerDeVideo: NSViewRepresentable {
    let player: AVPlayer
    let quadroParado: NSImage?
    let falhou: () -> Void

    final class Coordinator {
        var status: NSKeyValueObservation?
        var tempo: Any?
        weak var player: AVPlayer?
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> AVPlayerView {
        let v = AVPlayerView()
        v.controlsStyle = .inline
        v.videoGravity = .resizeAspect
        v.player = player
        v.isHidden = true
        let falhou = falhou
        let c = context.coordinator
        c.player = player
        c.status = player.currentItem?.observe(\.status, options: [.initial, .new]) { item, _ in
            let status = item.status
            DispatchQueue.main.async {
                v.isHidden = status != .readyToPlay
                if status == .failed { falhou() }
            }
        }
        if let quadroParado, let overlay = v.contentOverlayView {
            let poster = NSImageView(image: quadroParado)
            poster.imageScaling = .scaleProportionallyUpOrDown
            poster.frame = overlay.bounds
            poster.autoresizingMask = [.width, .height]
            overlay.addSubview(poster)
            c.tempo = player.addPeriodicTimeObserver(forInterval: CMTime(value: 1, timescale: 10),
                                                     queue: .main) { [weak poster] t in
                if t.seconds > 0.1 { poster?.removeFromSuperview() }
            }
        }
        return v
    }

    func updateNSView(_ v: AVPlayerView, context: Context) {}

    static func dismantleNSView(_ v: AVPlayerView, coordinator: Coordinator) {
        coordinator.status = nil
        if let tempo = coordinator.tempo { coordinator.player?.removeTimeObserver(tempo) }
        coordinator.tempo = nil
    }
}

/// Botão do topo do visualizador: 22 pt, canto 8, fundo branco 8% (15% no
/// hover), como os de reagir e citar ao lado da bolha.
private struct WABotaoDoVisualizador: View {
    let icone: String
    let ajuda: String
    let ativo: Bool
    let acao: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: acao) {
            Image(systemName: icone)
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(ativo ? 0.85 : 0.35))
                .frame(width: 22, height: 22)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(.white.opacity(hover && ativo ? 0.15 : 0.08)))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!ativo)
        .onHover { hover = $0 }
        .help(ajuda)
        .accessibilityLabel(ajuda)
    }
}
