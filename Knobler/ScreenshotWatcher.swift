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
    private var startedAt = Date()

    func start() {
        guard query == nil else { return }
        let query = NSMetadataQuery()
        // capturas de tela que são imagem (kMDItemIsScreenCapture só existe em
        // itens gerados pela captura do sistema)
        query.predicate = NSPredicate(
            format: "kMDItemIsScreenCapture == 1 && kMDItemContentTypeTree == %@",
            "public.image")
        query.searchScopes = [NSMetadataQueryLocalComputerScope]
        // Ordena o resultado; a data ainda precisa ser validada nos updates.
        query.sortDescriptors = [NSSortDescriptor(key: kMDItemFSCreationDate as String,
                                                  ascending: false)]

        NotificationCenter.default.addObserver(
            self, selector: #selector(finishedGathering),
            name: .NSMetadataQueryDidFinishGathering, object: query)
        NotificationCenter.default.addObserver(
            self, selector: #selector(updated),
            name: .NSMetadataQueryDidUpdate, object: query)

        gathered = false
        startedAt = Date()
        query.start()
        self.query = query
    }

    func stop() {
        guard let query else { return }
        query.stop()
        NotificationCenter.default.removeObserver(self, name: .NSMetadataQueryDidFinishGathering, object: query)
        NotificationCenter.default.removeObserver(self, name: .NSMetadataQueryDidUpdate, object: query)
        self.query = nil
        gathered = false
    }

    @objc private func finishedGathering(_: Notification) {
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
            // "Adicionado" ao Spotlight não significa recém-criado: reindexação
            // e discos que voltam a ficar disponíveis também trazem itens antigos.
            let createdAt = item.value(forAttribute: kMDItemFSCreationDate as String) as? Date
            guard Self.isNewScreenshot(path: path, createdAt: createdAt, since: startedAt)
            else { continue }
            let url = URL(fileURLWithPath: path)
            // Arquivos e Pastas não expõe status: o Spotlight devolve o path
            // mesmo sem acesso, e só a leitura revela se o TCC deixa. O painel
            // de Permissões lê esse registro.
            // ponytail: access(2) basta pro caso comum (Desktop/Documentos);
            // se aparecer falso-positivo, trocar por uma leitura mapeada.
            Permission.record(.arquivos,
                              worked: FileManager.default.isReadableFile(atPath: path))
            DispatchQueue.main.async { [weak self] in
                // Desligar/religar a captura invalida entregas da consulta anterior.
                guard let self, self.query === query else { return }
                self.onScreenshot?(url)
            }
        }
    }

    static func isNewScreenshot(path: String, createdAt: Date?, since start: Date) -> Bool {
        guard let createdAt, createdAt >= start else { return false }
        // Ignora o arquivo temporário oculto que o screencapture cria ao gravar.
        return !(path as NSString).lastPathComponent.hasPrefix(".")
    }

    deinit { stop() }
}
