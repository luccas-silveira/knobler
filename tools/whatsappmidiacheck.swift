// Gate da etapa 19 do WhatsApp: mídia (Knobler/WhatsApp/WhatsAppMidia.swift),
// anexo pelo store (Knobler/WhatsApp/WhatsAppStore.swift) e tocador do áudio
// recebido (Knobler/WhatsApp/WhatsAppPlayer.swift).
// Contrato: nome do arquivo de mídia em docs/whatsapp-ponte.md:195-198,
// `GET /v1/midia` e `POST /v1/midia/recuperar` em :493-519, tipos do anexo em
// :617-621, "a ponte lê tudo antes de responder" em :600-602 e o mimetype
// da voz em :656.
//
//   - `caminho(chave:mensagem:)`: `<raiz>/<conta>/<chat com : → _>/<id com
//     tudo fora de [A-Za-z0-9_-] → _>.<ext>`; a extensão vem do nome e, sem
//     ela, do mimetype (`audio/ogg` → ogg, `image/jpeg` → jpg,
//     `application/pdf` → pdf, desconhecido → bin).
//   - `arquivo(chave:mensagem:)`: arquivo no cache volta sem pedido; senão
//     `GET /v1/midia`, grava e a segunda chamada não pede de novo.
//   - `410 midia_expirada` → `POST /v1/midia/recuperar` uma vez só e
//     `.aguardando`; `recuperou(ok: true)` faz a próxima baixar; `ok: false`
//     → `.indisponivel`.
//   - `409 conta_desconectada` → `.contaDesconectada`; ponte fora do ar →
//     `.falhou` (e volta a baixar quando a ponte volta).
//   - `miniatura(chave:mensagem:)`: `miniatura=1`, guardada em memória;
//     `404 sem_miniatura` → `nil` sem pedir de novo.
//   - `WAAnexo.tipo(paraArquivo:)` e `prepararEnvio(_:pasta:)`.
//   - `WhatsAppStore.enviarAnexo(_:para:legenda:)`: `POST /v1/enviar/midia`
//     com a cópia, nome original e legenda; bolha enviando → enviada (ou
//     falhou); cópia apagada depois da resposta; lida só no sucesso; acima de
//     100 MiB não sai e vira "Arquivo maior que 100 MB".
//   - evento `midia` do canal chega ao cache do store (`recuperou`).
//   - `WAPlayer` com tocador falso: tocar, trocar, pausar, fim do áudio.
//
//   xcrun swiftc -parse-as-library -swift-version 5 \
//     Knobler/WhatsApp/WhatsAppModelos.swift Knobler/WhatsApp/WhatsAppChave.swift \
//     Knobler/WhatsApp/WhatsAppCliente.swift Knobler/WhatsApp/WhatsAppCanal.swift \
//     Knobler/WhatsApp/WhatsAppEstado.swift Knobler/WhatsApp/WhatsAppStore.swift \
//     Knobler/WhatsApp/WhatsAppGravacao.swift Knobler/WhatsApp/CodificadorOpus.swift \
//     Knobler/WhatsApp/OggOpus.swift Knobler/WhatsApp/WhatsAppMidia.swift \
//     Knobler/WhatsApp/WhatsAppPlayer.swift tools/whatsappmidiacheck.swift \
//     -o /tmp/whatsappmidiacheck && /tmp/whatsappmidiacheck
//
// Nada sai pela rede nem toca som: o cliente fala com um transporte falso e o
// tocador é falso. Cache, pasta de envio e anexos moram em
// NSTemporaryDirectory(). A exceção é o cache do store (raiz padrão em
// ~/Library/Caches/com.zoi.knobler/whatsapp): o caso do evento usa uma conta
// fictícia, só toma 410 (nenhum arquivo gravado) e apaga a pasta dela no fim.

import Foundation

private func exigir(_ cond: Bool, _ msg: String, linha: UInt = #line) {
    if !cond {
        print("FALHOU: \(msg) (tools/whatsappmidiacheck.swift:\(linha))")
        exit(1)
    }
}

// MARK: - números do teste

private let A = "554791744143"
private let G = "120363@g.us"
private let X = "554799990001@s.whatsapp.net"
/// Conta fictícia do caso que passa pelo cache padrão do store.
private let C = "550000000019"

private let kG = WAChave(conta: A, jid: G)
private let kX = WAChave(conta: A, jid: X)

private let pastaBase = URL(fileURLWithPath: NSTemporaryDirectory())
    .appendingPathComponent("whatsappmidiacheck-\(getpid())", isDirectory: true)
private let arquivoDaChave: URL = {
    let u = pastaBase.appendingPathComponent("api-key")
    try! FileManager.default.createDirectory(at: pastaBase, withIntermediateDirectories: true)
    try! Data("chave-de-teste\n".utf8).write(to: u)
    return u
}()

private var contadorDeCasos = 0
/// Pasta nova (inexistente) por caso.
private func pastaDoCaso() -> URL {
    contadorDeCasos += 1
    return pastaBase.appendingPathComponent("caso-\(contadorDeCasos)", isDirectory: true)
}

private func msg(_ id: String, conversa: String = G, tipo: WATipoMensagem = .imagem,
                 nome: String = "x.jpg", mimetype: String = "image/jpeg") -> WAMensagem {
    WAMensagem(id: id, conversa: conversa, remetente: "554799990002@s.whatsapp.net", remetenteNome: "Fulano",
               deMim: false, ts: 1_762_270_500, tipo: tipo, texto: "",
               midia: WAMidia(mimetype: mimetype, nome: nome, tamanho: 1000, segundos: nil,
                              miniatura: true, baixada: false),
               citacao: nil, reacoes: [], editada: nil, apagada: nil, status: nil)
}

private func js(_ s: String?) -> String {
    guard let s else { return "null" }
    let d = try! JSONSerialization.data(withJSONObject: [s], options: [.fragmentsAllowed])
    let t = String(decoding: d, as: UTF8.self)
    return String(t.dropFirst().dropLast())
}

private func modo(_ url: URL) -> Int {
    ((try? FileManager.default.attributesOfItem(atPath: url.path))?[.posixPermissions] as? NSNumber)?.intValue ?? -1
}

