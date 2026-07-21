//
//  LANMessaging.swift
//  Knobler
//
//  Mensagens LAN: anuncia/descobre `_knobler._tcp` via Bonjour e troca
//  pacotes emoldurados (ver Wire.swift) por conexões efêmeras. Separado do
//  NotchAPIServer (localhost) — a API de automação não é exposta à rede.
//

import Foundation
import Network

final class LANMessaging: ObservableObject {
    static let serviceType = "_knobler._tcp"
    /// Teto de uma troca (conexão efêmera) — dimensionado pelo anexo, não pelo texto.
    private static let timeout: TimeInterval = 20

    @Published private(set) var peers: [Peer] = []

    /// Usado pelo harness de renderização offline (tools/main.swift) — evita
    /// subir Bonjour real.
    func injectPreview(peers: [Peer]) {
        self.peers = peers
    }

    /// Rede Local negada pelo usuário (kDNSServiceErr_PolicyDenied -65570).
    @Published private(set) var permissionDenied = false

    /// App fornece o próprio perfil (id/nome/foto) pra anunciar e responder `profile`.
    var profileProvider: (() -> PeerProfile)?
    /// Mensagem recebida (já validada) → app grava/mostra. `media` = anexo cru
    /// já validado (bytes + tipo); o app decide onde gravar.
    var onIncoming: ((PeerMessage, PeerProfile?, (Data, MediaKind)?) -> Void)?

    private var listener: NWListener?
    private var browser: NWBrowser?

    // MARK: Ciclo de vida

    func start() {
        guard listener == nil else { return }
        permissionDenied = false   // dá nova chance: usuário pode ter concedido desde a última negação
        startListener()
        startBrowser()
    }

    func stop() {
        listener?.cancel(); listener = nil
        browser?.cancel(); browser = nil
        peers = []
    }

    func peer(withID id: String) -> Peer? { peers.first { $0.id == id } }

    /// Re-anuncia com o perfil atual (usuário mudou nome/foto nos Ajustes) —
    /// só se já estamos anunciando. O nome novo aparece na lista dos outros
    /// sem precisar reiniciar o app.
    func refreshIdentity() {
        guard listener != nil else { return }
        listener?.cancel()
        listener = nil
        startListener()
    }

    var diagnostics: [String: Any] {
        ["peers": peers.count, "permissionDenied": permissionDenied]
    }

    // MARK: Anúncio (listener)

    private func startListener() {
        guard let profile = profileProvider?() else { return }
        let listener = try? NWListener(using: .tcp)
        guard let listener else { return }
        var txt = NWTXTRecord()
        txt["id"] = profile.id
        txt["name"] = profile.name
        listener.service = NWListener.Service(
            name: profile.id, type: Self.serviceType, txtRecord: txt)
        listener.stateUpdateHandler = { [weak self] state in
            if case let .failed(err) = state { self?.noteError(err) }
        }
        listener.newConnectionHandler = { [weak self] conn in
            self?.serve(conn)
        }
        listener.start(queue: .main)
        self.listener = listener
    }

    // MARK: Descoberta (browser)

