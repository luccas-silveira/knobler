// Gate da etapa 20 do WhatsApp: foto de perfil com a chave
// (Knobler/WhatsApp/WhatsAppFoto.swift), sem afrouxar o RemoteAvatarLoader.
// Contrato: `GET /v1/foto` em docs/whatsapp-ponte.md:524-535.
//
//   - primeira carga de (conta, jid): `GET /v1/foto?conta&jid&tamanho=miniatura`
//     com `Authorization` e sem `If-None-Match`; a imagem guardada é a
//     miniatura (lado maior <= 128 px) de um JPEG de 1000 × 800.
//   - segunda carga em menos de 10 min: nenhum pedido. Depois de 10 min
//     (relógio injetado): `If-None-Match: "<etag>"`; `304` mantém a imagem.
//   - `404 sem_foto` → `nil` e nenhuma nova tentativa por 10 min.
//   - sem arquivo de chave: nenhum pedido e `nil`.
//   - cache por (conta, jid) e teto de 64 entradas (`WAFotoCache.limite`).
//   - o `avatarcheck` (gate próprio no check.sh) segue provando que o
//     `RemoteAvatarLoader` recusa http e loopback.
//
//   xcrun swiftc -parse-as-library -swift-version 5 \
//     Knobler/WhatsApp/WhatsAppModelos.swift Knobler/WhatsApp/WhatsAppChave.swift \
//     Knobler/WhatsApp/WhatsAppCliente.swift Knobler/RemoteAvatarLoader.swift \
//     Knobler/WhatsApp/WhatsAppFoto.swift tools/whatsappfotocheck.swift \
//     -o /tmp/whatsappfotocheck && /tmp/whatsappfotocheck
//
// Nada sai pela rede: o cliente fala com um transporte falso e o arquivo da
// chave mora em NSTemporaryDirectory().

import AppKit
import Combine

private func exigir(_ cond: Bool, _ msg: String, linha: UInt = #line) {
    if !cond {
        print("FALHOU: \(msg) (tools/whatsappfotocheck.swift:\(linha))")
        exit(1)
    }
}

// MARK: - números do teste

private let A = "554791744143"
private let B = "554792028292"

private let pastaBase = URL(fileURLWithPath: NSTemporaryDirectory())
    .appendingPathComponent("whatsappfotocheck-\(getpid())", isDirectory: true)
private let arquivoDaChave: URL = {
    let u = pastaBase.appendingPathComponent("api-key")
    try! FileManager.default.createDirectory(at: pastaBase, withIntermediateDirectories: true)
    try! Data("chave-de-teste\n".utf8).write(to: u)
    return u
}()
private let semArquivoDeChave = pastaBase.appendingPathComponent("nao-existe/api-key")

/// JPEG de verdade, `largura × altura` px, gerado aqui. Pinta os bytes direto
/// (sem NSGraphicsContext): o roteiro do transporte roda fora da main thread.
private func jpeg(_ largura: Int, _ altura: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: largura, pixelsHigh: altura,
                               bitsPerSample: 8, samplesPerPixel: 3, hasAlpha: false, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    let px = rep.bitmapData!
    for y in 0..<altura {
        for x in 0..<largura {
            let i = y * rep.bytesPerRow + x * 3
            let miolo = x > largura / 4 && x < 3 * largura / 4 && y > altura / 4 && y < 3 * altura / 4
            px[i] = miolo ? 255 : 50
            px[i + 1] = miolo ? 255 : 150
            px[i + 2] = miolo ? 255 : 80
        }
    }
    return rep.representation(using: .jpeg, properties: [.compressionFactor: 0.8])!
}

private let fotoGrande = jpeg(1000, 800)

/// Pixels da imagem entregue (a do CGImage, não o tamanho em pontos).
private func pixels(_ img: NSImage?) -> (Int, Int)? {
    guard let img, let cg = img.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
    return (cg.width, cg.height)
}

