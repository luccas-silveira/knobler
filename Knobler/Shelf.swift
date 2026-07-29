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
}

/// Aproximou um arquivo do notch → expande na hora; soltou → entra na prateleira.
struct ShelfDropDelegate: DropDelegate {
    let shelf: ShelfStore
    let vm: NotchViewModel

    func validateDrop(info: DropInfo) -> Bool {
        info.hasItemsConforming(to: [.fileURL])
    }

    func dropEntered(info: DropInfo) {
        vm.setExpandedDirect(true)
    }

    func performDrop(info: DropInfo) -> Bool {
        let providers = info.itemProviders(for: [.fileURL])
        guard !providers.isEmpty else { return false }
        for provider in providers {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier) { item, _ in
                guard let data = item as? Data,
                      let url = URL(dataRepresentation: data, relativeTo: nil)
                else { return }
                DispatchQueue.main.async { [weak shelf] in
                    shelf?.add(url)
                }
            }
        }
        return true
    }
}

struct ShelfRowView: View {
    @ObservedObject var shelf: ShelfStore
    /// Só pra faixa de progresso da conversão de vídeo — o resto do shelf não
    /// precisa do view model.
    var vm: NotchViewModel?

    var body: some View {
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
            let targets = FileConverter.targets(for: url)
            if !targets.isEmpty {
                Menu("Converter") {
                    ForEach(targets, id: \.self) { target in
                        Button(target.label) { convert(url, to: target) }
                    }
                }
            }
            Menu("Compartilhar") {
                Button("Enviar por AirDrop") { Sharing.airdrop([url]) }
                Button("Compartilhar…") { Sharing.share([url]) }
                if shelf.items.count > 1 {
                    Divider()
                    Button("Enviar tudo por AirDrop (\(shelf.items.count))") {
                        Sharing.airdrop(shelf.items)
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

    /// Converte fora da main e coloca o resultado no shelf — o original fica.
    /// Vídeo demora, então ocupa a faixa de atividade do notch enquanto roda.
    /// Falha: beep e log, sem card de erro.
    private func convert(_ url: URL, to target: ConversionTarget) {
        // ponytail: a faixa de atividade é um slot só, compartilhado com a API
        // local — uma conversão longa esconde a atividade que estiver lá.
        if target.isSlow { showActivity(url, to: target, progress: 0) }
        FileConverter.convert(url, to: target) { fraction in
            if target.isSlow { showActivity(url, to: target, progress: fraction) }
        } completion: { result in
            if target.isSlow { vm?.activity = nil }
            switch result {
            case .success(let out):
                shelf.add(out)
            case .failure(let error):
                NSLog("knobler: conversão falhou (\(url.lastPathComponent)): \(error)")
                NSSound.beep()
            }
        }
    }

    private func showActivity(_ url: URL, to target: ConversionTarget, progress: Double) {
        vm?.activity = NotchActivity(
            id: "conversao",
            title: "Convertendo para \(target.label)",
            detail: url.lastPathComponent,
            progress: progress > 0 ? progress : nil,
            updatedAt: Date())
    }
}
