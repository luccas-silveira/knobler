//
//  MessageStore.swift
//  Knobler
//
//  Histórico das Mensagens LAN: últimas 20 por peer (JSON em App Support) +
//  cache das fotos dos peers (arquivos .jpg) + nomes conhecidos.
//

import AppKit
import Foundation

final class MessageStore: ObservableObject {
    /// peerID → últimas mensagens (mais antiga → mais nova).
    @Published private(set) var threads: [String: [PeerMessage]] = [:]
    /// peerID → último nome visto (pra rotular histórico com o peer offline).
    @Published private(set) var names: [String: String] = [:]

    private static let maxPerPeer = 20
    private var saveWork: DispatchWorkItem?

    private var baseDir: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Knobler", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
    private var threadsURL: URL { baseDir.appendingPathComponent("messages.json") }
    private var namesURL: URL { baseDir.appendingPathComponent("peerNames.json") }
    private var avatarsDir: URL {
        let dir = baseDir.appendingPathComponent("avatars", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
    private var mediaDir: URL {
        let dir = baseDir.appendingPathComponent("media", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    init() {
        if let data = try? Data(contentsOf: threadsURL),
           let decoded = try? JSONDecoder().decode([String: [PeerMessage]].self, from: data) {
            threads = decoded
        }
        if let data = try? Data(contentsOf: namesURL),
           let decoded = try? JSONDecoder().decode([String: String].self, from: data) {
            names = decoded
        }
    }

    func messages(for peerID: String) -> [PeerMessage] { threads[peerID] ?? [] }

    func append(_ msg: PeerMessage) {
        var list = threads[msg.peerID] ?? []
        list.append(msg)
        if list.count > Self.maxPerPeer {
            // some do histórico → o arquivo da foto/GIF vai junto (sem órfãos no disco)
            let dropped = list.prefix(list.count - Self.maxPerPeer)
            for old in dropped {
                if let url = old.mediaFile.flatMap(mediaURL) { try? FileManager.default.removeItem(at: url) }
            }
            list.removeFirst(list.count - Self.maxPerPeer)
        }
        threads[msg.peerID] = list
        scheduleSave()
    }

    // MARK: Fotos/GIFs das mensagens

    /// Grava o anexo e devolve o nome do arquivo (nome sempre gerado aqui —
    /// nada vindo da rede vira caminho).
    func saveMedia(_ data: Data, ext: String) -> String? {
        let name = "\(UUID().uuidString).\(ext)"
        guard (try? data.write(to: mediaDir.appendingPathComponent(name))) != nil else { return nil }
        return name
    }

    func mediaURL(_ file: String) -> URL? {
        guard file == (file as NSString).lastPathComponent, !file.hasPrefix(".") else { return nil }
        return mediaDir.appendingPathComponent(file)
    }

    func name(for peerID: String) -> String? { names[peerID] }

    func rememberName(_ name: String, for peerID: String) {
        guard names[peerID] != name else { return }
        names[peerID] = name
        scheduleSave()
    }

    /// Caminho do arquivo de foto — só pra peerID em formato UUID canônico.
    /// Defesa estrutural contra path-traversal: o peerID vem da rede e vira nome
    /// de arquivo; sem UUID válido, `nil` (não escreve/lê fora do diretório).
    private func avatarFile(for peerID: String) -> URL? {
        guard UUID(uuidString: peerID) != nil else { return nil }
        return avatarsDir.appendingPathComponent("\(peerID).jpg")
    }

    func cacheAvatar(_ jpeg: Data, for peerID: String) {
        guard let url = avatarFile(for: peerID) else { return }
        try? jpeg.write(to: url)
        objectWillChange.send()
    }

    func avatar(for peerID: String) -> NSImage? {
        avatarFile(for: peerID).flatMap { NSImage(contentsOf: $0) }
    }

    /// Peer respondeu o perfil SEM foto → ele removeu; limpa o cache local.
    func removeAvatar(for peerID: String) {
        guard let url = avatarFile(for: peerID) else { return }
        try? FileManager.default.removeItem(at: url)
        objectWillChange.send()
    }

    // ponytail: debounce simples de 1s; some flush no quit se virar problema
    private func scheduleSave() {
        saveWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.save() }
        saveWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1, execute: work)
    }

    private func save() {
        if let data = try? JSONEncoder().encode(threads) { try? data.write(to: threadsURL) }
        if let data = try? JSONEncoder().encode(names) { try? data.write(to: namesURL) }
    }

    /// Grava agora (chamado no encerramento do app) — fecha a janela do debounce.
    func flush() {
        saveWork?.cancel()
        saveWork = nil
        save()
    }
}