private func exigirMiniatura(_ img: NSImage?, _ contexto: String, linha: UInt = #line) {
    guard let (l, a) = pixels(img) else {
        exigir(false, "\(contexto): sem imagem (esperava a miniatura do JPEG 1000 × 800)", linha: linha)
        return
    }
    exigir(max(l, a) <= 128, "\(contexto): imagem guardada tem \(l) × \(a) px; o lado maior passa de 128", linha: linha)
    exigir(l > a && l >= 32, "\(contexto): \(l) × \(a) px não é a miniatura da foto 1000 × 800", linha: linha)
}

// MARK: - relógio injetado

@MainActor
private final class Relogio {
    var agora = Date(timeIntervalSince1970: 1_762_270_000)
    func passar(_ s: TimeInterval) { agora = agora.addingTimeInterval(s) }
}

// MARK: - transporte falso

private struct Pedido {
    let metodo: String
    let caminho: String
    let query: [String: String]
    let cabecalhos: [String: String]
}

private struct Resposta {
    let status: Int
    let dados: Data
    let cabecalhos: [String: String]
}

private func foto(_ dados: Data, etag: String) -> Resposta {
    Resposta(status: 200, dados: dados, cabecalhos: ["Content-Type": "image/jpeg", "ETag": "\"\(etag)\""])
}

private let igual = Resposta(status: 304, dados: Data(), cabecalhos: [:])

