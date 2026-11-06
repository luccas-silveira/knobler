// Gate da etapa 18 do WhatsApp: nota de voz gravada pelo gravador do ditado,
// forma de onda pelo nível do microfone e envio como voz
// (Knobler/WhatsApp/WhatsAppGravacao.swift e Knobler/WhatsApp/WhatsAppStore.swift).
// Contrato: `POST /v1/enviar/voz` em docs/whatsapp-ponte.md:630-656 (64
// inteiros de 0 a 100 na `onda`, `segundos` de 1 a 3600 arredondado para
// cima, Ogg Opus mono) e "a ponte lê tudo antes de responder" em :600-603.
//
//   - `WAOnda.reduzir(niveis:)`: exatamente 64 inteiros de 0 a 100; o maior
//     nível vira 100; sem níveis (ou silêncio), 64 zeros; poucos níveis
//     esticam para 64; muitos fazem média por fatia.
//   - `WAOnda.segundos(amostras16k:)`: arredonda para cima, mínimo 1, máximo 3600.
//   - `gravar(em:)`: `gravacao` vira `WAGravacaoEmCurso` com a conversa, o
//     início e o nível que acompanha a fonte; segunda chamada é ignorada.
//   - `cancelarGravacao()`: para a fonte, nada sai pela rede, nada sobra na
//     pasta de envio.
//   - menos de 0,5 s (`< 8000` amostras) é descartado; 0,5 s já envia.
//   - 2 s: `POST /v1/enviar/voz` com o Ogg na pasta de envio (existindo no
//     momento do pedido, começando com `OggS`, `OpusHead` mono), `segundos 2`,
//     a `onda` dos níveis que a fonte entregou, `ref` e `para`; a bolha de voz
//     aparece enviando e vira enviada (ou falhou); o arquivo some depois da
//     resposta, nos dois casos; só o sucesso marca a conversa como lida.
//   - fonte que lança ao começar: sem gravação e "Sem acesso ao microfone".
//
//   xcrun swiftc -parse-as-library -swift-version 5 \
//     Knobler/WhatsApp/WhatsAppModelos.swift Knobler/WhatsApp/WhatsAppChave.swift \
//     Knobler/WhatsApp/WhatsAppCliente.swift Knobler/WhatsApp/WhatsAppCanal.swift \
//     Knobler/WhatsApp/WhatsAppEstado.swift Knobler/WhatsApp/WhatsAppStore.swift \
//     Knobler/WhatsApp/WhatsAppGravacao.swift Knobler/WhatsApp/CodificadorOpus.swift \
//     Knobler/WhatsApp/OggOpus.swift tools/whatsappgravacaocheck.swift \
//     -o /tmp/whatsappgravacaocheck && /tmp/whatsappgravacaocheck
//
// Nada sai pela rede nem pelo microfone: a fonte é falsa (amostras e níveis
// roteirizados) e o cliente fala com um transporte falso que grava cada pedido
// e confere o arquivo no instante do pedido. O store nunca recebe `start()`.
// A chave e a pasta de envio moram em NSTemporaryDirectory().

import Foundation

private func exigir(_ cond: Bool, _ msg: String, linha: UInt = #line) {
    if !cond {
        print("FALHOU: \(msg) (tools/whatsappgravacaocheck.swift:\(linha))")
        exit(1)
    }
}

// MARK: - números do teste

private let A = "554791744143"
private let X = "554799990001@s.whatsapp.net"
private let Y = "554799990002@s.whatsapp.net"

private let kX = WAChave(conta: A, jid: X)
private let kY = WAChave(conta: A, jid: Y)

private let pastaBase = URL(fileURLWithPath: NSTemporaryDirectory())
    .appendingPathComponent("whatsappgravacaocheck-\(getpid())", isDirectory: true)
private let arquivoDaChave: URL = {
    let u = pastaBase.appendingPathComponent("api-key")
    try! FileManager.default.createDirectory(at: pastaBase, withIntermediateDirectories: true)
    try! Data("chave-de-teste\n".utf8).write(to: u)
    return u
}()