/// Caminho comparável: sem `..`, sem o `/private` que o /var do temporário ganha.
private func norm(_ u: URL) -> String {
    let p = u.standardizedFileURL.path
    return p.hasPrefix("/private/") ? String(p.dropFirst("/private".count)) : p
}

private func mesmoCaminho(_ a: URL, _ b: URL) -> Bool { norm(a) == norm(b) }

private func dentro(_ u: URL, _ pasta: URL) -> Bool { norm(u).hasPrefix(norm(pasta) + "/") }

private func urlDe(_ r: WAResultadoMidia) -> URL? {
    if case let .arquivo(u) = r { return u }
    return nil
}

private func conteudo(_ u: URL) -> Data? { FileManager.default.contents(atPath: u.path) }

private func itens(_ pasta: URL) -> [String] {
    (try? FileManager.default.contentsOfDirectory(atPath: pasta.path)) ?? []
}

// MARK: - transporte falso

private struct Pedido {
    let metodo: String
    let caminho: String
    let query: [String: String]
    let corpo: [String: Any]
}

private enum Saida {
    case resposta(Int, Data, String)
    case foraDoAr
}

private func jsonResp(_ status: Int, _ texto: String) -> Saida {
    .resposta(status, Data(texto.utf8), "application/json")
}

private func erroResp(_ status: Int, _ erro: String) -> Saida {
    jsonResp(status, #"{"ok": false, "erro": \#(js(erro)), "detalhe": "x"}"#)
}

/// Grava cada pedido, responde pelo roteiro do caso e guarda o conteúdo do
/// arquivo de `POST /v1/enviar/midia` no instante do pedido. Pode segurar o
/// próximo envio de mídia até `soltar()`. O cliente chama `enviar` fora do
/// main actor: tudo passa pela trava.
private final class TransporteFalso: WATransporte {
    private let trava = NSLock()
    private var _pedidos: [Pedido] = []
    private var _noPedido: [String: Data?] = [:]
    private var _roteiro: (Pedido) -> Saida = { _ in erroResp(404, "rota_inexistente") }
    private var segurar = false
    private var liberado = false
    private var preso: CheckedContinuation<Void, Never>?

    var pedidos: [Pedido] { trava.lock(); defer { trava.unlock() }; return _pedidos }
    func de(_ caminho: String) -> [Pedido] { pedidos.filter { $0.caminho == caminho } }
    /// Conteúdo do arquivo citado no envio quando o pedido chegou (`nil` = não existia).
    func noPedido(_ caminho: String) -> Data?? { trava.lock(); defer { trava.unlock() }; return _noPedido[caminho] }

    var roteiro: (Pedido) -> Saida {
        get { trava.lock(); defer { trava.unlock() }; return _roteiro }
        set { trava.lock(); _roteiro = newValue; trava.unlock() }
    }

    func segurarEnvio() { trava.lock(); segurar = true; liberado = false; trava.unlock() }
    func soltar() {
        trava.lock()
        let c = preso
        preso = nil
        if c == nil { liberado = true }
        trava.unlock()
        c?.resume()
    }

    func enviar(_ pedido: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let comps = URLComponents(url: pedido.url!, resolvingAgainstBaseURL: false)!
        var query: [String: String] = [:]
        for i in comps.queryItems ?? [] { query[i.name] = i.value ?? "" }
        let corpo = pedido.httpBody.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } ?? [:]
        let p = Pedido(metodo: pedido.httpMethod ?? "GET", caminho: comps.path, query: query, corpo: corpo)

        if registrar(p) {
            await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in prender(c) }
        }

        switch roteiro(p) {
        case .foraDoAr:
            throw URLError(.cannotConnectToHost)
        case let .resposta(status, dados, tipo):
            let r = HTTPURLResponse(url: pedido.url!, statusCode: status, httpVersion: "HTTP/1.1",
                                    headerFields: ["Content-Type": tipo])!
            return (dados, r)
        }
    }

    /// Grava o pedido (e o arquivo do envio de mídia); devolve se é pra segurar.
    private func registrar(_ p: Pedido) -> Bool {
        trava.lock(); defer { trava.unlock() }
        _pedidos.append(p)
        guard p.caminho == "/v1/enviar/midia", let a = p.corpo["arquivo"] as? String else { return false }
        _noPedido[a] = .some(FileManager.default.contents(atPath: a))
        let s = segurar
        segurar = false
        return s
    }

    private func prender(_ c: CheckedContinuation<Void, Never>) {
        trava.lock()
        if liberado {
            liberado = false
            trava.unlock(); c.resume()
        } else {
            preso = c; trava.unlock()
        }
    }
}

private func cliente(_ t: TransporteFalso) -> WACliente {
    WACliente(porta: 18099, caminhoDaChave: arquivoDaChave, transporte: t)
}

/// Espera a condição virar verdadeira (até 10 s), cedendo o main actor.
@MainActor
private func esperar(_ desc: String, linha: UInt = #line, _ cond: () -> Bool) async {
    for _ in 0..<10_000 {
        if cond() { return }
        try? await Task.sleep(nanoseconds: 1_000_000)
    }
    exigir(cond(), "esperou 10 s e não aconteceu: \(desc)", linha: linha)
}

/// Deixa as tarefas pendentes rodarem: base das provas de "não aconteceu".
@MainActor
private func assentar() async {
    for _ in 0..<80 { try? await Task.sleep(nanoseconds: 1_000_000) }
}

// MARK: - caminho no cache

