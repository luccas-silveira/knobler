import AppKit
import Combine
import os

// Foto de perfil do WhatsApp (`GET /v1/foto`, docs/whatsapp-ponte.md:524-535).
// Carregador próprio, com a chave da ponte: o `RemoteAvatarLoader` recusa http
// e loopback de propósito (é a guarda do webhook) e continua assim. Daqui só se
// reaproveita o que ele tem de público: a miniatura e o teto do cache.

private let log = Logger(subsystem: "com.zoi.knobler", category: "whatsapp")

@MainActor
final class WAFotoCache {
    static let shared = WAFotoCache()
    static let limite = RemoteAvatarLoader.limiteDoCache
    /// Janela em que a foto (ou a falta dela) vale sem perguntar à ponte.
    static let validade: TimeInterval = 10 * 60

    private struct Entrada {
        var etag: String?
        var quando: Date
        var semFoto: Bool
    }

    private let cliente: WACliente
    private let agora: () -> Date
    /// Miniaturas por `conta|jid`, com o mesmo teto do loader do webhook.
    private let imagens: NSCache<NSString, NSImage> = {
        let c = NSCache<NSString, NSImage>()
        c.countLimit = WAFotoCache.limite
        return c
    }()
    /// ponytail: metadado de poucos bytes por (conta, jid) visto na sessão; sem teto.
    private var entradas: [String: Entrada] = [:]
    /// Pedido em voo por chave: várias views pedindo o mesmo JID esperam o mesmo.
    private var emVoo: [String: Task<NSImage?, Never>] = [:]

    init(cliente: WACliente = WACliente(), agora: @escaping () -> Date = Date.init) {
        self.cliente = cliente
        self.agora = agora
    }

    func imagem(conta: String, jid: String) async -> NSImage? {
        let chave = "\(conta)|\(jid)"
        let guardada = imagens.object(forKey: chave as NSString)
        if let e = entradas[chave], agora().timeIntervalSince(e.quando) < Self.validade,
           e.semFoto || guardada != nil {
            return e.semFoto ? nil : guardada
        }
        if let tarefa = emVoo[chave] { return await tarefa.value }

        // ETag só quando há imagem para manter: sem ela o 304 não teria o que devolver.
        let etag = guardada == nil ? nil : entradas[chave]?.etag
        let tarefa = Task { await self.buscar(chave: chave, conta: conta, jid: jid, etag: etag, guardada: guardada) }
        emVoo[chave] = tarefa
        let img = await tarefa.value
        emVoo[chave] = nil
        return img
    }

    private func buscar(chave: String, conta: String, jid: String, etag: String?,
                        guardada: NSImage?) async -> NSImage? {
        do {
            switch try await cliente.foto(conta: conta, jid: jid, etag: etag) {
            case let .nova(dados, novaEtag):
                guard let cg = RemoteAvatarLoader.miniatura(de: dados) else {
                    log.error("foto de perfil: a ponte devolveu bytes que não são imagem")
                    return guardada
                }
                let img = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
                imagens.setObject(img, forKey: chave as NSString)
                entradas[chave] = Entrada(etag: novaEtag, quando: agora(), semFoto: false)
                return img
            case .igual:
                entradas[chave]?.quando = agora()
                return guardada
            case .semFoto:
                imagens.removeObject(forKey: chave as NSString)
                entradas[chave] = Entrada(etag: nil, quando: agora(), semFoto: true)
                return nil
            }
        } catch WAErroDoCliente.semChave {
            return nil
        } catch {
            // ponytail: ponte fora do ar ou erro passageiro; a próxima view tenta de novo.
            log.error("foto de perfil falhou: \(String(describing: error), privacy: .public)")
            return guardada
        }
    }
}

/// O que as views observam: a foto de um (conta, jid), carregada pelo cache compartilhado.
@MainActor
final class WAFotoLoader: ObservableObject {
    @Published private(set) var imagem: NSImage?

    private var tarefa: Task<Void, Never>?
    private var atual: String?

    func carregar(conta: String, jid: String) {
        let chave = "\(conta)|\(jid)"
        // Outra pessoa: some a foto anterior enquanto carrega (sem foto trocada).
        if chave != atual { imagem = nil }
        atual = chave
        tarefa?.cancel()
        tarefa = Task { [weak self] in
            let img = await WAFotoCache.shared.imagem(conta: conta, jid: jid)
            guard let self, !Task.isCancelled, self.atual == chave else { return }
            self.imagem = img
        }
    }
}