/// Seno de 440 Hz a 16 kHz mono, `n` amostras.
private func seno(_ n: Int) -> [Float] {
    (0..<n).map { Float(0.3 * sin(2 * Double.pi * 440 * Double($0) / 16000)) }
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

private func mesmoCaminho(_ a: URL, _ b: URL) -> Bool {
    a.resolvingSymlinksInPath().standardizedFileURL.path == b.resolvingSymlinksInPath().standardizedFileURL.path
}

// MARK: - fonte de microfone falsa

private struct SemMicrofone: Error {}

private final class FonteFalsa: WAFonteDeMicrofone {
    var amostras: [Float]
    var lancar = false
    private(set) var comecos = 0
    private(set) var paradas = 0
    private var aoNivel: ((Float) -> Void)?

    init(amostras: [Float]) { self.amostras = amostras }

    func comecar(nivel: @escaping (Float) -> Void) throws {
        comecos += 1
        if lancar { throw SemMicrofone() }
        aoNivel = nivel
    }

    func parar() -> [Float] {
        paradas += 1
        return amostras
    }

    /// Entrega um nível como o `onLevel` do `MicRecorder` (o callback que o
    /// store passou ao `comecar` mais recente; continua vivo depois de parar).
    func emitir(_ n: Float) { aoNivel?(n) }
}

// MARK: - transporte falso

private struct Pedido {
    let metodo: String
    let caminho: String
    let corpo: [String: Any]
}

/// O arquivo de `POST /v1/enviar/voz` como estava no instante do pedido.
private struct ArquivoNoPedido {
    let caminho: String
    let existia: Bool
    let comecaComOggS: Bool
    /// Byte de canais do `OpusHead` (8 bytes de assinatura + 1 de versão).
    let canais: Int?
}

/// Grava cada pedido e confere o arquivo de voz antes de responder; segura o
/// envio de voz quando o teste manda. O cliente chama `enviar` fora do main
/// actor: tudo passa pela trava.
private final class TransporteFalso: WATransporte {
    private let trava = NSLock()
    private var _pedidos: [Pedido] = []
    private var _arquivos: [ArquivoNoPedido] = []
    private var segurar = false
    private var liberado = false
    private var preso: CheckedContinuation<Void, Never>?
    private var falhar = false
    private var enviados = 0

    var pedidos: [Pedido] { trava.lock(); defer { trava.unlock() }; return _pedidos }
    var arquivos: [ArquivoNoPedido] { trava.lock(); defer { trava.unlock() }; return _arquivos }
    func de(_ caminho: String) -> [Pedido] { pedidos.filter { $0.caminho == caminho } }

    func segurarVoz() { trava.lock(); segurar = true; liberado = false; trava.unlock() }
    func soltarVoz() {
        trava.lock()
        let c = preso
        preso = nil
        if c == nil { liberado = true }
        trava.unlock()
        c?.resume()
    }
    /// O próximo envio de voz responde `502 whatsapp_recusou`.
    func falharVoz() { trava.lock(); falhar = true; trava.unlock() }

    func enviar(_ pedido: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let comps = URLComponents(url: pedido.url!, resolvingAgainstBaseURL: false)!
        let corpo = pedido.httpBody.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } ?? [:]
        let p = Pedido(metodo: pedido.httpMethod ?? "GET", caminho: comps.path, corpo: corpo)

        let arquivo = p.caminho == "/v1/enviar/voz" ? Self.inspecionar(corpo["arquivo"] as? String ?? "") : nil
        if registrar(p, arquivo: arquivo) {
            await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in prender(c) }
        }

        let (status, texto) = responder(p)
        let r = HTTPURLResponse(url: pedido.url!, statusCode: status, httpVersion: "HTTP/1.1",
                                headerFields: ["Content-Type": "application/json"])!
        return (Data(texto.utf8), r)
    }

    /// Grava o pedido (e o arquivo de voz); devolve se é pra segurar.
    private func registrar(_ p: Pedido, arquivo: ArquivoNoPedido?) -> Bool {
        trava.lock(); defer { trava.unlock() }
        _pedidos.append(p)
        guard let arquivo else { return false }
        _arquivos.append(arquivo)
        let s = segurar
        segurar = false
        return s
    }

    /// Prende o envio até `soltarVoz` (ou solta já, se ela veio antes).
    private func prender(_ c: CheckedContinuation<Void, Never>) {
        trava.lock()
        if liberado {
            liberado = false
            trava.unlock(); c.resume()
        } else {
            preso = c; trava.unlock()
        }
    }

    private static func inspecionar(_ caminho: String) -> ArquivoNoPedido {
        guard let d = FileManager.default.contents(atPath: caminho) else {
            return ArquivoNoPedido(caminho: caminho, existia: false, comecaComOggS: false, canais: nil)
        }
        let b = [UInt8](d)
        let ogg = Array(b.prefix(4)) == Array("OggS".utf8)
        var canais: Int? = nil
        let assinatura = Array("OpusHead".utf8)
        if b.count >= assinatura.count + 2 {
            for i in 0...(b.count - assinatura.count - 2) where Array(b[i..<(i + assinatura.count)]) == assinatura {
                canais = Int(b[i + assinatura.count + 1])
                break
            }
        }
        return ArquivoNoPedido(caminho: caminho, existia: true, comecaComOggS: ogg, canais: canais)
    }

    private func responder(_ p: Pedido) -> (Int, String) {
        trava.lock(); defer { trava.unlock() }
        switch (p.metodo, p.caminho) {
        case ("POST", "/v1/enviar/voz"):
            if falhar {
                falhar = false
                return (502, #"{"ok": false, "erro": "whatsapp_recusou", "detalhe": "recusado"}"#)
            }
            enviados += 1
            let ref = p.corpo["ref"] as? String
            let para = p.corpo["para"] as? String ?? ""
            let segundos = p.corpo["segundos"] as? Int ?? 1
            let m = #"{"id": "3EB-VOZ-\#(enviados)", "conversa": \#(js(para)), "remetente": \#(js(A + "@s.whatsapp.net")), "remetente_nome": null, "de_mim": true, "ts": \#(Int(Date().timeIntervalSince1970)), "tipo": "voz", "texto": "", "midia": {"mimetype": "audio/ogg; codecs=opus", "nome": "", "tamanho": 1000, "segundos": \#(segundos), "miniatura": false, "baixada": true}, "citacao": null, "reacoes": [], "editada": null, "apagada": null, "status": "enviada"}"#
            return (200, #"{"ok": true, "ref": \#(js(ref)), "mensagem": \#(m)}"#)
        case ("POST", "/v1/lida"):
            return (200, #"{"ok": true, "marcadas": 1}"#)
        default:
            return (404, #"{"ok": false, "erro": "rota_inexistente", "detalhe": "x"}"#)
        }
    }
}

// MARK: - montagem

private var contadorDeCasos = 0

@MainActor
private final class Montagem {
    let t = TransporteFalso()
    let fonte: FonteFalsa
    let store: WhatsAppStore
    /// Pasta de envio do caso; nasce inexistente (nem a mãe existe).
    let pasta: URL

    init(amostras: [Float] = []) {
        contadorDeCasos += 1
        pasta = pastaBase.appendingPathComponent("caso-\(contadorDeCasos)", isDirectory: true)
            .appendingPathComponent("envio", isDirectory: true)
        fonte = FonteFalsa(amostras: amostras)
        store = WhatsAppStore(cliente: WACliente(porta: 18099, caminhoDaChave: arquivoDaChave, transporte: t))
        store.fonteDeMicrofone = fonte
        store.pastaDeEnvio = pasta
    }

    /// O que está na pasta de envio (pasta ausente = vazia).
    var naPasta: [String] {
        (try? FileManager.default.contentsOfDirectory(atPath: pasta.path)) ?? []
    }

    var bolhasDeVoz: [WABolha] {
        store.estado.bolhas(de: kX).filter { $0.mensagem.tipo == .voz }
    }
}

/// Espera a condição virar verdadeira (até 10 s: a codificação Opus de
/// verdade roda no meio), cedendo o main actor.
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

/// Começa a gravar em kX e espera a gravação aparecer.
@MainActor
private func comecarAGravar(_ m: Montagem, linha: UInt = #line) async {
    m.store.gravar(em: kX)
    await esperar("gravar(em:) pôr a gravação em curso", linha: linha) { m.store.gravacao?.chave == kX }
}

// MARK: - WAOnda

private func validar(_ o: [Int], _ caso: String, maximo: Bool, linha: UInt = #line) {
    exigir(o.count == 64, "reduzir(\(caso)) devolveu \(o.count) valores, esperado 64", linha: linha)
    exigir(o.allSatisfy { (0...100).contains($0) }, "reduzir(\(caso)) saiu de 0...100: \(o)", linha: linha)
    if maximo {
        exigir(o.max() == 100, "reduzir(\(caso)): o maior nível tem que virar 100, maior saiu \(o.max() ?? -1)", linha: linha)
    }
}

private func onda() {
    let zeros = [Int](repeating: 0, count: 64)

    let vazio = WAOnda.reduzir(niveis: [])
    exigir(vazio == zeros, "reduzir(sem níveis) tem que ser 64 zeros, saiu \(vazio)")

    // silêncio não divide por zero nem vira NaN
    let silencio = WAOnda.reduzir(niveis: [Float](repeating: 0, count: 100))
    exigir(silencio == zeros, "reduzir(100 níveis zerados) tem que ser 64 zeros, saiu \(silencio)")

    // 64 níveis: um por barra, normalizados pelo maior (0,5 vira 100)
    let degraus: [Float] = [0, 0.125, 0.25, 0.375, 0.5]
    let n64 = (0..<64).map { degraus[$0 % 5] }
    let o64 = WAOnda.reduzir(niveis: n64)
    validar(o64, "64 níveis", maximo: true)
    let e64 = (0..<64).map { [0, 25, 50, 75, 100][$0 % 5] }
    exigir(o64 == e64, "reduzir(64 níveis até 0,5) tem que normalizar pelo maior: esperado \(e64), saiu \(o64)")

    // um nível só: estica para 64, e ele é o maior
    let o1 = WAOnda.reduzir(niveis: [0.3])
    exigir(o1 == [Int](repeating: 100, count: 64), "reduzir([0,3]) tem que ser 64 × 100, saiu \(o1)")

    // 10 níveis crescentes: estica para 64 sem inventar zero nem perder a ordem
    let n10 = (1...10).map { Float($0) / 10 }
    let o10 = WAOnda.reduzir(niveis: n10)
    validar(o10, "10 níveis", maximo: true)
    exigir(o10.first == 10, "reduzir(10 níveis 0,1…1,0): a primeira barra tem que ser 10, saiu \(o10)")
    exigir(o10.last == 100, "reduzir(10 níveis 0,1…1,0): a última barra tem que ser 100, saiu \(o10)")
    exigir(zip(o10, o10.dropFirst()).allSatisfy { $0 <= $1 },
           "reduzir(10 níveis crescentes) tem que sair em ordem crescente, saiu \(o10)")
    exigir(Set(o10).count >= 10, "reduzir(10 níveis distintos) perdeu níveis: \(Set(o10).count) valores distintos em \(o10)")

    // 1000 níveis: média por fatia. Metade de baixo alterna 0 e 0,4 (média 0,2,
    // pico 0,4); metade de cima é 0,8. Média → ~25 embaixo e 100 em cima;
    // pegar o pico daria 50, pegar uma amostra daria 0 ou 50.
    let n1000 = (0..<1000).map { i -> Float in i < 500 ? (i % 2 == 0 ? 0 : 0.4) : 0.8 }
    let o1000 = WAOnda.reduzir(niveis: n1000)
    validar(o1000, "1000 níveis", maximo: true)
    exigir(o1000[0..<30].allSatisfy { (20...30).contains($0) },
           "reduzir(1000 níveis): as fatias da metade de baixo têm que ser a média (~25 de 100), saiu \(Array(o1000[0..<30]))")
    exigir(o1000[34..<64].allSatisfy { $0 == 100 },
           "reduzir(1000 níveis): as fatias da metade de cima (0,8, o maior) têm que ser 100, saiu \(Array(o1000[34..<64]))")
}

private func segundos() {
    let casos: [(Int, Int, String)] = [
        (8000, 1, "0,5 s"),
        (16000, 1, "1 s exato"),
        (16001, 2, "1 s e uma amostra"),
        (32000, 2, "2 s exatos"),
        (0, 1, "nada"),
        (57_600_000, 3600, "1 hora exata"),
        (3 * 3600 * 16000, 3600, "3 horas"),
    ]
    for (n, esperado, desc) in casos {
        let s = WAOnda.segundos(amostras16k: n)
        exigir(s == esperado, "segundos(amostras16k: \(n)) [\(desc)] devolveu \(s), esperado \(esperado)")
    }
}

// MARK: - pasta padrão

@MainActor
private func pastaPadrao() {
    let s = WhatsAppStore(cliente: WACliente(porta: 18099, caminhoDaChave: arquivoDaChave, transporte: TransporteFalso()))
    let esperado = URL(fileURLWithPath: NSHomeDirectory())
        .appendingPathComponent("Library/Caches/com.zoi.knobler/envio", isDirectory: true)
    exigir(mesmoCaminho(s.pastaDeEnvio, esperado),
           "pastaDeEnvio padrão tem que ser \(esperado.path), é \(s.pastaDeEnvio.path)")
    exigir(s.gravacao == nil, "store novo já com gravação")
    exigir(s.erroDeGravacao == nil, "store novo já com erroDeGravacao")
}

// MARK: - gravar

@MainActor
private func gravarEmCurso() async {
    let m = Montagem(amostras: seno(32000))
    exigir(m.store.gravacao == nil, "gravação antes de gravar(em:)")

    let antes = Date()
    m.store.gravar(em: kX)
    await esperar("gravar(em:) pôr a gravação em curso") { m.store.gravacao != nil }
    let depois = Date()
    let g = m.store.gravacao!
    exigir(g.chave == kX, "gravação em \(g.chave), esperado \(kX)")
    exigir(g.inicio >= antes.addingTimeInterval(-0.01) && g.inicio <= depois.addingTimeInterval(0.01),
           "início da gravação \(g.inicio) fora de [\(antes), \(depois)]")
    exigir(m.fonte.comecos == 1, "gravar(em:) chamou a fonte \(m.fonte.comecos) vez(es), esperado 1")
    exigir(m.store.erroDeGravacao == nil, "gravar com microfone deu erroDeGravacao \(m.store.erroDeGravacao ?? "")")

    // o nível acompanha a fonte
    m.fonte.emitir(0.7)
    await esperar("nível da gravação virar 0,7") { m.store.gravacao?.nivel == 0.7 }
    exigir(m.store.gravacao == WAGravacaoEmCurso(chave: kX, inicio: g.inicio, nivel: 0.7),
           "gravação depois do nível 0,7: \(String(describing: m.store.gravacao))")
    m.fonte.emitir(0.2)
    await esperar("nível da gravação virar 0,2") { m.store.gravacao?.nivel == 0.2 }

    // segunda chamada com gravação em curso é ignorada (outra conversa ou a mesma)
    m.store.gravar(em: kY)
    m.store.gravar(em: kX)
    await assentar()
    exigir(m.store.gravacao == WAGravacaoEmCurso(chave: kX, inicio: g.inicio, nivel: 0.2),
           "segunda gravar(em:) mexeu na gravação em curso: \(String(describing: m.store.gravacao))")
    exigir(m.fonte.comecos == 1, "segunda gravar(em:) começou a fonte de novo (\(m.fonte.comecos) começos)")
    exigir(m.fonte.paradas == 0, "segunda gravar(em:) parou a fonte")
    exigir(m.t.pedidos.isEmpty, "gravar fez pedido HTTP: \(m.t.pedidos.map(\.caminho))")

    m.store.cancelarGravacao()
}

@MainActor
private func cancelar() async {
    let m = Montagem(amostras: seno(32000))
    await comecarAGravar(m)
    m.fonte.emitir(0.5)
    await esperar("nível 0,5") { m.store.gravacao?.nivel == 0.5 }

    m.store.cancelarGravacao()
    await esperar("cancelar zerar a gravação") { m.store.gravacao == nil }
    exigir(m.fonte.paradas == 1, "cancelarGravacao parou a fonte \(m.fonte.paradas) vez(es), esperado 1")
    for _ in 0..<5 { await assentar() }
    exigir(m.t.pedidos.isEmpty, "cancelarGravacao fez pedido HTTP: \(m.t.pedidos.map(\.caminho))")
    exigir(m.naPasta.isEmpty, "cancelarGravacao deixou arquivo na pasta de envio: \(m.naPasta)")
    exigir(m.bolhasDeVoz.isEmpty, "cancelarGravacao deixou bolha de voz na conversa")
    exigir(m.store.erroDeGravacao == nil, "cancelar deu erroDeGravacao")

    // nível atrasado do gravador não ressuscita a gravação
    m.fonte.emitir(0.9)
    await assentar()
    exigir(m.store.gravacao == nil, "nível depois do cancelar recriou a gravação")

    // parar e enviar sem gravação em curso não faz nada
    await m.store.pararEEnviarGravacao()
    await assentar()
    exigir(m.fonte.paradas == 1, "pararEEnviarGravacao sem gravação parou a fonte de novo")
    exigir(m.t.pedidos.isEmpty, "pararEEnviarGravacao sem gravação fez pedido HTTP: \(m.t.pedidos.map(\.caminho))")

    // depois de cancelar, dá pra gravar de novo
    await comecarAGravar(m)
    exigir(m.fonte.comecos == 2, "gravar depois do cancelar não começou a fonte (\(m.fonte.comecos) começos)")
    m.store.cancelarGravacao()
    await esperar("segundo cancelar") { m.store.gravacao == nil }
}

@MainActor
private func curtaDemais() async {
    let m = Montagem(amostras: seno(7999))
    await comecarAGravar(m)
    for n: Float in [0.3, 0.6, 0.9] { m.fonte.emitir(n) }
    await m.store.pararEEnviarGravacao()
    await esperar("gravação curta sair de cena") { m.store.gravacao == nil }
    exigir(m.fonte.paradas == 1, "pararEEnviarGravacao (curta) parou a fonte \(m.fonte.paradas) vez(es), esperado 1")
    for _ in 0..<5 { await assentar() }
    exigir(m.t.pedidos.isEmpty, "gravação de 7999 amostras (< 0,5 s) foi enviada: \(m.t.pedidos.map(\.caminho))")
    exigir(m.bolhasDeVoz.isEmpty, "gravação curta deixou bolha de voz")
    exigir(m.naPasta.isEmpty, "gravação curta deixou arquivo na pasta de envio: \(m.naPasta)")
}

/// 8000 amostras = 0,5 s: já não é curta demais.
@MainActor
private func meioSegundoEnvia() async {
    let m = Montagem(amostras: seno(8000))
    await comecarAGravar(m)
    m.fonte.emitir(0.4)
    await esperar("nível 0,4") { m.store.gravacao?.nivel == 0.4 }
    await m.store.pararEEnviarGravacao()
    await esperar("envio de 0,5 s") { !m.t.de("/v1/enviar/voz").isEmpty }
    let p = m.t.de("/v1/enviar/voz")[0]
    exigir(p.corpo["segundos"] as? Int == 1, "0,5 s tem que ir com segundos 1, foi \(String(describing: p.corpo["segundos"]))")
}

@MainActor
private func vozDe2s() async {
    let m = Montagem(amostras: seno(32000))
    await comecarAGravar(m)
    let niveis: [Float] = (0..<200).map { Float(($0 * 37) % 101) / 100 }
    for n in niveis { m.fonte.emitir(n) }
    await esperar("nível acompanhar o último da fonte") { m.store.gravacao?.nivel == niveis.last }

    m.t.segurarVoz()
    let tarefa = Task { await m.store.pararEEnviarGravacao() }
    await esperar("POST /v1/enviar/voz") { !m.t.de("/v1/enviar/voz").isEmpty }
    exigir(m.fonte.paradas == 1, "pararEEnviarGravacao parou a fonte \(m.fonte.paradas) vez(es), esperado 1")

    // o pedido
    let pedidos = m.t.de("/v1/enviar/voz")
    exigir(pedidos.count == 1, "\(pedidos.count) pedidos de voz, esperado 1")
    let p = pedidos[0]
    exigir(p.metodo == "POST", "envio de voz com \(p.metodo)")
    exigir(p.corpo["conta"] as? String == A, "conta do envio \(String(describing: p.corpo["conta"])), esperado \(A)")
    exigir(p.corpo["para"] as? String == X, "para do envio \(String(describing: p.corpo["para"])), esperado o jid \(X)")
    exigir(p.corpo["segundos"] as? Int == 2, "segundos do envio \(String(describing: p.corpo["segundos"])), esperado 2")
    let onda = p.corpo["onda"] as? [Int] ?? []
    exigir(onda.count == 64, "onda com \(onda.count) valores, esperado 64")
    exigir(onda.allSatisfy { (0...100).contains($0) }, "onda fora de 0...100: \(onda)")
    let esperada = WAOnda.reduzir(niveis: niveis)
    exigir(onda == esperada, "onda tem que vir dos níveis que a fonte entregou: esperado \(esperada), foi \(onda)")
    let ref = p.corpo["ref"] as? String ?? ""
    exigir(!ref.isEmpty, "envio de voz sem ref")
    exigir(p.corpo["citar"] == nil || p.corpo["citar"] is NSNull, "envio de voz citando \(String(describing: p.corpo["citar"]))")

    // o arquivo, como estava no instante do pedido
    let a = m.t.arquivos[0]
    let url = URL(fileURLWithPath: a.caminho)
    exigir(a.caminho.hasPrefix("/"), "arquivo do envio não é caminho absoluto: \(a.caminho)")
    exigir(a.caminho.hasSuffix(".ogg"), "arquivo do envio não termina em .ogg: \(a.caminho)")
    exigir(a.existia, "o arquivo \(a.caminho) não existia no momento do pedido")
    exigir(a.comecaComOggS, "o arquivo do envio não começa com OggS")
    exigir(a.canais == 1, "o OpusHead do arquivo tem que dizer 1 canal, diz \(String(describing: a.canais))")
    exigir(mesmoCaminho(url.deletingLastPathComponent(), m.pasta),
           "o arquivo tem que ficar na pastaDeEnvio (\(m.pasta.path)), ficou em \(url.deletingLastPathComponent().path)")
    exigir(modo(m.pasta) == 0o700, String(format: "pasta de envio nasceu %o, esperado 700", modo(m.pasta)))
    exigir(FileManager.default.fileExists(atPath: a.caminho),
           "o arquivo foi apagado antes da resposta da ponte (ela lê o arquivo até responder)")

    // a bolha, enquanto a ponte não responde
    let enviando = m.bolhasDeVoz
    exigir(enviando.count == 1, "\(enviando.count) bolhas de voz durante o envio, esperado 1")
    if let b = enviando.first {
        exigir(m.store.estado.estadoDaBolha(b) == .enviando,
               "bolha de voz durante o envio está \(m.store.estado.estadoDaBolha(b)), esperado .enviando")
        exigir(b.envio == .enviando(ref: ref), "bolha de voz com envio \(String(describing: b.envio)), esperado .enviando(ref: \(ref))")
        exigir(b.mensagem.deMim, "bolha de voz enviando não é minha")
    }
    exigir(m.t.de("/v1/lida").isEmpty, "marcou lida antes da resposta do envio")

    m.t.soltarVoz()
    await tarefa.value
    await esperar("bolha de voz virar enviada") {
        m.bolhasDeVoz.contains { $0.id == "3EB-VOZ-1" && $0.envio == nil }
    }
    let depois = m.bolhasDeVoz
    exigir(depois.count == 1, "\(depois.count) bolhas de voz depois do envio (a local tem que virar a real): \(depois.map(\.id))")
    if let b = depois.first {
        exigir(b.id == "3EB-VOZ-1", "bolha de voz depois do envio é \(b.id), esperado 3EB-VOZ-1")
        exigir(m.store.estado.estadoDaBolha(b) == .enviada,
               "bolha de voz depois do envio está \(m.store.estado.estadoDaBolha(b)), esperado .enviada")
    }

    await esperar("apagar o arquivo depois da resposta") { !FileManager.default.fileExists(atPath: a.caminho) }
    exigir(m.naPasta.isEmpty, "sobrou arquivo na pasta de envio depois do envio: \(m.naPasta)")

    await esperar("POST /v1/lida depois do envio") { !m.t.de("/v1/lida").isEmpty }
    let lida = m.t.de("/v1/lida")
    exigir(lida.count == 1, "\(lida.count) POST /v1/lida, esperado 1")
    exigir(lida[0].corpo["conta"] as? String == A && lida[0].corpo["conversa"] as? String == X,
           "POST /v1/lida pra \(lida[0].corpo), esperado conta \(A) e conversa \(X)")
    let ordem = m.t.pedidos.map(\.caminho)
    exigir(ordem.firstIndex(of: "/v1/enviar/voz")! < ordem.firstIndex(of: "/v1/lida")!,
           "lida antes do envio: \(ordem)")
    exigir(m.store.gravacao == nil, "gravação continua em curso depois do envio")
}

@MainActor
private func vozRecusada() async {
    let m = Montagem(amostras: seno(32000))
    await comecarAGravar(m)
    m.fonte.emitir(0.5)
    await esperar("nível 0,5") { m.store.gravacao?.nivel == 0.5 }
    m.t.falharVoz()
    await m.store.pararEEnviarGravacao()
    await esperar("POST /v1/enviar/voz") { !m.t.de("/v1/enviar/voz").isEmpty }
    let a = m.t.arquivos[0]
    exigir(a.existia && a.comecaComOggS, "o arquivo do envio recusado não existia ou não era Ogg no pedido")

    await esperar("bolha de voz virar falhou") {
        m.bolhasDeVoz.contains { m.store.estado.estadoDaBolha($0) == .falhou }
    }
    exigir(m.bolhasDeVoz.count == 1, "\(m.bolhasDeVoz.count) bolhas de voz depois da recusa, esperado 1")
    await esperar("apagar o arquivo depois da recusa") { !FileManager.default.fileExists(atPath: a.caminho) }
    exigir(m.naPasta.isEmpty, "sobrou arquivo na pasta de envio depois da recusa: \(m.naPasta)")
    for _ in 0..<5 { await assentar() }
    exigir(m.t.de("/v1/lida").isEmpty, "envio recusado marcou a conversa como lida")
    exigir(m.store.gravacao == nil, "gravação continua em curso depois da recusa")
}

@MainActor
private func semMicrofone() async {
    let m = Montagem(amostras: seno(32000))
    m.fonte.lancar = true
    m.store.gravar(em: kX)
    await esperar("erroDeGravacao aparecer") { m.store.erroDeGravacao != nil }
    exigir(m.store.erroDeGravacao == "Sem acesso ao microfone",
           "erroDeGravacao é \(m.store.erroDeGravacao ?? "nil"), esperado \"Sem acesso ao microfone\"")
    await assentar()
    exigir(m.store.gravacao == nil, "fonte que lançou deixou gravação em curso: \(String(describing: m.store.gravacao))")
    exigir(m.t.pedidos.isEmpty, "fonte que lançou fez pedido HTTP: \(m.t.pedidos.map(\.caminho))")
    exigir(m.naPasta.isEmpty, "fonte que lançou deixou arquivo na pasta de envio")
}

@main
enum Gate {
    @MainActor
    static func main() async {
        defer { try? FileManager.default.removeItem(at: pastaBase) }
        onda()
        segundos()
        pastaPadrao()
        await gravarEmCurso()
        await cancelar()
        await curtaDemais()
        await meioSegundoEnvia()
        await vozDe2s()
        await vozRecusada()
        await semMicrofone()
        try? FileManager.default.removeItem(at: pastaBase)
        print("whatsappgravacaocheck: ok")
    }
}