@MainActor
private func caminhos() {
    let raiz = pastaDoCaso().appendingPathComponent("raiz", isDirectory: true)
    let t = TransporteFalso()
    let c = WAMidiaCache(raiz: raiz, cliente: cliente(t))

    let u = c.caminho(chave: kG, mensagem: msg("3EB0/A+B"))
    exigir(u.path.hasSuffix("/554791744143/120363@g.us/3EB0_A_B.jpg"),
           "caminho de 3EB0/A+B em \(G) é \(u.path), esperado terminar em 554791744143/120363@g.us/3EB0_A_B.jpg")
    exigir(dentro(u, raiz), "caminho \(u.path) fora da raiz do cache \(raiz.path)")
    exigir(u.isFileURL, "caminho não é URL de arquivo: \(u)")

    // `:` do chat vira `_`; o resto do jid fica
    let kDois = WAChave(conta: A, jid: "554799990001:12@s.whatsapp.net")
    let u2 = c.caminho(chave: kDois, mensagem: msg("ABC", conversa: kDois.jid))
    exigir(u2.path.hasSuffix("/554791744143/554799990001_12@s.whatsapp.net/ABC.jpg"),
           "chat com `:` deu \(u2.path), esperado .../554799990001_12@s.whatsapp.net/ABC.jpg")

    // id: só [A-Za-z0-9_-] passa
    let ids: [(String, String)] = [
        ("ABC-def_09", "ABC-def_09"),
        ("a.b c", "a_b_c"),
        ("../x", "___x"),
        ("3EB0é", "3EB0_"),
    ]
    for (id, esperado) in ids {
        let n = c.caminho(chave: kG, mensagem: msg(id)).lastPathComponent
        exigir(n == "\(esperado).jpg", "id \(id) virou arquivo \(n), esperado \(esperado).jpg")
    }

    // extensão: do nome; sem ela, do mimetype
    let exts: [(nome: String, mime: String, ext: String)] = [
        ("x.jpg", "image/jpeg", "jpg"),
        ("contrato.pdf", "application/octet-stream", "pdf"),
        ("", "audio/ogg", "ogg"),
        // é assim que a nota de voz chega (docs/whatsapp-ponte.md:656)
        ("", "audio/ogg; codecs=opus", "ogg"),
        ("", "image/jpeg", "jpg"),
        ("", "application/pdf", "pdf"),
        ("relatorio", "application/pdf", "pdf"),
        ("", "application/x-coisa-que-ninguem-conhece", "bin"),
    ]
    for e in exts {
        let n = c.caminho(chave: kG, mensagem: msg("M1", nome: e.nome, mimetype: e.mime)).lastPathComponent
        exigir(n == "M1.\(e.ext)",
               "nome \"\(e.nome)\" com mimetype \(e.mime) deu \(n), esperado M1.\(e.ext)")
    }

    exigir(t.pedidos.isEmpty, "caminho(chave:mensagem:) fez pedido HTTP: \(t.pedidos.map(\.caminho))")
}

// MARK: - arquivo

@MainActor
private func arquivoBaixaEGuarda() async {
    let raiz = pastaDoCaso().appendingPathComponent("raiz", isDirectory: true)
    let t = TransporteFalso()
    let c = WAMidiaCache(raiz: raiz, cliente: cliente(t))
    let jpeg = Data("JPEG-DE-VERDADE".utf8)
    t.roteiro = { p in
        if p.caminho == "/v1/midia" { return .resposta(200, jpeg, "image/jpeg") }
        return erroResp(404, "rota_inexistente")
    }

    // já no cache: devolve sem pedir (outra conta: as pastas da conta A
    // ficam pro download abaixo provar que nascem 0700)
    let kOutra = WAChave(conta: "554792508292", jid: G)
    let mCache = msg("JA-NO-CACHE")
    let noCache = c.caminho(chave: kOutra, mensagem: mCache)
    try! FileManager.default.createDirectory(at: noCache.deletingLastPathComponent(), withIntermediateDirectories: true)
    try! Data("ANTIGO".utf8).write(to: noCache)
    let r0 = await c.arquivo(chave: kOutra, mensagem: mCache)
    exigir(urlDe(r0).map { mesmoCaminho($0, noCache) } == true,
           "arquivo já no cache devolveu \(r0), esperado .arquivo(\(noCache.path))")
    exigir(t.pedidos.isEmpty, "arquivo já no cache fez pedido: \(t.pedidos.map(\.caminho))")
    exigir(conteudo(noCache) == Data("ANTIGO".utf8), "arquivo já no cache foi reescrito")

    // fora do cache: GET /v1/midia, grava, devolve
    let m = msg("3EB0/A+B")
    let esperado = c.caminho(chave: kG, mensagem: m)
    let r1 = await c.arquivo(chave: kG, mensagem: m)
    guard let u1 = urlDe(r1) else {
        exigir(false, "arquivo fora do cache devolveu \(r1), esperado .arquivo")
        return
    }
    exigir(mesmoCaminho(u1, esperado), "arquivo baixado em \(u1.path), esperado \(esperado.path)")
    exigir(conteudo(u1) == jpeg, "arquivo baixado não tem os bytes que a ponte serviu")
    let gets = t.de("/v1/midia")
    exigir(gets.count == 1, "\(gets.count) GET /v1/midia, esperado 1")
    if let g = gets.first {
        exigir(g.metodo == "GET", "mídia pedida com \(g.metodo)")
        exigir(g.query["conta"] == A, "GET /v1/midia com conta \(g.query["conta"] ?? "nil"), esperado \(A)")
        exigir(g.query["conversa"] == G, "GET /v1/midia com conversa \(g.query["conversa"] ?? "nil"), esperado \(G)")
        exigir(g.query["id"] == "3EB0/A+B", "GET /v1/midia com id \(g.query["id"] ?? "nil"), esperado 3EB0/A+B")
        exigir(g.query["miniatura"] != "1", "o arquivo inteiro foi pedido com miniatura=1")
    }
    exigir(t.de("/v1/midia/recuperar").isEmpty, "download que deu certo pediu recuperação")

    // pastas novas do cache nascem 0700
    let chat = esperado.deletingLastPathComponent()
    let conta = chat.deletingLastPathComponent()
    exigir(modo(chat) == 0o700, String(format: "pasta do chat nasceu %o, esperado 700", modo(chat)))
    exigir(modo(conta) == 0o700, String(format: "pasta da conta nasceu %o, esperado 700", modo(conta)))

    // segunda chamada: do disco, sem pedido
    let r2 = await c.arquivo(chave: kG, mensagem: m)
    exigir(urlDe(r2).map { mesmoCaminho($0, esperado) } == true, "segunda chamada devolveu \(r2)")
    exigir(t.de("/v1/midia").count == 1, "segunda chamada pediu a mídia de novo (\(t.de("/v1/midia").count) GETs)")

    // outro cache na mesma raiz (app relançado) acha o arquivo sem pedir
    let c2 = WAMidiaCache(raiz: raiz, cliente: cliente(t))
    let r3 = await c2.arquivo(chave: kG, mensagem: m)
    exigir(urlDe(r3).map { mesmoCaminho($0, esperado) } == true, "cache novo na mesma raiz devolveu \(r3)")
    exigir(t.de("/v1/midia").count == 1, "cache novo na mesma raiz pediu a mídia de novo")
}

