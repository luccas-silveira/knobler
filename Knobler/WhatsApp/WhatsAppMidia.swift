import Foundation
import os

// Mídia do WhatsApp do lado do Knobler: cache descartável do que a ponte serve
// (`GET /v1/midia`, docs/whatsapp-ponte.md:493-507), recuperação única da mídia
// expirada (`POST /v1/midia/recuperar`, :509-519) e o preparo do anexo que sai
// por `POST /v1/enviar/midia` (:598-625). O cache pode ser apagado a qualquer
// hora: o que falta volta da ponte na próxima vez.

private let log = Logger(subsystem: "com.zoi.knobler", category: "whatsapp")

enum WAResultadoMidia: Equatable {
    case arquivo(URL)
    /// `410 midia_expirada`: a recuperação foi pedida e o resultado chega pelo evento `midia`.
    case aguardando
    /// O celular não conseguiu reenviar (evento `midia` com `ok: false`).
    case indisponivel
    case contaDesconectada
    case falhou
}

@MainActor
final class WAMidiaCache {
    nonisolated static var raizPadrao: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("com.zoi.knobler/whatsapp", isDirectory: true)
    }

    private enum Recuperacao { case aguardando, indisponivel }

    private let raiz: URL
    private let cliente: WACliente
    /// Mídias expiradas desta sessão, por `conta|conversa|id`.
    private var recuperacoes: [String: Recuperacao] = [:]
    /// ponytail: miniatura é pequena (alguns KB) e só vive enquanto o app roda;
    /// sem limite de contagem.
    private var miniaturas: [String: Data] = [:]
    /// `404 sem_miniatura`: não pede de novo na mesma sessão.
    private var semMiniatura: Set<String> = []

    init(raiz: URL = WAMidiaCache.raizPadrao, cliente: WACliente) {
        self.raiz = raiz
        self.cliente = cliente
    }

    /// `<raiz>/<conta>/<chat com : → _>/<id saneado>.<ext>`, a mesma regra de
    /// nome da ponte (docs/whatsapp-ponte.md:195-198). Não mexe no disco.
    func caminho(chave: WAChave, mensagem: WAMensagem) -> URL {
        let chat = chave.jid.replacingOccurrences(of: ":", with: "_")
        let nome = Self.saneado(mensagem.id) + "." + Self.extensao(de: mensagem)
        return raiz
            .appendingPathComponent(Self.saneado(chave.conta), isDirectory: true)
            .appendingPathComponent(chat.replacingOccurrences(of: "/", with: "_"), isDirectory: true)
            .appendingPathComponent(nome, isDirectory: false)
    }

    /// Do disco se já está no cache; senão baixa da ponte e grava. `410` pede a
    /// recuperação uma vez só e fica `.aguardando` até o evento `midia`.
    func arquivo(chave: WAChave, mensagem: WAMensagem) async -> WAResultadoMidia {
        let destino = caminho(chave: chave, mensagem: mensagem)
        if FileManager.default.fileExists(atPath: destino.path) { return .arquivo(destino) }

        let id = Self.id(chave, mensagem.id)
        switch recuperacoes[id] {
        case .aguardando?: return .aguardando
        case .indisponivel?: return .indisponivel
        case nil: break
        }

        do {
            let r = try await cliente.midia(conta: chave.conta, conversa: chave.jid, id: mensagem.id, miniatura: false)
            try await Self.gravar(r.dados, em: destino, raiz: raiz)
            return .arquivo(destino)
        } catch let erro as WAErroDoCliente where erro.midiaExpirada {
            return await recuperar(chave: chave, mensagem: mensagem, id: id)
        } catch let erro as WAErroDoCliente where erro.contaDesconectada {
            return .contaDesconectada
        } catch {
            log.error("WhatsApp: mídia não baixada — \(String(describing: error), privacy: .public)")
            return .falhou
        }
    }

    /// Marca antes do pedido: duas telas pedindo juntas não recuperam duas vezes.
    /// Se o pedido nem sai (ponte caiu), desmarca e a próxima chamada tenta de novo.
    private func recuperar(chave: WAChave, mensagem: WAMensagem, id: String) async -> WAResultadoMidia {
        if let r = recuperacoes[id] { return r == .aguardando ? .aguardando : .indisponivel }
        recuperacoes[id] = .aguardando
        do {
            try await cliente.recuperarMidia(conta: chave.conta, conversa: chave.jid, id: mensagem.id)
            return .aguardando
        } catch {
            log.error("WhatsApp: recuperação de mídia não pedida — \(String(describing: error), privacy: .public)")
            if recuperacoes[id] == .aguardando { recuperacoes[id] = nil }
            return .falhou
        }
    }

    /// Evento `midia`: `ok` libera o próximo download; senão a mídia fica indisponível.
    func recuperou(chave: WAChave, alvo: String, ok: Bool) {
        recuperacoes[Self.id(chave, alvo)] = ok ? nil : .indisponivel
    }

    /// Miniatura embutida na mensagem (`miniatura=1`), guardada em memória.
    func miniatura(chave: WAChave, mensagem: WAMensagem) async -> Data? {
        let id = Self.id(chave, mensagem.id)
        if let d = miniaturas[id] { return d }
        guard !semMiniatura.contains(id) else { return nil }
        do {
            let r = try await cliente.midia(conta: chave.conta, conversa: chave.jid, id: mensagem.id, miniatura: true)
            miniaturas[id] = r.dados
            return r.dados
        } catch WAErroDoCliente.ponte(404, "sem_miniatura", _) {
            semMiniatura.insert(id)
            return nil
        } catch {
            log.error("WhatsApp: miniatura não lida — \(String(describing: error), privacy: .public)")
            return nil
        }
    }

    /// Só snapshot: a miniatura já em memória, sem pedir à ponte.
    func _injetarMiniatura(_ dados: Data, chave: WAChave, mensagem: WAMensagem) {
        miniaturas[Self.id(chave, mensagem.id)] = dados
    }

    /// Só snapshot: a mídia já pedida ao celular (`.aguardando`), sem a ponte.
    func _marcarAguardando(chave: WAChave, mensagem: WAMensagem) {
        recuperacoes[Self.id(chave, mensagem.id)] = .aguardando
    }

    // MARK: - Ajudantes

    private static func id(_ k: WAChave, _ mensagem: String) -> String {
        "\(k.conta)|\(k.jid)|\(mensagem)"
    }

    /// Tudo fora de `[A-Za-z0-9_-]` vira `_`.
    nonisolated static func saneado(_ s: String) -> String {
        String(s.map { c -> Character in
            guard c.isASCII, c.isLetter || c.isNumber || c == "_" || c == "-" else { return "_" }
            return c
        })
    }

    private static let extensoes: [String: String] = [
        "audio/ogg": "ogg", "audio/mpeg": "mp3", "audio/mp4": "m4a", "audio/aac": "aac",
        "image/jpeg": "jpg", "image/png": "png", "image/webp": "webp", "image/gif": "gif",
        "video/mp4": "mp4", "video/quicktime": "mov", "video/3gpp": "3gp",
        "application/pdf": "pdf", "text/plain": "txt",
    ]

    /// Do nome original; sem extensão nele, do mimetype (sem os parâmetros); senão `bin`.
    private static func extensao(de m: WAMensagem) -> String {
        if let nome = m.midia?.nome {
            let ext = saneado((nome as NSString).pathExtension.lowercased())
            if !ext.isEmpty { return ext }
        }
        let mime = m.midia?.mimetype.split(separator: ";").first
            .map { $0.trimmingCharacters(in: .whitespaces).lowercased() } ?? ""
        return extensoes[mime] ?? "bin"
    }

    /// Grava fora da main: cria as pastas que faltam com 0700 e escreve atômico.
    private static func gravar(_ dados: Data, em destino: URL, raiz: URL) async throws {
        try await Task.detached(priority: .utility) {
            let fm = FileManager.default
            let chat = destino.deletingLastPathComponent()
            for pasta in [raiz, chat.deletingLastPathComponent(), chat] where !fm.fileExists(atPath: pasta.path) {
                try fm.createDirectory(at: pasta, withIntermediateDirectories: true,
                                       attributes: [.posixPermissions: 0o700])
                try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: pasta.path)
            }
            try dados.write(to: destino, options: .atomic)
        }.value
    }
}

/// Anexo que sai por `POST /v1/enviar/midia`. A ponte confere o tipo pela
/// extensão (docs/whatsapp-ponte.md:617-621) e lê o arquivo antes de responder.
enum WAAnexo {
    static let limite = 100 * 1024 * 1024

    static func tipo(paraArquivo url: URL) -> String {
        switch url.pathExtension.lowercased() {
        case "jpg", "jpeg", "png", "webp": return "imagem"
        case "mp4", "mov": return "video"
        default: return "documento"
        }
    }

    /// Copia para `<pasta>/<UUID>.<ext>` (pasta 0700) e devolve o caminho
    /// absoluto da cópia. O original não é tocado.
    static func prepararEnvio(_ url: URL, pasta: URL) throws -> URL {
        let fm = FileManager.default
        try fm.createDirectory(at: pasta, withIntermediateDirectories: true,
                               attributes: [.posixPermissions: 0o700])
        try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: pasta.path)
        var nome = UUID().uuidString
        if !url.pathExtension.isEmpty { nome += "." + url.pathExtension }
        let copia = pasta.appendingPathComponent(nome, isDirectory: false).standardizedFileURL
        try fm.copyItem(at: url, to: copia)
        return copia
    }
}
