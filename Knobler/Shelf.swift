//
//  Shelf.swift
//  Knobler
//
//  Prateleira de arquivos: arraste pro notch (expande sozinho ao aproximar),
//  os itens ficam no card expandido e saem arrastando de volta pro Finder.
//  ponytail: persiste paths em UserDefaults (app não é sandboxed) —
//  bookmarks security-scoped só se um dia sandboxar.
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers

final class ShelfStore: ObservableObject {
    @Published private(set) var items: [URL] = [] {
        didSet { UserDefaults.standard.set(items.map(\.path), forKey: Self.storageKey) }
    }
    /// Conversão esperando confirmação. Um de cada vez: abrir outra descarta a
    /// anterior, senão duas pastas temporárias ficariam vivas sem dono na tela.
    @Published var preview: ShelfPreview?
    private static let capacity = 8
    private static let storageKey = "shelfItems"

    init() {
        let paths = UserDefaults.standard.stringArray(forKey: Self.storageKey) ?? []
        items = paths.map { URL(fileURLWithPath: $0) }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    func add(_ url: URL) {
        guard !items.contains(url) else { return }
        items.append(url)
        if items.count > Self.capacity {
            items.removeFirst(items.count - Self.capacity)
        }
    }

    func remove(_ url: URL) {
        items.removeAll { $0 == url }
    }

    func clear() {
        items.removeAll()
    }

    /// Abre o preview de uma conversão. Substitui o que estiver aberto.
    @MainActor
    func startPreview(_ url: URL, to target: ConversionTarget) {
        preview?.descartar()
        preview = ShelfPreview(source: url, target: target)
    }

    /// Grava o resultado ao lado do original e põe no shelf.
    @MainActor
    func confirmPreview() {
        guard let preview else { return }
        // só a primeira página volta pro shelf: um PDF de 30 páginas estouraria
        // a prateleira (capacidade 8) e empurraria tudo pra fora
        if let first = preview.salvar().first { add(first) }
        self.preview = nil
    }

    @MainActor
    func cancelPreview() {
        preview?.descartar()
        preview = nil
    }
}

/// Aproximou um arquivo do notch → expande na hora; soltou → entra na prateleira.
struct ShelfDropDelegate: DropDelegate {
    let shelf: ShelfStore
    let vm: NotchViewModel

    func validateDrop(info: DropInfo) -> Bool {
        info.hasItemsConforming(to: [.fileURL, .url, .plainText])
    }

    func dropEntered(info: DropInfo) {
        vm.setExpandedDirect(true)
    }

    func performDrop(info: DropInfo) -> Bool {
        let providers = info.itemProviders(for: [.fileURL, .url, .plainText])
        guard !providers.isEmpty else { return false }
        for provider in providers {
            carregar(provider)
        }
        return true
    }

    /// Decide o caminho pelo que ESTE provider registra, não por qual lista
    /// veio cheia.
    ///
    /// O motivo é o Chrome: arrastar um link de lá anuncia
    /// `com.apple.pasteboard.promised-file-url`, que conforma a `public.file-url`.
    /// Filtrar por conformidade (`itemProviders(for: [.fileURL])`) pescava o
    /// link junto, mandava pro caminho de arquivo e o `loadItem` devolvia nada —
    /// o notch abria e o link sumia sem erro. Por isso a comparação aqui é com
    /// o identificador **exato**.
    private func carregar(_ provider: NSItemProvider) {
        let tipos = provider.registeredTypeIdentifiers
        if tipos.contains(UTType.fileURL.identifier) {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier) { item, _ in
                guard let url = Self.url(from: item), url.isFileURL else { return }
                DispatchQueue.main.async { [weak shelf] in shelf?.add(url) }
            }
            return
        }
        if tipos.contains(UTType.url.identifier) {
            provider.loadItem(forTypeIdentifier: UTType.url.identifier) { item, _ in
                guard let url = Self.url(from: item), LinkBrowser.isWebLink(url) else { return }
                abrir(url)
            }
            return
        }
        guard tipos.contains(UTType.plainText.identifier) else { return }
        provider.loadItem(forTypeIdentifier: UTType.plainText.identifier) { item, _ in
            guard let texto = Self.texto(from: item),
                  !texto.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else { return }
            // texto que é só uma URL vale mais como link que como .txt
            if let url = URL(string: texto.trimmingCharacters(in: .whitespacesAndNewlines)),
               LinkBrowser.isWebLink(url) {
                abrir(url)
                return
            }
            Self.materializar(shelf) { try ShelfDrop.materializar(texto: texto) }
        }
    }