// MARK: - mídia expirada

@MainActor
private func expirada() async {
    let raiz = pastaDoCaso().appendingPathComponent("raiz", isDirectory: true)
    let t = TransporteFalso()
    let c = WAMidiaCache(raiz: raiz, cliente: cliente(t))
    let dados = Data("RECUPERADA".utf8)
    var expirou = true
    t.roteiro = { p in
        switch (p.metodo, p.caminho) {
        case ("GET", "/v1/midia"):
            return expirou ? erroResp(410, "midia_expirada") : .resposta(200, dados, "image/jpeg")
        case ("POST", "/v1/midia/recuperar"):
            return jsonResp(200, #"{"ok": true}"#)
        default:
            return erroResp(404, "rota_inexistente")
        }
    }

    let m = msg("3EB-EXP-1")
    let r1 = await c.arquivo(chave: kG, mensagem: m)
    exigir(r1 == .aguardando, "410 midia_expirada devolveu \(r1), esperado .aguardando")
    var rec = t.de("/v1/midia/recuperar")
    exigir(rec.count == 1, "\(rec.count) POST /v1/midia/recuperar depois do 410, esperado 1")
    if let p = rec.first {
        exigir(p.metodo == "POST", "recuperação com \(p.metodo)")
        exigir(p.corpo["conta"] as? String == A && p.corpo["conversa"] as? String == G
               && p.corpo["id"] as? String == "3EB-EXP-1",
               "recuperação com corpo \(p.corpo), esperado conta \(A), conversa \(G), id 3EB-EXP-1")
    }
    exigir(!FileManager.default.fileExists(atPath: c.caminho(chave: kG, mensagem: m).path),
           "o corpo do 410 foi gravado como arquivo da mídia")

    let r2 = await c.arquivo(chave: kG, mensagem: m)
    exigir(r2 == .aguardando, "segunda chamada da expirada devolveu \(r2), esperado .aguardando")
    rec = t.de("/v1/midia/recuperar")
    exigir(rec.count == 1, "segunda chamada pediu recuperação de novo (\(rec.count) POSTs)")

    // ok: true → a próxima baixa
    expirou = false
    c.recuperou(chave: kG, alvo: "3EB-EXP-1", ok: true)
    let r3 = await c.arquivo(chave: kG, mensagem: m)
    guard let u3 = urlDe(r3) else {
        exigir(false, "depois de recuperou(ok: true) devolveu \(r3), esperado .arquivo")
        return
    }
    exigir(conteudo(u3) == dados, "a mídia recuperada não tem os bytes que a ponte serviu")
    exigir(t.de("/v1/midia/recuperar").count == 1, "baixar depois de recuperada pediu recuperação de novo")

    // ok: false → indisponível
    expirou = true
    let m2 = msg("3EB-EXP-2")
    let r4 = await c.arquivo(chave: kG, mensagem: m2)
    exigir(r4 == .aguardando, "410 da segunda mensagem devolveu \(r4), esperado .aguardando")
    exigir(t.de("/v1/midia/recuperar").count == 2, "a segunda mensagem expirada não pediu a recuperação dela")
    c.recuperou(chave: kG, alvo: "3EB-EXP-2", ok: false)
    let r5 = await c.arquivo(chave: kG, mensagem: m2)
    exigir(r5 == .indisponivel, "depois de recuperou(ok: false) devolveu \(r5), esperado .indisponivel")
    let r6 = await c.arquivo(chave: kG, mensagem: m2)
    exigir(r6 == .indisponivel, "segunda chamada depois de ok: false devolveu \(r6), esperado .indisponivel")
    exigir(t.de("/v1/midia/recuperar").count == 2, "mídia indisponível pediu recuperação de novo")

    // o resultado de uma mensagem não vaza pra outra
    let m3 = msg("3EB-EXP-3")
    let r7 = await c.arquivo(chave: kG, mensagem: m3)
    exigir(r7 == .aguardando, "terceira mensagem expirada devolveu \(r7), esperado .aguardando")
    exigir(t.de("/v1/midia/recuperar").count == 3, "a terceira mensagem expirada não pediu a recuperação dela")
}

// MARK: - erros

@MainActor
private func erros() async {
    let raiz = pastaDoCaso().appendingPathComponent("raiz", isDirectory: true)
    let t = TransporteFalso()
    let c = WAMidiaCache(raiz: raiz, cliente: cliente(t))

    t.roteiro = { p in p.caminho == "/v1/midia" ? erroResp(409, "conta_desconectada") : erroResp(404, "rota_inexistente") }
    let m = msg("3EB-ERR-1")
    let r1 = await c.arquivo(chave: kG, mensagem: m)
    exigir(r1 == .contaDesconectada, "409 conta_desconectada devolveu \(r1), esperado .contaDesconectada")
    exigir(t.de("/v1/midia/recuperar").isEmpty, "409 pediu recuperação")
    exigir(!FileManager.default.fileExists(atPath: c.caminho(chave: kG, mensagem: m).path),
           "o corpo do 409 foi gravado como arquivo da mídia")

    t.roteiro = { _ in .foraDoAr }
    let m2 = msg("3EB-ERR-2")
    let r2 = await c.arquivo(chave: kG, mensagem: m2)
    exigir(r2 == .falhou, "ponte fora do ar devolveu \(r2), esperado .falhou")
    exigir(t.de("/v1/midia/recuperar").isEmpty, "ponte fora do ar pediu recuperação")
    exigir(!FileManager.default.fileExists(atPath: c.caminho(chave: kG, mensagem: m2).path),
           "ponte fora do ar deixou arquivo no cache")

    // a ponte voltou: a mesma mensagem baixa
    let dados = Data("VOLTOU".utf8)
    t.roteiro = { p in p.caminho == "/v1/midia" ? .resposta(200, dados, "image/jpeg") : erroResp(404, "rota_inexistente") }
    let r3 = await c.arquivo(chave: kG, mensagem: m2)
    exigir(urlDe(r3).flatMap(conteudo) == dados, "depois da ponte voltar devolveu \(r3), esperado o arquivo baixado")
}

// MARK: - miniatura

@MainActor
private func miniaturas() async {
    let raiz = pastaDoCaso().appendingPathComponent("raiz", isDirectory: true)
    let t = TransporteFalso()
    let c = WAMidiaCache(raiz: raiz, cliente: cliente(t))
    let mini = Data("MINI".utf8)
    let cheio = Data("CHEIO".utf8)
    t.roteiro = { p in
        guard p.caminho == "/v1/midia" else { return erroResp(404, "rota_inexistente") }
        if p.query["miniatura"] == "1" {
            return p.query["id"] == "SEM-MINI" ? erroResp(404, "sem_miniatura") : .resposta(200, mini, "image/jpeg")
        }
        return .resposta(200, cheio, "image/jpeg")
    }

    let m = msg("3EB-MINI-1")
    let d1 = await c.miniatura(chave: kG, mensagem: m)
    exigir(d1 == mini, "miniatura devolveu \(d1.map { String(decoding: $0, as: UTF8.self) } ?? "nil"), esperado MINI")
    let gets = t.de("/v1/midia")
    exigir(gets.count == 1, "\(gets.count) GET /v1/midia pela miniatura, esperado 1")
    if let g = gets.first {
        exigir(g.query["miniatura"] == "1", "miniatura pedida sem miniatura=1: \(g.query)")
        exigir(g.query["conta"] == A && g.query["conversa"] == G && g.query["id"] == "3EB-MINI-1",
               "miniatura pedida com \(g.query), esperado conta \(A), conversa \(G), id 3EB-MINI-1")
    }

    let d2 = await c.miniatura(chave: kG, mensagem: m)
    exigir(d2 == mini, "segunda miniatura devolveu outra coisa")
    exigir(t.de("/v1/midia").count == 1, "segunda miniatura pediu de novo (\(t.de("/v1/midia").count) GETs)")

    // a miniatura não se passa pelo arquivo inteiro
    let r = await c.arquivo(chave: kG, mensagem: m)
    exigir(urlDe(r).flatMap(conteudo) == cheio, "arquivo depois da miniatura devolveu \(r) sem os bytes do arquivo inteiro")
    let inteiro = t.de("/v1/midia").filter { $0.query["miniatura"] != "1" }
    exigir(inteiro.count == 1, "\(inteiro.count) GET do arquivo inteiro depois da miniatura, esperado 1")

    // 404 sem_miniatura: nil, e não pede de novo
    let s = msg("SEM-MINI")
    let n1 = await c.miniatura(chave: kG, mensagem: s)
    exigir(n1 == nil, "404 sem_miniatura devolveu dados, esperado nil")
    let antes = t.de("/v1/midia").count
    let n2 = await c.miniatura(chave: kG, mensagem: s)
    exigir(n2 == nil, "segunda miniatura sem_miniatura devolveu dados")
    exigir(t.de("/v1/midia").count == antes, "sem_miniatura pediu de novo na mesma sessão")
}

// MARK: - WAAnexo

@MainActor
private func anexo() {
    exigir(WAAnexo.limite == 100 * 1024 * 1024, "WAAnexo.limite é \(WAAnexo.limite), esperado 100 MiB")

    let tipos: [(String, String)] = [
        ("a.jpg", "imagem"), ("a.jpeg", "imagem"), ("a.png", "imagem"), ("a.webp", "imagem"),
        ("a.mp4", "video"), ("a.mov", "video"),
        ("a.gif", "documento"), ("a.pdf", "documento"), ("semextensao", "documento"),
        ("planilha.xlsx", "documento"),
    ]
    for (nome, esperado) in tipos {
        let u = URL(fileURLWithPath: "/tmp/qualquer").appendingPathComponent(nome)
        let r = WAAnexo.tipo(paraArquivo: u)
        exigir(r == esperado, "tipo(paraArquivo: \(nome)) é \(r), esperado \(esperado)")
    }

    let caso = pastaDoCaso()
    let origem = caso.appendingPathComponent("originais", isDirectory: true)
    try! FileManager.default.createDirectory(at: origem, withIntermediateDirectories: true)
    let original = origem.appendingPathComponent("foto da praia.jpg")
    let bytes = Data((0..<4096).map { UInt8($0 % 251) })
    try! bytes.write(to: original)
    let envio = caso.appendingPathComponent("envio", isDirectory: true)

    let copia: URL
    do {
        copia = try WAAnexo.prepararEnvio(original, pasta: envio)
    } catch {
        exigir(false, "prepararEnvio lançou \(error)")
        return
    }
    exigir(copia.path.hasPrefix("/"), "prepararEnvio devolveu caminho relativo: \(copia.path)")
    exigir(dentro(copia, envio), "a cópia \(copia.path) não está na pasta de envio \(envio.path)")
    exigir(copia.deletingLastPathComponent().lastPathComponent == "envio",
           "a cópia \(copia.path) não está numa pasta envio/")
    exigir(copia.pathExtension == "jpg", "a cópia perdeu a extensão: \(copia.lastPathComponent)")
    exigir(UUID(uuidString: copia.deletingPathExtension().lastPathComponent) != nil,
           "a cópia não se chama <UUID>.jpg: \(copia.lastPathComponent)")
    exigir(!mesmoCaminho(copia, original), "prepararEnvio devolveu o próprio original")
    exigir(conteudo(copia) == bytes, "a cópia não tem os bytes do original")
    exigir(conteudo(original) == bytes, "prepararEnvio mexeu no original")

    let outra = try? WAAnexo.prepararEnvio(original, pasta: envio)
    exigir(outra != nil && !mesmoCaminho(outra!, copia), "duas preparações do mesmo arquivo deram o mesmo caminho")
}

// MARK: - envio de anexo pelo store

private final class CanalFalso: WACanalProtocolo {
    var aoEvento: ((WAEvento) -> Void)?
    var aoRessincronizar: ((String, Int) -> Void)?
    var aoMudarEstado: ((WAEstadoDoCanal) -> Void)?
    func iniciar() {}
    func parar() { aoMudarEstado?(.parado) }
    func acordou() {}
    func entregar(_ e: WAEvento) { aoEvento?(e) }
}

/// Respostas da ponte ao envio de anexo. O transporte responde fora do main
/// actor: contador e falha passam pela trava.
private final class PonteDeEnvio {
    private let trava = NSLock()
    private var _falhar = false
    private var enviados = 0

    var falhar: Bool {
        get { trava.lock(); defer { trava.unlock() }; return _falhar }
        set { trava.lock(); _falhar = newValue; trava.unlock() }
    }

    private func proximo() -> Int? {
        trava.lock(); defer { trava.unlock() }
        if _falhar { _falhar = false; return nil }
        enviados += 1
        return enviados
    }

    func responder(_ p: Pedido) -> Saida {
        switch (p.metodo, p.caminho) {
        case ("POST", "/v1/enviar/midia"):
            guard let n = proximo() else { return erroResp(502, "whatsapp_recusou") }
            let tipo = p.corpo["tipo"] as? String ?? "documento"
            let m = #"{"id": "3EB-ANX-\#(n)", "conversa": \#(js(p.corpo["para"] as? String)), "remetente": \#(js(A + "@s.whatsapp.net")), "remetente_nome": null, "de_mim": true, "ts": \#(Int(Date().timeIntervalSince1970)), "tipo": \#(js(tipo)), "texto": \#(js(p.corpo["legenda"] as? String ?? "")), "midia": {"mimetype": "image/jpeg", "nome": "x.jpg", "tamanho": 1000, "segundos": null, "miniatura": false, "baixada": true}, "citacao": null, "reacoes": [], "editada": null, "apagada": null, "status": "enviada"}"#
            return jsonResp(200, #"{"ok": true, "ref": \#(js(p.corpo["ref"] as? String)), "mensagem": \#(m)}"#)
        case ("POST", "/v1/lida"):
            return jsonResp(200, #"{"ok": true, "marcadas": 1}"#)
        default:
            return erroResp(404, "rota_inexistente")
        }
    }
}

@MainActor
private final class Montagem {
    let t = TransporteFalso()
    let ponte = PonteDeEnvio()
    var canais: [CanalFalso] = []
    var store: WhatsAppStore!
    let caso = pastaDoCaso()
    var pasta: URL { caso.appendingPathComponent("envio", isDirectory: true) }
    var originais: URL { caso.appendingPathComponent("originais", isDirectory: true) }

    init() {
        store = WhatsAppStore(cliente: cliente(t), fabricaDeCanal: { [unowned self] _ in
            let c = CanalFalso()
            self.canais.append(c)
            return c
        })
        store.pastaDeEnvio = pasta
        try! FileManager.default.createDirectory(at: originais, withIntermediateDirectories: true)
        let ponte = self.ponte
        t.roteiro = { p in ponte.responder(p) }
    }

    func original(_ nome: String, _ dados: Data) -> URL {
        let u = originais.appendingPathComponent(nome)
        try! dados.write(to: u)
        return u
    }

    var bolhas: [WABolha] { store.estado.bolhas(de: kX) }
}

@MainActor
private func anexoEnviado() async {
    let m = Montagem()
    let bytes = Data((0..<2048).map { UInt8($0 % 7) })
    let original = m.original("foto da praia.jpg", bytes)

    m.t.segurarEnvio()
    let tarefa = Task { await m.store.enviarAnexo(original, para: kX, legenda: "olha isso") }
    await esperar("POST /v1/enviar/midia") { !m.t.de("/v1/enviar/midia").isEmpty }
    let envios = m.t.de("/v1/enviar/midia")
    exigir(envios.count == 1, "\(envios.count) POST /v1/enviar/midia, esperado 1")
    let p = envios[0]
    exigir(p.corpo["conta"] as? String == A, "envio de anexo com conta \(String(describing: p.corpo["conta"])), esperado \(A)")
    exigir(p.corpo["para"] as? String == X, "envio de anexo para \(String(describing: p.corpo["para"])), esperado \(X)")
    exigir(p.corpo["tipo"] as? String == "imagem", "envio de .jpg com tipo \(String(describing: p.corpo["tipo"])), esperado imagem")
    exigir(p.corpo["nome"] as? String == "foto da praia.jpg",
           "envio com nome \(String(describing: p.corpo["nome"])), esperado o nome original \"foto da praia.jpg\"")
    exigir(p.corpo["legenda"] as? String == "olha isso", "envio com legenda \(String(describing: p.corpo["legenda"]))")
    exigir(p.corpo["citar"] == nil || p.corpo["citar"] is NSNull, "envio de anexo citando \(String(describing: p.corpo["citar"]))")
    let ref = p.corpo["ref"] as? String ?? ""
    exigir(!ref.isEmpty, "envio de anexo sem ref")

    let caminho = p.corpo["arquivo"] as? String ?? ""
    exigir(caminho.hasPrefix("/"), "arquivo do envio não é caminho absoluto: \(caminho)")
    let copia = URL(fileURLWithPath: caminho)
    exigir(!mesmoCaminho(copia, original), "o envio mandou o original em vez da cópia")
    exigir(dentro(copia, m.pasta), "a cópia \(caminho) não está na pasta de envio \(m.pasta.path)")
    exigir(m.t.noPedido(caminho) == .some(.some(bytes)), "a cópia não existia (ou não tinha os bytes do original) no instante do pedido")

    // enquanto a ponte não responde: bolha minha, de imagem, com a legenda
    let enviando = m.bolhas
    exigir(enviando.count == 1, "\(enviando.count) bolhas durante o envio do anexo, esperado 1")
    if let b = enviando.first {
        exigir(b.mensagem.deMim, "bolha do anexo não é minha")
        exigir(b.mensagem.tipo == .imagem, "bolha do .jpg com tipo \(b.mensagem.tipo), esperado .imagem")
        exigir(b.mensagem.texto == "olha isso", "bolha do anexo com texto \"\(b.mensagem.texto)\", esperado a legenda")
        exigir(m.store.estado.estadoDaBolha(b) == .enviando,
               "bolha do anexo durante o envio está \(m.store.estado.estadoDaBolha(b)), esperado .enviando")
    }
    exigir(m.t.de("/v1/lida").isEmpty, "marcou lida antes da resposta do envio")

    m.t.soltar()
    await tarefa.value
    await esperar("bolha do anexo virar a real enviada") {
        m.bolhas.contains { $0.id == "3EB-ANX-1" && m.store.estado.estadoDaBolha($0) == .enviada }
    }
    exigir(m.bolhas.count == 1, "\(m.bolhas.count) bolhas depois do envio (a local tem que virar a real): \(m.bolhas.map(\.id))")
    await esperar("apagar a cópia depois da resposta") { !FileManager.default.fileExists(atPath: caminho) }
    exigir(itens(m.pasta).isEmpty, "sobrou arquivo na pasta de envio: \(itens(m.pasta))")
    exigir(conteudo(original) == bytes, "o envio mexeu no original")
    await esperar("POST /v1/lida depois do envio") { !m.t.de("/v1/lida").isEmpty }
    let lida = m.t.de("/v1/lida")
    exigir(lida.count == 1, "\(lida.count) POST /v1/lida, esperado 1")
    exigir(lida[0].corpo["conta"] as? String == A && lida[0].corpo["conversa"] as? String == X,
           "POST /v1/lida pra \(lida[0].corpo), esperado conta \(A) e conversa \(X)")
    let ordem = m.t.pedidos.map(\.caminho)
    exigir(ordem.firstIndex(of: "/v1/enviar/midia")! < ordem.firstIndex(of: "/v1/lida")!,
           "lida saiu antes do envio: \(ordem)")
    exigir(m.store.erroDeAnexo == nil, "envio que deu certo deixou erroDeAnexo \(m.store.erroDeAnexo ?? "")")
}

@MainActor
private func anexoOutrosTipos() async {
    let m = Montagem()
    let video = m.original("clipe.mov", Data("MOV".utf8))
    await m.store.enviarAnexo(video, para: kX, legenda: nil)
    let pdf = m.original("proposta.pdf", Data("%PDF".utf8))
    await m.store.enviarAnexo(pdf, para: kX, legenda: "segue")
    let gif = m.original("risada.gif", Data("GIF89a".utf8))
    await m.store.enviarAnexo(gif, para: kX, legenda: nil)
    await esperar("três POST /v1/enviar/midia") { m.t.de("/v1/enviar/midia").count == 3 }
    let e = m.t.de("/v1/enviar/midia")
    let esperados: [(String, String, String?)] = [
        ("video", "clipe.mov", nil), ("documento", "proposta.pdf", "segue"), ("documento", "risada.gif", nil),
    ]
    for (p, (tipo, nome, legenda)) in zip(e, esperados) {
        exigir(p.corpo["tipo"] as? String == tipo, "envio de \(nome) com tipo \(String(describing: p.corpo["tipo"])), esperado \(tipo)")
        exigir(p.corpo["nome"] as? String == nome, "envio de \(nome) com nome \(String(describing: p.corpo["nome"]))")
        if let legenda {
            exigir(p.corpo["legenda"] as? String == legenda, "envio de \(nome) com legenda \(String(describing: p.corpo["legenda"]))")
        } else {
            let l = p.corpo["legenda"]
            exigir(l == nil || l is NSNull || (l as? String) == "", "envio de \(nome) sem legenda mandou legenda \(String(describing: l))")
        }
    }
    let tiposDasBolhas = m.bolhas.filter { $0.mensagem.deMim }.map(\.mensagem.tipo)
    exigir(tiposDasBolhas.contains(.video), "anexo .mov não virou bolha de vídeo: \(tiposDasBolhas)")
    exigir(tiposDasBolhas.filter { $0 == .documento }.count == 2, "pdf e gif não viraram duas bolhas de documento: \(tiposDasBolhas)")
    await esperar("pasta de envio vazia") { itens(m.pasta).isEmpty }
}

@MainActor
private func anexoRecusado() async {
    let m = Montagem()
    let bytes = Data("CONTEUDO".utf8)
    let original = m.original("nota.pdf", bytes)
    m.ponte.falhar = true
    await m.store.enviarAnexo(original, para: kX, legenda: nil)
    await esperar("POST /v1/enviar/midia") { !m.t.de("/v1/enviar/midia").isEmpty }
    let caminho = m.t.de("/v1/enviar/midia")[0].corpo["arquivo"] as? String ?? ""
    exigir(m.t.noPedido(caminho) == .some(.some(bytes)), "a cópia não existia no instante do envio recusado")
    await esperar("bolha do anexo virar falhou") {
        m.bolhas.contains { m.store.estado.estadoDaBolha($0) == .falhou }
    }
    exigir(m.bolhas.count == 1, "\(m.bolhas.count) bolhas depois da recusa, esperado 1")
    await esperar("apagar a cópia depois da recusa") { !FileManager.default.fileExists(atPath: caminho) }
    exigir(itens(m.pasta).isEmpty, "sobrou arquivo na pasta de envio depois da recusa: \(itens(m.pasta))")
    exigir(conteudo(original) == bytes, "a recusa mexeu no original")
    for _ in 0..<5 { await assentar() }
    exigir(m.t.de("/v1/lida").isEmpty, "envio recusado marcou a conversa como lida")
}

/// Arquivo esparso do tamanho pedido (não ocupa disco).
private func esparso(_ u: URL, tamanho: Int) {
    FileManager.default.createFile(atPath: u.path, contents: nil)
    let h = try! FileHandle(forWritingTo: u)
    try! h.truncate(atOffset: UInt64(tamanho))
    try! h.close()
}

@MainActor
private func anexoGrande() async {
    let m = Montagem()
    let grande = m.originais.appendingPathComponent("video enorme.mp4")
    esparso(grande, tamanho: WAAnexo.limite + 1)
    await m.store.enviarAnexo(grande, para: kX, legenda: "pesado")
    for _ in 0..<3 { await assentar() }
    exigir(m.t.de("/v1/enviar/midia").isEmpty, "arquivo acima de 100 MiB foi enviado")
    exigir(m.store.erroDeAnexo == "Arquivo maior que 100 MB",
           "erroDeAnexo é \(m.store.erroDeAnexo ?? "nil"), esperado \"Arquivo maior que 100 MB\"")
    exigir(m.bolhas.isEmpty, "arquivo acima de 100 MiB deixou bolha na conversa: \(m.bolhas.map(\.id))")
    exigir(itens(m.pasta).isEmpty, "arquivo acima de 100 MiB foi copiado pra pasta de envio: \(itens(m.pasta))")
    exigir(FileManager.default.fileExists(atPath: grande.path), "o original grande sumiu")
    try? FileManager.default.removeItem(at: grande)

    // exatamente 100 MiB ainda vai
    let m2 = Montagem()
    let limite = m2.originais.appendingPathComponent("no limite.bin")
    esparso(limite, tamanho: WAAnexo.limite)
    await m2.store.enviarAnexo(limite, para: kX, legenda: nil)
    await esperar("POST /v1/enviar/midia de exatamente 100 MiB") { !m2.t.de("/v1/enviar/midia").isEmpty }
    exigir(m2.store.erroDeAnexo == nil, "arquivo de exatamente 100 MiB virou erro: \(m2.store.erroDeAnexo ?? "")")
    await esperar("pasta de envio vazia depois de 100 MiB") { itens(m2.pasta).isEmpty }
    try? FileManager.default.removeItem(at: limite)
}

// MARK: - evento midia chega ao cache do store

@MainActor
private func eventoMidia() async {
    let m = Montagem()
    m.t.roteiro = { p in
        switch (p.metodo, p.caminho) {
        case ("GET", "/v1/midia"): return erroResp(410, "midia_expirada")
        case ("POST", "/v1/midia/recuperar"): return jsonResp(200, #"{"ok": true}"#)
        default: return erroResp(404, "rota_inexistente")
        }
    }
    let jid = "550000000019-1762270500@g.us"
    let k = WAChave(conta: C, jid: jid)
    let mensagem = msg("3EB-EVT-1", conversa: jid)
    // a pasta da conta fictícia no cache padrão; apagada no fim
    let pastaDaConta = m.store.midia.caminho(chave: k, mensagem: mensagem)
        .deletingLastPathComponent().deletingLastPathComponent()
    defer {
        if pastaDaConta.lastPathComponent == C { try? FileManager.default.removeItem(at: pastaDaConta) }
    }

    await m.store.iniciar()
    exigir(!m.canais.isEmpty, "iniciar() não criou canal")

    let r1 = await m.store.midia.arquivo(chave: k, mensagem: mensagem)
    exigir(!m.t.de("/v1/midia").isEmpty, "o cache do store não usa o cliente do store (nenhum GET /v1/midia chegou ao transporte)")
    exigir(r1 == .aguardando, "410 pelo cache do store devolveu \(r1), esperado .aguardando")
    exigir(m.t.de("/v1/midia/recuperar").count == 1, "o cache do store não pediu a recuperação")

    m.canais.last!.entregar(.numerado(seq: 1, conta: C, ts: 1_762_270_600,
                                      .midia(conversa: jid, alvo: "3EB-EVT-1", ok: false)))
    await assentar()
    let r2 = await m.store.midia.arquivo(chave: k, mensagem: mensagem)
    exigir(r2 == .indisponivel, "evento midia ok: false não chegou ao cache: devolveu \(r2), esperado .indisponivel")
    m.store.stop()
}

// MARK: - tocador

private final class TocadorFalso: WATocador {
    var aoTerminar: (() -> Void)?
    var duracao: TimeInterval = 10
    var tempo: TimeInterval = 3
    private(set) var tocadas = 0
    private(set) var pausas = 0
    func tocar() -> Bool { tocadas += 1; return true }
    func pausar() { pausas += 1 }
}

@MainActor
private func tocador() async {
    exigir(WAPlayer.shared.tocando == nil, "WAPlayer.shared nasceu tocando")

    var urls: [URL] = []
    var tocadores: [TocadorFalso] = []
    let p = WAPlayer(fabrica: { u in
        let f = TocadorFalso()
        urls.append(u)
        tocadores.append(f)
        return f
    })
    exigir(p.tocando == nil, "player novo tocando \(p.tocando ?? "")")
    exigir(p.progresso == 0, "player novo com progresso \(p.progresso)")

    let u1 = URL(fileURLWithPath: "/tmp/a.ogg")
    let u2 = URL(fileURLWithPath: "/tmp/b.ogg")
    let u3 = URL(fileURLWithPath: "/tmp/c.ogg")

    p.tocar(url: u1, id: "m1")
    exigir(urls == [u1], "tocar(url: a.ogg) abriu \(urls.map(\.lastPathComponent))")
    exigir(tocadores.count == 1 && tocadores[0].tocadas == 1, "tocar(url:id:) não mandou o tocador tocar")
    exigir(p.tocando == "m1", "depois de tocar m1, tocando é \(p.tocando ?? "nil")")

    p.tocar(url: u2, id: "m2")
    exigir(tocadores.count == 2 && tocadores[1].tocadas == 1, "tocar outro áudio não tocou o novo")
    exigir(tocadores[0].pausas >= 1, "tocar outro áudio não parou o anterior")
    exigir(p.tocando == "m2", "depois de tocar m2, tocando é \(p.tocando ?? "nil")")

    p.pausar()
    exigir(p.tocando == nil, "depois de pausar(), tocando é \(p.tocando ?? "nil")")
    exigir(tocadores[1].pausas >= 1, "pausar() não pausou o tocador")

    p.tocar(url: u3, id: "m3")
    exigir(p.tocando == "m3", "depois de tocar m3, tocando é \(p.tocando ?? "nil")")
    exigir(tocadores.count == 3, "tocar m3 não abriu tocador novo")
    let f3 = tocadores[2]
    exigir(f3.aoTerminar != nil, "o player não ouve o fim do áudio (aoTerminar nil)")
    f3.aoTerminar?()
    await esperar("fim do áudio limpar tocando e progresso") { p.tocando == nil && p.progresso == 0 }
    // nada volta a mexer no progresso depois do fim
    for _ in 0..<8 { await assentar() }
    exigir(p.tocando == nil, "tocando voltou depois do fim: \(p.tocando ?? "")")
    exigir(p.progresso == 0, "progresso voltou a \(p.progresso) depois do fim do áudio")
}

@main
enum Gate {
    @MainActor
    static func main() async {
        defer { try? FileManager.default.removeItem(at: pastaBase) }
        caminhos()
        await arquivoBaixaEGuarda()
        await expirada()
        await erros()
        await miniaturas()
        anexo()
        await anexoEnviado()
        await anexoOutrosTipos()
        await anexoRecusado()
        await anexoGrande()
        await eventoMidia()
        await tocador()
        try? FileManager.default.removeItem(at: pastaBase)
        print("whatsappmidiacheck: ok")
    }
}
