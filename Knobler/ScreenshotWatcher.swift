//
//  ScreenshotWatcher.swift
//  Knobler
//
//  Observa capturas de tela do macOS via Spotlight (NSMetadataQuery) e
//  emite a URL de cada captura NOVA. Pega em qualquer pasta configurada
//  (⌘⇧5 → "Salvar em"), sem polling nem ler com.apple.screencapture.
//  ponytail: só imagens — gravações de tela (.mov) também têm o atributo
//  de captura mas não cabem na prateleira.
//

import Foundation

final class ScreenshotWatcher {
    /// URL de uma captura nova (arquivo já gravado). Sempre na main queue.
    var onScreenshot: ((URL) -> Void)?

    private var query: NSMetadataQuery?
    /// O primeiro resultado do query traz TODAS as capturas antigas do índice;
    /// só emitimos depois desse gathering — senão o shelf enche de histórico.
    private var gathered = false

    func start() {
        guard query == nil else { return }
        let query = NSMetadataQuery()
        // capturas de tela que são imagem (kMDItemIsScreenCapture só existe em
        // itens gerados pela captura do sistema)
        query.predicate = NSPredicate(
            format: "kMDItemIsScreenCapture == 1 && kMDItemContentTypeTree == %@",
            "public.image")
        query.searchScopes = [NSMetadataQueryLocalComputerScope]
        // mais recentes primeiro: o item [0] após um update é a captura nova
        query.sortDescriptors = [NSSortDescriptor(key: kMDItemFSCreationDate as String,
                                                  ascending: false)]

        NotificationCenter.default.addObserver(
            self, selector: #selector(finishedGathering),
            name: .NSMetadataQueryDidFinishGathering, object: query)
        NotificationCenter.default.addObserver(
            self, selector: #selector(updated),
            name: .NSMetadataQueryDidUpdate, object: query)

        gathered = false
        query.start()
        self.query = query
    }

    func stop() {
        guard let query else { return }
        query.stop()
        NotificationCenter.default.removeObserver(self, name: .NSMetadataQueryDidFinishGathering, object: query)
        NotificationCenter.default.removeObserver(self, name: .NSMetadataQueryDidUpdate, object: query)
        self.query = nil
    }

    @objc private func finishedGathering(_ note: Notification) {
        // marca o baseline: capturas já existentes não entram no shelf
        gathered = true
    }

    @objc private func updated(_ note: Notification) {
        guard gathered, let query else { return }
        // durante o processamento do update o query precisa ficar "parado"
        query.disableUpdates()
        defer { query.enableUpdates() }

        // itens adicionados nesta atualização (chave presente a partir do macOS 10.9)
        let added = note.userInfo?[kMDQueryUpdateAddedItems as String] as? [NSMetadataItem]
        guard let added, !added.isEmpty else { return }

        for item in added {
            guard let path = item.value(forAttribute: kMDItemPath as String) as? String
            else { continue }
            // ignora o arquivo temporário "." que o screencapture cria antes de gravar
            guard !(path as NSString).lastPathComponent.hasPrefix(".") else { continue }
            let url = URL(fileURLWithPath: path)
            DispatchQueue.main.async { [weak self] in
                self?.onScreenshot?(url)
            }
        }
    }

    deinit { stop() }
}