    /// O provider entrega `Data`, `URL` ou `NSURL` conforme a origem do arraste.
    private static func url(from item: NSSecureCoding?) -> URL? {
        if let url = item as? URL { return url }
        if let data = item as? Data {
            return URL(dataRepresentation: data, relativeTo: nil)
                ?? String(data: data, encoding: .utf8).flatMap(URL.init(string:))
        }
        if let texto = item as? String { return URL(string: texto) }
        return nil
    }

    private static func texto(from item: NSSecureCoding?) -> String? {
        if let texto = item as? String { return texto }
        if let data = item as? Data { return String(data: data, encoding: .utf8) }
        return nil
    }

    /// Link arrastado só abre o preview. **Não** vira item da prateleira: ela é
    /// pra arquivo que você vai usar depois, e encher de atalho de cada link
    /// espiado empurraria pra fora o que estava lá (a capacidade é 8).
    private func abrir(_ url: URL) {
        // Sem a peça instalada a ação some, calada (regra 5): o link solto
        // não vira preview nem item da prateleira (comentário acima: link
        // nunca materializa como arquivo).
        guard PluginHost.shared.estaInstalado(.previewLink) else { return }
        DispatchQueue.main.async { [vm] in
            LinkPreview.shared.abrir(url, on: vm.displayID)
            vm.setExpandedDirect(true)
            vm.pedirFoco(.link)
        }
    }

    /// Escreve fora da main (é I/O) e entra no shelf na main.
    private static func materializar(_ shelf: ShelfStore, _ escrever: @escaping () throws -> URL) {
        do {
            let url = try escrever()
            DispatchQueue.main.async { [weak shelf] in shelf?.add(url) }
        } catch {
            NSLog("knobler: não deu pra guardar o item arrastado: \(error)")
            NSSound.beep()
        }
    }
}

struct ShelfRowView: View {
    @ObservedObject var shelf: ShelfStore
    /// Foco na prateleira ao abrir o preview de conversão.
    var vm: NotchViewModel?
    /// Envio por AirDrop que reporta estado no notch. nil (harness de snapshot,
    /// que não tem AppDelegate) cai no envio mudo de sempre.
    var onAirDrop: (([URL]) -> Void)?

    private func enviar(_ urls: [URL]) {
        if let onAirDrop { onAirDrop(urls) } else { Sharing.airdrop(urls) }
    }

    var body: some View {
        if let preview = shelf.preview {
            ShelfPreviewView(preview: preview, shelf: shelf)
        } else {
            grade
        }
    }

    private var grade: some View {
        HStack(spacing: 14) {
            ForEach(shelf.items, id: \.self) { url in
                shelfItem(url)
            }
            Spacer(minLength: 0)
            Button("Limpar") { shelf.clear() }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.45))
        }
    }

    private func shelfItem(_ url: URL) -> some View {
        VStack(spacing: 3) {
            // miniatura é uma view AppKit = fonte de drag (ver ShelfThumbnailDragView)
            ShelfThumbnailDragView(url: url)
                .frame(width: 30, height: 30)
            Text(url.lastPathComponent)
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.7))
                .lineLimit(1)
                .frame(maxWidth: 58)
        }
        .overlay(alignment: .topTrailing) {
            Button {
                shelf.remove(url)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.6), .black.opacity(0.6))
            }
            .buttonStyle(.plain)
            .offset(x: 6, y: -5)
        }
        .contextMenu {
            if let link = ShelfDrop.link(de: url) {
                // "Abrir no notch" some sem a peça instalada (regra 5); "Abrir
                // no navegador" não depende dela e continua sempre disponível.
                if PluginHost.shared.estaInstalado(.previewLink) {
                    Button("Abrir no notch") {
                        LinkPreview.shared.abrir(link, on: vm?.displayID)
                        vm?.focar(.link)
                    }
                }
                Button("Abrir no navegador") { NSWorkspace.shared.open(link) }
                Divider()
            }
            let targets = FileConverter.targets(for: url)
            if !targets.isEmpty {
                Menu("Converter") {
                    ForEach(targets, id: \.self) { target in
                        Button(target.label) {
                            shelf.startPreview(url, to: target)
                            vm?.focar(.shelf)
                        }
                    }
                }
            }
            Menu("Compartilhar") {
                Button("Enviar por AirDrop") { enviar([url]) }
                Button("Compartilhar…") { Sharing.share([url]) }
                if shelf.items.count > 1 {
                    Divider()
                    Button("Enviar tudo por AirDrop (\(shelf.items.count))") {
                        enviar(shelf.items)
                    }
                }
            }
            Divider()
            Button("Mostrar no Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([url])
            }
            Button("Remover do shelf") { shelf.remove(url) }
        }
        .transition(.blurReplace)
    }

}
