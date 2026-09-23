//
//  AirDropCoordenador.swift
//  Knobler
//
//  Junta envio e recebimento num estado só e traduz pro notch: atividade (anel)
//  durante, card com miniatura e ações no fim. O AppDelegate só liga.
//

import AppKit

final class AirDropCoordenador {
    private let shelf: ShelfStore
    private let onActivity: (NotchActivity?) -> Void
    private let onCard: (NotchNotification) -> Void
    private let progresso = AirDropProgresso()
    private var recebimento = AirDropRecebimentoEstado()
    /// arquivos por card vivo; o índice do botão escolhe a ação
    private var acoes: [UUID: (urls: [URL], recebido: Bool)] = [:]

    init(shelf: ShelfStore,
         onActivity: @escaping (NotchActivity?) -> Void,
         onCard: @escaping (NotchNotification) -> Void) {
        self.shelf = shelf; self.onActivity = onActivity; self.onCard = onCard
    }

    func iniciar() {
        progresso.onFracao = { [weak self] url, f in
            guard let self else { return }
            self.recebimento.atualizar(url, fracao: f)
            self.onActivity(NotchActivity(
                id: "airdrop", title: AirDropTexto.atividadeRecebendo(),
                detail: self.recebimento.rotulo ?? "", progress: self.recebimento.progresso,
                updatedAt: Date()))
        }
        progresso.onFim = { [weak self] url in
            guard let self, let fim = self.recebimento.encerrar(url) else { return }
            self.onActivity(nil)
            if case .recebido(let urls) = fim { self.cardFinal(urls: urls, recebido: true, titulo: "Recebido") }
        }
        progresso.iniciar()
    }

    func enviar(_ urls: [URL]) { AirDropEnvio.enviar(urls) { [weak self] in self?.aplicar($0) } }
    func enviarDoPainel() { AirDropEnvio.enviarDoPainel { [weak self] in self?.aplicar($0) } }

    private func aplicar(_ estado: AirDropState) {
        switch estado {
        case .enviando(let label, let destino):
            onActivity(NotchActivity(id: "airdrop", title: AirDropTexto.atividadeEnviando(destino: destino),
                                     detail: label, progress: nil, updatedAt: Date()))
        case .enviado(_, let destino, let urls):
            onActivity(nil)
            cardFinal(urls: urls, recebido: false, titulo: AirDropTexto.cardEnviado(destino: destino))
        case .cancelado:
            onActivity(nil)
        case .falhou(let motivo):
            onActivity(nil)
            onCard(NotchNotification(appName: "AirDrop", title: "Não deu pra enviar",
                                     body: motivo, iconEmoji: "📤"))
        }
    }

    private func cardFinal(urls: [URL], recebido: Bool, titulo: String) {
        let token = UUID()
        acoes[token] = (urls, recebido)
        // ponytail: teto simples; card que some sem clique deixaria a entrada viva
        if acoes.count > 8, let velho = acoes.keys.first(where: { $0 != token }) { acoes[velho] = nil }
        var n = NotchNotification(appName: "AirDrop", title: titulo,
                                  body: AirDropRegras.rotulo(urls),
                                  iconEmoji: recebido ? "📥" : "📤",
                                  revealsDownloads: recebido)
        n.thumbnail = urls.first.flatMap(ShelfPreview.thumbnail(of:))
        n.actionTitles = recebido ? AirDropTexto.acoesRecebido : AirDropTexto.acoesEnviado
        n.actionToken = token
        onCard(n)
    }

    func perform(token: UUID, index: Int) -> Bool {
        guard let entrada = acoes.removeValue(forKey: token) else { return false }
        // arquivo pode ter sido movido/apagado enquanto o card estava na tela
        let urls = Sharing.existing(entrada.urls)
        guard !urls.isEmpty else { NSSound.beep(); return true }
        let titulos = entrada.recebido ? AirDropTexto.acoesRecebido : AirDropTexto.acoesEnviado
        switch titulos.indices.contains(index) ? titulos[index] : "" {
        case "Abrir": urls.forEach { NSWorkspace.shared.open($0) }
        case "Mostrar no Finder": NSWorkspace.shared.activateFileViewerSelecting(urls)
        case "Prateleira": shelf.add(urls)
        default: break
        }
        return true
    }
}