private let semFoto = Resposta(
    status: 404, dados: Data(#"{"ok": false, "erro": "sem_foto", "detalhe": "x"}"#.utf8),
    cabecalhos: ["Content-Type": "application/json"])

/// Grava cada pedido e responde pelo roteiro do caso. O cliente pode chamar
/// `enviar` fora do main actor: tudo passa pela trava.
private final class TransporteFalso: WATransporte {
    private let trava = NSLock()
    private var _pedidos: [Pedido] = []
    private var _roteiro: (Pedido) -> Resposta = { _ in semFoto }

    var pedidos: [Pedido] { trava.lock(); defer { trava.unlock() }; return _pedidos }
    var roteiro: (Pedido) -> Resposta {
        get { trava.lock(); defer { trava.unlock() }; return _roteiro }
        set { trava.lock(); _roteiro = newValue; trava.unlock() }
    }

    func enviar(_ pedido: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let comps = URLComponents(url: pedido.url!, resolvingAgainstBaseURL: false)!
        var query: [String: String] = [:]
        for i in comps.queryItems ?? [] { query[i.name] = i.value ?? "" }
        let p = Pedido(metodo: pedido.httpMethod ?? "GET", caminho: comps.path, query: query,
                       cabecalhos: pedido.allHTTPHeaderFields ?? [:])
        registrar(p)
        let r = roteiro(p)
        let h = HTTPURLResponse(url: pedido.url!, statusCode: r.status, httpVersion: "HTTP/1.1",
                                headerFields: r.cabecalhos)!
        return (r.dados, h)
    }

    private func registrar(_ p: Pedido) { trava.lock(); _pedidos.append(p); trava.unlock() }
}

private func cabecalho(_ p: Pedido, _ nome: String) -> String? {
    p.cabecalhos.first { $0.key.lowercased() == nome.lowercased() }?.value
}

@MainActor
private func montar(chave: URL = arquivoDaChave) -> (WAFotoCache, TransporteFalso, Relogio) {
    let t = TransporteFalso()
    let r = Relogio()
    let c = WACliente(porta: 8099, caminhoDaChave: chave, transporte: t)
    return (WAFotoCache(cliente: c, agora: { r.agora }), t, r)
}

// MARK: - casos

/// Primeira carga, cache de 10 min e revalidação com ETag.
@MainActor
private func primeiraCargaECache() async {
    let jid = "554799990001@s.whatsapp.net"
    let (cache, t, relogio) = montar()
    t.roteiro = { _ in foto(fotoGrande, etag: "foto-1") }

    let img = await cache.imagem(conta: A, jid: jid)
    exigir(t.pedidos.count == 1, "primeira carga fez \(t.pedidos.count) pedidos, esperava 1")
    if let p = t.pedidos.first {
        exigir(p.metodo == "GET" && p.caminho == "/v1/foto", "primeira carga pediu \(p.metodo) \(p.caminho)")
        exigir(p.query["conta"] == A, "conta na query: \(p.query["conta"] ?? "nil")")
        exigir(p.query["jid"] == jid, "jid na query: \(p.query["jid"] ?? "nil")")
        exigir(p.query["tamanho"] == "miniatura", "tamanho na query: \(p.query["tamanho"] ?? "nil")")
        exigir(cabecalho(p, "Authorization") == "Bearer chave-de-teste",
               "Authorization da primeira carga: \(cabecalho(p, "Authorization") ?? "nil")")
        exigir(cabecalho(p, "If-None-Match") == nil,
               "primeira carga mandou If-None-Match \(cabecalho(p, "If-None-Match") ?? "")")
    }
    exigirMiniatura(img, "primeira carga")

    // segunda carga logo depois e quase no fim da janela: nada de pedido
    let img2 = await cache.imagem(conta: A, jid: jid)
    exigir(t.pedidos.count == 1, "segunda carga imediata pediu de novo (\(t.pedidos.count) pedidos)")
    exigirMiniatura(img2, "segunda carga imediata")
    relogio.passar(9 * 60 + 59)
    let img3 = await cache.imagem(conta: A, jid: jid)
    exigir(t.pedidos.count == 1, "carga com 9 min 59 s pediu de novo (\(t.pedidos.count) pedidos)")
    exigirMiniatura(img3, "carga com 9 min 59 s")

    // passou de 10 min: revalida com a ETag entre aspas; 304 mantém a imagem
    relogio.passar(2)
    t.roteiro = { _ in igual }
    let img4 = await cache.imagem(conta: A, jid: jid)
    exigir(t.pedidos.count == 2, "depois de 10 min fez \(t.pedidos.count - 1) pedidos novos, esperava 1")
    if t.pedidos.count == 2 {
        let p = t.pedidos[1]
        exigir(p.caminho == "/v1/foto" && p.query["tamanho"] == "miniatura",
               "revalidação pediu \(p.caminho) tamanho=\(p.query["tamanho"] ?? "nil")")
        exigir(cabecalho(p, "If-None-Match") == "\"foto-1\"",
               "If-None-Match da revalidação: \(cabecalho(p, "If-None-Match") ?? "nil"), esperava \"foto-1\" entre aspas")
        exigir(cabecalho(p, "Authorization") == "Bearer chave-de-teste",
               "Authorization da revalidação: \(cabecalho(p, "Authorization") ?? "nil")")
    }
    exigirMiniatura(img4, "depois do 304")

    // o 304 abre outra janela de 10 min
    relogio.passar(5 * 60)
    let img5 = await cache.imagem(conta: A, jid: jid)
    exigir(t.pedidos.count == 2, "5 min depois do 304 pediu de novo (\(t.pedidos.count) pedidos)")
    exigirMiniatura(img5, "5 min depois do 304")
}

/// Cada (conta, jid) tem sua entrada: a mesma pessoa vista pelas duas contas
/// pede duas vezes, e um JID não devolve a foto do outro.
@MainActor
private func chavePorContaEJid() async {
    let jid = "554799990002@s.whatsapp.net"
    let outro = "554799990003@s.whatsapp.net"
    let (cache, t, _) = montar()
    t.roteiro = { p in
        p.query["conta"] == A && p.query["jid"] == jid ? foto(fotoGrande, etag: "foto-a") : semFoto
    }

    exigirMiniatura(await cache.imagem(conta: A, jid: jid), "conta A")
    let deB = await cache.imagem(conta: B, jid: jid)
    exigir(t.pedidos.count == 2, "mesmo jid na outra conta fez \(t.pedidos.count - 1) pedidos, esperava 1")
    exigir(deB == nil, "conta B recebeu a foto que a ponte só deu para a conta A")
    let deOutro = await cache.imagem(conta: A, jid: outro)
    exigir(t.pedidos.count == 3, "outro jid na mesma conta fez \(t.pedidos.count - 2) pedidos, esperava 1")
    exigir(deOutro == nil, "outro jid recebeu a foto de \(jid)")
    if t.pedidos.count == 3 {
        exigir(t.pedidos[1].query["conta"] == B, "segundo pedido foi da conta \(t.pedidos[1].query["conta"] ?? "nil")")
        exigir(t.pedidos[2].query["jid"] == outro, "terceiro pedido foi do jid \(t.pedidos[2].query["jid"] ?? "nil")")
    }
}

/// `404 sem_foto`: nil e nenhuma tentativa nova por 10 min.
@MainActor
private func semFotoNaoInsiste() async {
    let jid = "120363000000020@g.us"
    let (cache, t, relogio) = montar()
    t.roteiro = { _ in semFoto }

    let img = await cache.imagem(conta: A, jid: jid)
    exigir(img == nil, "404 sem_foto devolveu imagem")
    exigir(t.pedidos.count == 1, "404 sem_foto: \(t.pedidos.count) pedidos, esperava 1")

    for passo: TimeInterval in [0, 60, 4 * 60, 4 * 60 + 59] {
        relogio.passar(passo)
        let de_novo = await cache.imagem(conta: A, jid: jid)
        exigir(de_novo == nil, "sem_foto virou imagem dentro da janela")
        exigir(t.pedidos.count == 1, "sem_foto tentou de novo antes de 10 min (\(t.pedidos.count) pedidos)")
    }

    // passou de 10 min (9 min 59 s até aqui + 2 s): tenta de novo, sem ETag
    relogio.passar(2)
    t.roteiro = { _ in foto(fotoGrande, etag: "foto-nova") }
    let depois = await cache.imagem(conta: A, jid: jid)
    exigir(t.pedidos.count == 2, "depois de 10 min sem_foto não tentou de novo (\(t.pedidos.count) pedidos)")
    if t.pedidos.count == 2 {
        exigir(cabecalho(t.pedidos[1], "If-None-Match") == nil,
               "nova tentativa depois de sem_foto mandou If-None-Match \(cabecalho(t.pedidos[1], "If-None-Match") ?? "")")
    }
    exigirMiniatura(depois, "foto que apareceu depois de sem_foto")
}

/// Sem arquivo de chave: nenhum pedido e nil, nem repetindo.
@MainActor
private func semChave() async {
    let jid = "554799990004@s.whatsapp.net"
    let (cache, t, relogio) = montar(chave: semArquivoDeChave)
    t.roteiro = { _ in foto(fotoGrande, etag: "nao-devia") }

    exigir(await cache.imagem(conta: A, jid: jid) == nil, "sem arquivo de chave devolveu imagem")
    relogio.passar(11 * 60)
    exigir(await cache.imagem(conta: A, jid: jid) == nil, "sem arquivo de chave devolveu imagem na segunda vez")
    exigir(t.pedidos.isEmpty, "sem arquivo de chave fez \(t.pedidos.count) pedidos à ponte")
}

/// Teto do cache e o loader para as views (sem carregar nada: o `shared`
/// fala com a ponte de verdade).
@MainActor
private func tetoELoader() {
    exigir(WAFotoCache.limite == 64, "WAFotoCache.limite é \(WAFotoCache.limite), esperava 64")
    exigir(WAFotoCache.limite == RemoteAvatarLoader.limiteDoCache,
           "WAFotoCache.limite (\(WAFotoCache.limite)) diverge do RemoteAvatarLoader.limiteDoCache")
    let _: WAFotoCache = WAFotoCache.shared

    func observavel<T: ObservableObject>(_: T) {}
    let loader = WAFotoLoader()
    observavel(loader)
    exigir(loader.imagem == nil, "WAFotoLoader nasce com imagem")
    let _: (String, String) -> Void = loader.carregar(conta:jid:)
}

@main
enum Gate {
    @MainActor
    static func main() async {
        defer { try? FileManager.default.removeItem(at: pastaBase) }
        _ = arquivoDaChave
        _ = fotoGrande
        tetoELoader()
        await primeiraCargaECache()
        await chavePorContaEJid()
        await semFotoNaoInsiste()
        await semChave()
        print("whatsappfotocheck OK")
    }
}