    private func startBrowser() {
        let params = NWParameters.tcp
        let browser = NWBrowser(
            for: .bonjourWithTXTRecord(type: Self.serviceType, domain: nil), using: params)
        browser.stateUpdateHandler = { [weak self] state in
            if case let .failed(err) = state { self?.noteError(err) }
        }
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            self?.updatePeers(results)
        }
        browser.start(queue: .main)
        self.browser = browser
    }

    private func updatePeers(_ results: Set<NWBrowser.Result>) {
        let myID = profileProvider?().id
        var found: [Peer] = []
        for r in results {
            // id DEVE ser um UUID canônico (nosso id é sempre UUID().uuidString).
            // Rejeitar o resto barra path-traversal no cache de foto (o id vira
            // nome de arquivo) e enchente de peers forjados de qualquer host da LAN.
            guard case let .bonjour(txt) = r.metadata,
                  let id = txt["id"], id != myID,
                  UUID(uuidString: id) != nil else { continue }
            let name = txt["name"] ?? id
            found.append(Peer(id: id, name: name, endpoint: r.endpoint))
        }
        peers = found.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    // MARK: Servir conexões de entrada

    private func serve(_ conn: NWConnection) {
        conn.start(queue: .main)
        // watchdog: peer que abre e não envia (ou trickle) não pode segurar o socket
        // pra sempre. cancel após completar/fechar é no-op — seguro.
        // 20s (e não 5) porque um GIF de alguns MB em Wi-Fi ruim leva mais que isso.
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.timeout) { conn.cancel() }
        receiveFrame(on: conn) { [weak self] packet in
            guard let self, let packet else { conn.cancel(); return }
            switch packet {
            case .profileRequest:
                let p = self.profileProvider?() ?? PeerProfile(id: "", name: "?", avatarJPEG: nil)
                self.sendFrame(.profileResponse(id: p.id, name: p.name, avatar: p.avatarJPEG),
                               on: conn, close: true)
            case let .message(id, from, fromName, text, reply, media, mime):
                // `from` vira chave de arquivo (histórico/foto) — exige UUID canônico
                // (mesma defesa do updatePeers). Remetente forjado é descartado.
                guard UUID(uuidString: from) != nil else { conn.cancel(); return }
                // anexo só passa se os bytes forem mesmo jpeg/png/gif e casarem
                // com o mime declarado; caso contrário vira mensagem só de texto.
                let attachment = media.flatMap { data in
                    MediaKind.validate(data, mime: mime).map { (data, $0) }
                }
                let clipped = String(text.prefix(2000))
                let msg = PeerMessage(id: id, peerID: from, incoming: true,
                                      text: clipped, allowReply: reply, at: Date())
                let prof = PeerProfile(id: from, name: fromName, avatarJPEG: nil)
                DispatchQueue.main.async { self.onIncoming?(msg, prof, attachment) }
                self.sendFrame(.ack, on: conn, close: true)
            default:
                conn.cancel()
            }
        }
    }

    // MARK: Enviar

    func send(_ text: String, to peer: Peer, allowReply: Bool,
              media: (Data, MediaKind)? = nil,
              completion: @escaping (Bool) -> Void) {
        guard let me = profileProvider?() else { completion(false); return }
        let packet = Packet.message(
            id: UUID().uuidString, from: me.id, fromName: me.name,
            text: String(text.prefix(2000)), reply: allowReply,
            media: media?.0, mime: media?.1.mime)
        request(packet, to: peer.endpoint) { reply in
            if case .ack = reply { completion(true) } else { completion(false) }
        }
    }

    func fetchProfile(from peer: Peer, completion: @escaping (PeerProfile?) -> Void) {
        request(.profileRequest, to: peer.endpoint) { reply in
            if case let .profileResponse(id, name, avatar) = reply {
                completion(PeerProfile(id: id, name: name, avatarJPEG: avatar))
            } else {
                completion(nil)
            }
        }
    }

    /// Conecta, manda um pacote, lê a resposta, fecha. `nil` = falhou.
    private func request(_ packet: Packet, to endpoint: NWEndpoint,
                         completion: @escaping (Packet?) -> Void) {
        let conn = NWConnection(to: endpoint, using: .tcp)
        var finished = false
        func finish(_ reply: Packet?) {
            guard !finished else { return }
            finished = true
            conn.cancel()
            DispatchQueue.main.async { completion(reply) }
        }
        conn.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                self?.sendFrame(packet, on: conn, close: false)
                self?.receiveFrame(on: conn) { finish($0) }
            case let .failed(err):
                self?.noteError(err)
                finish(nil)
            case let .waiting(err):
                // .waiting é transitório (pode virar .ready). Captura -65570 aqui,
                // mas deixa o timeout de 5s decidir — não falha na hora.
                self?.noteError(err)
            default:
                break
            }
        }
        conn.start(queue: .main)
        // rede local não deve demorar; corta pendências
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.timeout) { finish(nil) }
    }

    // MARK: Framing sobre NWConnection

    private func sendFrame(_ packet: Packet, on conn: NWConnection, close: Bool) {
        guard let data = try? Frame.encode(packet) else { conn.cancel(); return }
        conn.send(content: data, completion: .contentProcessed { _ in
            if close { conn.cancel() }
        })
    }

    /// Lê 4 bytes de tamanho, depois o corpo, decodifica. `nil` em erro.
    private func receiveFrame(on conn: NWConnection, then: @escaping (Packet?) -> Void) {
        conn.receive(minimumIncompleteLength: 4, maximumLength: 4) { header, _, _, err in
            guard let header, header.count == 4, err == nil else { then(nil); return }
            let n = Int(header.withUnsafeBytes { $0.loadUnaligned(as: UInt32.self).bigEndian })
            guard n > 0, n <= Frame.maxSize else { then(nil); return }
            // NWConnection não entrega mais que 64 KB por receive — pedir `n` de
            // uma vez faz a leitura falhar calada em qualquer frame com anexo.
            // Acumula em pedaços até fechar o corpo.
            var body = Data()
            body.reserveCapacity(n)
            func more() {
                conn.receive(minimumIncompleteLength: 1,
                             maximumLength: min(n - body.count, 64 * 1024)) { chunk, _, _, err in
                    guard let chunk, !chunk.isEmpty, err == nil else { then(nil); return }
                    body.append(chunk)
                    if body.count < n { more() } else { then(try? Frame.decode(body)) }
                }
            }
            more()
        }
    }

    // MARK: Erros

    private func noteError(_ error: NWError) {
        // kDNSServiceErr_PolicyDenied == -65570 → Rede Local negada
        if case let .dns(code) = error, code == -65570 {
            DispatchQueue.main.async { self.permissionDenied = true }
        }
    }
}
