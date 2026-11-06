// Gate da etapa 28 do WhatsApp: fumaça de ponta a ponta, sem rede, sem ponte
// e sem WhatsApp. Uma ponte falsa em memória (transporte HTTP falso + canal
// falso) com as duas contas, `554791744143` (padrão) e `554792508292`, ambas
// `conectada`; o fluxo inteiro passa pelo `WhatsAppStore`, pela
// `WhatsAppIntegracao` e por dois `NotchViewModel` ligados como o
// `AppDelegate` liga (Knobler/KnoblerApp.swift:658-659).
//
//   ver a linha `swift_teste tools/whatsappfumacacheck.swift $VM_FONTES
//   $WA_NUCLEO Knobler/NotificationRules.swift
//   Knobler/WhatsApp/WhatsAppCartao.swift
//   Knobler/WhatsApp/WhatsAppIntegracao.swift` em tools/check.sh.
//
// O que se prova, na ordem em que quem usa vive:
//   1. `iniciar()` → canal aberto → `GET /v1/contas`, `/v1/conversas` das duas
//      contas, `/v1/pareamento` → `.pronta`, `ponteConectada`, e o banner do
//      WhatsApp Desktop descartado.
//   2. Mensagem do 4143 chegando na conta 8292 → card nas duas telas em menos
//      de 2 s de relógio de parede, uma vez (reentrega não repete), com o
//      nome do 4143 no título e a linha da conta terminada em "· 8292".
//   3. Resposta pelo card citando a mensagem → `POST /v1/enviar/texto` (conta
//      8292, `citar`, `ref`) e depois `POST /v1/lida`; o card some nas duas
//      telas; o evento da própria resposta não duplica a bolha.
//   4. Abrir a conversa mostra a mensagem recebida; reação → `POST /v1/reagir`.
//   5. Foto e documento → `POST /v1/enviar/midia` com `imagem`/`documento`.
//   6. Áudio de 2 s → `POST /v1/enviar/voz` com Ogg (`OggS`, `OpusHead` mono),
//      `segundos 2` e 64 valores de onda.
//   7. Recibos `entregue` e `lida` levam a bolha enviada a `.lida`.
//   8. Leitura noutro aparelho: `leitura` zera a conversa; o `conta` que vem
//      depois zera o seletor e o sinal da faixa (o sinal é da conta).
//   9. Queda do canal: `ponteConectada == false` e o banner volta; reabrir
//      relê contas e pareamento, e a reentrega não duplica bolha.
//  10. `ressincronize`: relê conversas das duas contas e a conversa aberta,
//      sem bolha duplicada.
//  11. Todo pedido foi para http://127.0.0.1:8099 com a chave no
//      `Authorization`; nenhum saiu sem ela.
//
// A chave (64 hex) mora numa pasta de NSTemporaryDirectory(); a chave de
// verdade da ponte nunca é lida, o `WhatsAppStore.shared` não é tocado e o
// histórico não grava em disco (`arquivo = nil`).

import AppKit

private func exigir(_ cond: Bool, _ msg: String, linha: UInt = #line) {
    if !cond {
        print("FALHOU: \(msg) (tools/whatsappfumacacheck.swift:\(linha))")
        exit(1)
    }
}

// MARK: - as duas contas

private let C4143 = "554791744143"                    // padrão
private let C8292 = "554792508292"
private let J4143 = C4143 + "@s.whatsapp.net"
private let J8292 = C8292 + "@s.whatsapp.net"
private let NOME_4143 = "ZOI Business"
private let NOME_8292 = "Luccas Silveira"
/// A conversa do 8292 com o 4143: é nela que tudo acontece.
private let K = WAChave(conta: C8292, jid: J4143)
private let CHAVE = String(repeating: "3fa9c27e", count: 8)   // 64 hex
private let PORTA = 8099

private func agoraTs() -> Int { Int(Date().timeIntervalSince1970) }

// MARK: - JSON do contrato

private func json(_ obj: Any) -> String {
    let d = try! JSONSerialization.data(withJSONObject: obj, options: [.sortedKeys, .fragmentsAllowed])
    return String(decoding: d, as: UTF8.self)
}

private func nulo(_ v: Any?) -> Any { v ?? NSNull() }

private func contaJSON(_ conta: String, nome: String, padrao: Bool, naoLidas: Int,
                       conversasNaoLidas: Int) -> [String: Any] {
    ["conta": conta, "jid": conta + ":17@s.whatsapp.net", "nome": nome, "padrao": padrao,
     "estado": "conectada", "motivo": NSNull(), "desde": 1_762_270_000,
     "nao_lidas": naoLidas, "conversas_nao_lidas": conversasNaoLidas]
}

private func conversaJSON(_ jid: String, nome: String, naoLidas: Int, ts: Int) -> [String: Any] {
    ["jid": jid, "jids": [jid], "tipo": "individual", "nome": nome, "nao_lidas": naoLidas,
     "marcada_nao_lida": false, "ts": ts, "ultima": NSNull()]
}

private func mensagemJSON(_ id: String, conversa: String, remetente: String, deMim: Bool, ts: Int,
                          tipo: String = "texto", texto: String, midia: [String: Any]? = nil,
                          citacao: [String: Any]? = nil, status: String? = nil) -> [String: Any] {
    ["id": id, "conversa": conversa, "remetente": remetente, "remetente_nome": NSNull(), "de_mim": deMim,
     "ts": ts, "tipo": tipo, "texto": texto, "midia": nulo(midia), "citacao": nulo(citacao),
     "reacoes": [Any](), "editada": NSNull(), "apagada": NSNull(), "status": nulo(status)]
}

// MARK: - ponte falsa (transporte HTTP)

private struct ArquivoNoPedido {
    let existia: Bool
    let bytes: [UInt8]
    var comecaComOggS: Bool { Array(bytes.prefix(4)) == Array("OggS".utf8) }
    /// Byte de canais do `OpusHead` (8 bytes de assinatura + 1 de versão).
    var canaisOpus: Int? {
        let a = Array("OpusHead".utf8)
        guard bytes.count >= a.count + 2 else { return nil }
        for i in 0...(bytes.count - a.count - 2) where Array(bytes[i..<(i + a.count)]) == a {
            return Int(bytes[i + a.count + 1])
        }
        return nil
    }
}

private struct Pedido {
    let metodo: String
    let url: URL
    let caminho: String
    let query: [String: String]
    let corpo: [String: Any]
    let autorizacao: String?
    /// `arquivo` do corpo lido no instante do pedido (a ponte lê antes de responder).
    let arquivo: ArquivoNoPedido?
    var linha: String { "\(metodo) \(caminho)" }
}

/// Responde as rotas do contrato com o estado das duas contas e grava cada pedido.
private final class PonteFalsa: WATransporte {
    private let trava = NSLock()
    private var _pedidos: [Pedido] = []
    private var _historico: [Pedido] = []
    private var contas: [String: [String: Any]] = [
        C4143: contaJSON(C4143, nome: NOME_4143, padrao: true, naoLidas: 0, conversasNaoLidas: 0),
        C8292: contaJSON(C8292, nome: NOME_8292, padrao: false, naoLidas: 0, conversasNaoLidas: 0),
    ]
    /// Mensagens guardadas por `conta|jid`, em ordem.
    private var mensagens: [String: [[String: Any]]] = [:]
    private var enviadas = 0
    private(set) var idsEnviados: [String] = []

    var pedidos: [Pedido] { trava.lock(); defer { trava.unlock() }; return _pedidos }
    /// Todos os pedidos desde o começo (o `limpar` não apaga).
    var historico: [Pedido] { trava.lock(); defer { trava.unlock() }; return _historico }
    func de(_ caminho: String) -> [Pedido] { pedidos.filter { $0.caminho == caminho } }
    func limpar() { trava.lock(); _pedidos = []; trava.unlock() }

    func guardar(_ m: [String: Any], em k: WAChave) {
        trava.lock(); mensagens[k.texto, default: []].append(m); trava.unlock()
    }
    func idsGuardados(_ k: WAChave) -> [String] {
        trava.lock(); defer { trava.unlock() }
        return (mensagens[k.texto] ?? []).compactMap { $0["id"] as? String }
    }
    func definirConta(_ conta: String, naoLidas: Int, conversasNaoLidas: Int) -> [String: Any] {
        trava.lock(); defer { trava.unlock() }
        var c = contas[conta]!
        c["nao_lidas"] = naoLidas
        c["conversas_nao_lidas"] = conversasNaoLidas
        contas[conta] = c
        return c
    }

    func enviar(_ pedido: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let url = pedido.url!
        let comps = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        var q: [String: String] = [:]
        for item in comps.queryItems ?? [] { q[item.name] = item.value ?? "" }
        let corpo = pedido.httpBody.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } ?? [:]
        var arquivo: ArquivoNoPedido?
        if let caminho = corpo["arquivo"] as? String {
            let d = FileManager.default.contents(atPath: caminho)
            arquivo = ArquivoNoPedido(existia: d != nil, bytes: d.map { [UInt8]($0) } ?? [])
        }
        let p = Pedido(metodo: pedido.httpMethod ?? "GET", url: url, caminho: comps.path, query: q, corpo: corpo,
                       autorizacao: pedido.value(forHTTPHeaderField: "Authorization"), arquivo: arquivo)
        registrar(p)
        let (status, texto) = responder(p)
        let r = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1",
                                headerFields: ["Content-Type": "application/json"])!
        return (Data(texto.utf8), r)
    }

    private func registrar(_ p: Pedido) {
        trava.lock(); _pedidos.append(p); _historico.append(p); trava.unlock()
    }

    private func responder(_ p: Pedido) -> (Int, String) {
        trava.lock(); defer { trava.unlock() }
        // a ponte de verdade recusa sem chave; a falsa também
        guard p.autorizacao == "Bearer \(CHAVE)" else {
            return (401, json(["ok": false, "erro": "nao_autorizado", "detalhe": "chave"]))
        }
        let agora = agoraTs()
        switch (p.metodo, p.caminho) {
        case ("GET", "/v1/contas"):
            return (200, json(["ok": true, "contas": [contas[C4143]!, contas[C8292]!]]))
        case ("GET", "/v1/conversas"):
            let lista: [[String: Any]]
            switch p.query["conta"] {
            case C8292?: lista = [conversaJSON(J4143, nome: NOME_4143, naoLidas: 0, ts: agora - 3600)]
            case C4143?: lista = [conversaJSON(J8292, nome: NOME_8292, naoLidas: 0, ts: agora - 3600)]
            default: lista = []
            }
            return (200, json(["ok": true, "conversas": lista, "antes": NSNull()]))
        case ("GET", "/v1/pareamento"):
            return (404, json(["ok": false, "erro": "sem_pareamento", "detalhe": "nada em andamento"]))
        case ("GET", "/v1/mensagens"):
            let k = WAChave(conta: p.query["conta"] ?? "", jid: p.query["conversa"] ?? "")
            return (200, json(["ok": true, "conversa": k.jid, "mensagens": mensagens[k.texto] ?? [],
                               "antes": NSNull()]))
        case ("POST", "/v1/enviar/texto"), ("POST", "/v1/enviar/midia"), ("POST", "/v1/enviar/voz"):
            let conta = p.corpo["conta"] as? String ?? ""
            let para = p.corpo["para"] as? String ?? ""
            let k = WAChave(conta: conta, jid: para)
            enviadas += 1
            let id = "3EB-ENV-\(enviadas)"
            idsEnviados.append(id)
            var citacao: [String: Any]?
            if let alvo = p.corpo["citar"] as? String,
               let m = mensagens[k.texto]?.first(where: { $0["id"] as? String == alvo }) {
                citacao = ["id": alvo, "remetente": m["remetente"]!, "texto": m["texto"]!]
            }
            var tipo = "texto", midia: [String: Any]?
            if p.caminho == "/v1/enviar/midia" {
                tipo = p.corpo["tipo"] as? String ?? "documento"
                midia = ["mimetype": "application/octet-stream", "nome": p.corpo["nome"] as? String ?? "",
                         "tamanho": p.arquivo?.bytes.count ?? 0, "segundos": NSNull(),
                         "miniatura": false, "baixada": true]
            } else if p.caminho == "/v1/enviar/voz" {
                tipo = "voz"
                midia = ["mimetype": "audio/ogg; codecs=opus", "nome": "", "tamanho": p.arquivo?.bytes.count ?? 0,
                         "segundos": p.corpo["segundos"] as? Int ?? 0, "miniatura": false, "baixada": true]
            }
            let m = mensagemJSON(id, conversa: para, remetente: conta + "@s.whatsapp.net", deMim: true, ts: agora,
                                 tipo: tipo, texto: p.corpo["texto"] as? String ?? p.corpo["legenda"] as? String ?? "",
                                 midia: midia, citacao: citacao, status: "enviada")
            mensagens[k.texto, default: []].append(m)
            return (200, json(["ok": true, "ref": nulo(p.corpo["ref"]), "mensagem": m]))
        case ("POST", "/v1/reagir"):
            return (200, json(["ok": true]))
        case ("POST", "/v1/lida"):
            return (200, json(["ok": true, "marcadas": 1]))
        default:
            return (404, json(["ok": false, "erro": "rota_inexistente", "detalhe": p.caminho]))
        }
    }
}

// MARK: - canal falso

/// Entrega quadros JSON do WebSocket, decodificados por `WAEvento.decodificar`.
private final class CanalFalso: WACanalProtocolo {
    var aoEvento: ((WAEvento) -> Void)?
    var aoRessincronizar: ((String, Int) -> Void)?
    var aoMudarEstado: ((WAEstadoDoCanal) -> Void)?
    private(set) var iniciados = 0
    private var seq = 100

    func iniciar() { iniciados += 1 }
    func parar() { aoMudarEstado?(.parado) }
    func acordou() {}
    func mudar(_ e: WAEstadoDoCanal) { aoMudarEstado?(e) }

    func proximoSeq() -> Int { seq += 1; return seq }

    func quadro(_ texto: String, linha: UInt = #line) {
        let e = WAEvento.decodificar(texto)
        exigir(e != nil, "quadro do canal não decodifica: \(texto)", linha: linha)
        aoEvento?(e!)
    }

    /// Envelope de evento numerado (`seq`); devolve o quadro para reentregar.
    @discardableResult
    func numerado(_ tipo: String, conta: String, seq: Int? = nil, _ dados: [String: Any],
                  linha: UInt = #line) -> String {
        let q = json(["seq": seq ?? proximoSeq(), "tipo": tipo, "conta": conta, "ts": agoraTs(), "dados": dados])
        quadro(q, linha: linha)
        return q
    }

    /// Envelope de evento de estado (sem `seq`).
    func estado(_ tipo: String, conta: String, _ dados: [String: Any], linha: UInt = #line) {
        quadro(json(["tipo": tipo, "conta": conta, "ts": agoraTs(), "dados": dados]), linha: linha)
    }
}

// MARK: - fonte de microfone falsa

private final class FonteFalsa: WAFonteDeMicrofone {
    let amostras: [Float]
    private var aoNivel: ((Float) -> Void)?
    init(amostras: [Float]) { self.amostras = amostras }
    func comecar(nivel: @escaping (Float) -> Void) throws { aoNivel = nivel }
    func parar() -> [Float] { amostras }
    func emitir(_ n: Float) { aoNivel?(n) }
}

/// 2 s de seno de 440 Hz a 16 kHz mono.
private let seno2s: [Float] = (0..<32_000).map { Float(0.3 * sin(2 * Double.pi * 440 * Double($0) / 16_000)) }

// MARK: - pasta temporária

private let pastaBase = URL(fileURLWithPath: NSTemporaryDirectory())
    .appendingPathComponent("whatsappfumacacheck-\(getpid())", isDirectory: true)
private let arquivoDaChave: URL = {
    let u = pastaBase.appendingPathComponent("api-key")
    try! FileManager.default.createDirectory(at: pastaBase, withIntermediateDirectories: true)
    try! Data((CHAVE + "\n").utf8).write(to: u)
    return u
}()

// MARK: - espera

@MainActor
private func esperar(_ desc: String, linha: UInt = #line, _ cond: () -> Bool) async {
    for _ in 0..<3000 {
        if cond() { return }
        try? await Task.sleep(nanoseconds: 1_000_000)
    }
    exigir(cond(), "esperou 3 s e não aconteceu: \(desc)", linha: linha)
}

@MainActor
private func assentar() async {
    for _ in 0..<60 { try? await Task.sleep(nanoseconds: 1_000_000) }
}

// MARK: - a cena: ponte, store, integração e duas telas

@MainActor
private final class Cena {
    let ponte = PonteFalsa()
    let canal = CanalFalso()
    private(set) var canaisDaFabrica = 0
    var store: WhatsAppStore!
    let a = NotchViewModel()
    let b = NotchViewModel()
    private(set) var cards: [(card: NotchNotification, quando: Date)] = []
    var integracao: WhatsAppIntegracao!

    init() {
        let cliente = WACliente(porta: PORTA, caminhoDaChave: arquivoDaChave, transporte: ponte)
        store = WhatsAppStore(cliente: cliente, fabricaDeCanal: { [unowned self] _ in
            self.canaisDaFabrica += 1
            return self.canal
        })
        store.pastaDeEnvio = pastaBase.appendingPathComponent("envio", isDirectory: true)
        let telas = [a, b]
        integracao = WhatsAppIntegracao(telas: { telas }, publicar: { [unowned self] card in
            self.cards.append((card, Date()))
            telas.forEach { $0.enqueue(card) }
        })
        // ligada como o AppDelegate liga (Knobler/KnoblerApp.swift:658-659)
        let integracao = self.integracao!
        store.aoChegarMensagem = { m, c, conta in
            integracao.chegou(mensagem: m, conversa: c, conta: conta, numero: conta?.conta ?? "")
        }
        store.aoDispensarCartao = { integracao.respondeu(chave: $0) }
    }

    func conversa(_ conta: String, _ jid: String) -> WAConversa? {
        store.estado.conversas(da: conta).first { $0.jid == jid }
    }
    func conta(_ c: String) -> WAConta? { store.estado.contas.first { $0.conta == c } }
    var bolhas: [WABolha] { store.estado.bolhas(de: K) }
    func banner() -> Bool {
        NotificationRules.descartaBannerDoWhatsApp(appName: "WhatsApp", bundleID: nil,
                                                    ponteConectada: store.ponteConectada)
    }
}

// MARK: - 1. iniciar

@MainActor
private func iniciar(_ c: Cena) async {
    exigir(!c.banner(), "antes de iniciar, o banner do WhatsApp Desktop já era descartado")
    await c.store.iniciar()
    exigir(c.canaisDaFabrica == 1 && c.canal.iniciados == 1,
           "iniciar() deveria criar e iniciar um canal: fábrica \(c.canaisDaFabrica), iniciar \(c.canal.iniciados)")
    exigir(!c.store.ponteConectada, "ponteConectada antes de o canal abrir")
    c.canal.mudar(.aberto)
    await esperar("primeira carga terminar em .pronta") { c.store.conexao == .pronta }
    await assentar()

    exigir(c.ponte.de("/v1/contas").count == 1, "abertura: \(c.ponte.de("/v1/contas").count) GET /v1/contas, esperado 1")
    let contasPedidas = Set(c.ponte.de("/v1/conversas").compactMap { $0.query["conta"] })
    exigir(contasPedidas == [C4143, C8292],
           "abertura: GET /v1/conversas tem que sair para as duas contas, saiu para \(contasPedidas.sorted())")
    exigir(c.ponte.de("/v1/pareamento").count == 1, "abertura: GET /v1/pareamento não saiu uma vez")
    exigir(c.store.estado.contas.map(\.conta).sorted() == [C4143, C8292],
           "as duas contas não estão no estado: \(c.store.estado.contas.map(\.conta))")
    exigir(c.store.estado.contas.first { $0.padrao }?.conta == C4143, "a conta padrão não é a 4143")
    exigir(c.conversa(C8292, J4143) != nil, "a conversa do 8292 com o 4143 não carregou na lista")
    exigir(c.store.ponteConectada, "canal aberto e contas conectadas, mas ponteConectada == false")
    exigir(c.banner(), "ponte conectada e o banner do WhatsApp Desktop não é descartado")
}

// MARK: - 2. chegada

/// Mensagem que o 4143 manda ao 8292, como a ponte publica.
@MainActor
private func chegar(_ c: Cena, id: String, texto: String, naoLidas: Int) -> String {
    let m = mensagemJSON(id, conversa: J4143, remetente: J4143, deMim: false, ts: agoraTs(), texto: texto)
    c.ponte.guardar(m, em: K)
    return c.canal.numerado("mensagem", conta: C8292, [
        "mensagem": m, "conversa": conversaJSON(J4143, nome: NOME_4143, naoLidas: naoLidas, ts: agoraTs()),
        "ref": NSNull()])
}

private let ID_PRIMEIRA = "3EB-4143-1"
private var quadroDaPrimeira = ""
private var quadroDaSegunda = ""

@MainActor
private func chegada(_ c: Cena) async {
    let t0 = Date()
    quadroDaPrimeira = chegar(c, id: ID_PRIMEIRA, texto: "teste notch 1", naoLidas: 1)
    c.canal.estado("conta", conta: C8292, c.ponte.definirConta(C8292, naoLidas: 1, conversasNaoLidas: 1))
    await esperar("o card da mensagem aparecer") { !c.cards.isEmpty }

    exigir(c.cards.count == 1, "uma mensagem publicou \(c.cards.count) cards")
    let (card, quando) = c.cards[0]
    let atraso = quando.timeIntervalSince(t0)
    exigir(atraso < 2, "card publicado \(atraso) s depois da entrega do quadro (limite 2 s)")
    exigir(card.whatsapp?.chave == K.texto, "card de outra conversa: \(String(describing: card.whatsapp?.chave))")
    exigir(card.title == NOME_4143, "título do card \"\(card.title)\", esperado o nome do 4143 \"\(NOME_4143)\"")
    exigir(card.subtitle?.hasSuffix("· 8292") == true,
           "a linha da conta do card tem que terminar em \"· 8292\", veio \"\(card.subtitle ?? "nil")\"")
    exigir(card.body == "teste notch 1", "corpo do card \"\(card.body)\"")
    exigir(c.a.activeNotification?.id == card.id, "o card não apareceu na tela A")
    exigir(c.b.activeNotification?.id == card.id, "o card não apareceu na tela B")

    // a reentrega do mesmo quadro (o `desde` depois de uma queda) não repete
    c.canal.quadro(quadroDaPrimeira)
    await assentar()
    exigir(c.cards.count == 1, "a reentrega da mesma mensagem publicou outro card (\(c.cards.count))")
}

// MARK: - 3. resposta pelo card

private var refDaResposta = ""
private var idDaResposta = ""

@MainActor
private func resposta(_ c: Cena) async {
    let recebida = ID_PRIMEIRA
    // a citação é a mensagem do card
    let m = WAMensagem(id: recebida, conversa: J4143, remetente: J4143, remetenteNome: nil, deMim: false,
                       ts: agoraTs(), tipo: .texto, texto: "teste notch 1", midia: nil, citacao: nil,
                       reacoes: [], editada: nil, apagada: nil, status: nil)
    c.store.citar(m, em: K)
    c.ponte.limpar()

    await c.store.responderCartao(chave: K, texto: "recebi pelo notch")
    await assentar()

    let linhas = c.ponte.pedidos.map(\.linha)
    exigir(linhas == ["POST /v1/enviar/texto", "POST /v1/lida"],
           "responder pelo card: esperado enviar/texto e depois lida, veio \(linhas)")
    let envio = c.ponte.de("/v1/enviar/texto").first
    exigir(envio?.corpo["conta"] as? String == C8292,
           "a resposta saiu pela conta \(String(describing: envio?.corpo["conta"])), esperado a 8292")
    exigir(envio?.corpo["para"] as? String == J4143, "a resposta foi para \(String(describing: envio?.corpo["para"]))")
    exigir(envio?.corpo["texto"] as? String == "recebi pelo notch", "texto da resposta \(String(describing: envio?.corpo["texto"]))")
    exigir(envio?.corpo["citar"] as? String == recebida,
           "a resposta não citou a mensagem do card: citar = \(String(describing: envio?.corpo["citar"]))")
    refDaResposta = envio?.corpo["ref"] as? String ?? ""
    exigir(!refDaResposta.isEmpty, "a resposta saiu sem ref")
    let lida = c.ponte.de("/v1/lida").first
    exigir(lida?.corpo["conta"] as? String == C8292 && lida?.corpo["conversa"] as? String == J4143,
           "POST /v1/lida com corpo errado: \(lida?.corpo ?? [:])")
    exigir(c.a.activeNotification?.whatsapp?.chave != K.texto, "respondi pelo card e ele continuou na tela A")
    exigir(c.b.activeNotification?.whatsapp?.chave != K.texto, "respondi pelo card e ele continuou na tela B")

    // a ponte publica a própria resposta com o `ref`: nem bolha dupla nem card
    idDaResposta = c.ponte.idsEnviados.last ?? ""
    let guardada = mensagemJSON(idDaResposta, conversa: J4143, remetente: J8292, deMim: true, ts: agoraTs(),
                                texto: "recebi pelo notch", status: "enviada")
    let cards = c.cards.count
    c.canal.numerado("mensagem", conta: C8292, [
        "mensagem": guardada, "conversa": conversaJSON(J4143, nome: NOME_4143, naoLidas: 0, ts: agoraTs()),
        "ref": refDaResposta])
    await assentar()
    exigir(c.cards.count == cards, "a minha própria resposta virou card")
    let minhas = c.bolhas.filter { $0.mensagem.texto == "recebi pelo notch" }
    exigir(minhas.count == 1, "a resposta aparece \(minhas.count) vezes na conversa (resposta + evento duplicaram)")
    exigir(minhas.first?.id == idDaResposta && minhas.first?.envio == nil,
           "a bolha da resposta não virou a mensagem da ponte: \(String(describing: minhas.first))")
}

// MARK: - 4. abrir, reagir

@MainActor
private func abrirEReagir(_ c: Cena) async {
    c.ponte.limpar()
    await c.store.abrir(K)
    await assentar()
    let recebida = ID_PRIMEIRA
    exigir(c.bolhas.contains { $0.id == recebida },
           "abri a conversa depois de responder pelo card e a mensagem recebida não aparece: bolhas \(c.bolhas.map(\.id)), pedidos \(c.ponte.pedidos.map(\.linha))")

    c.ponte.limpar()
    await c.store.reagir("👍", a: recebida, em: K)
    let r = c.ponte.de("/v1/reagir")
    exigir(r.count == 1, "reagir: \(r.count) POST /v1/reagir, esperado 1")
    exigir(r.first?.metodo == "POST", "reagir com \(r.first?.metodo ?? "nada")")
    exigir(r.first?.corpo["conta"] as? String == C8292 && r.first?.corpo["conversa"] as? String == J4143,
           "reação com conta/conversa erradas: \(r.first?.corpo ?? [:])")
    exigir(r.first?.corpo["alvo"] as? String == recebida && r.first?.corpo["emoji"] as? String == "👍",
           "reação com alvo/emoji errados: \(r.first?.corpo ?? [:])")
}

// MARK: - 5. foto e documento

private let pngDe1px = Data(base64Encoded:
    "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==")!

@MainActor
private func fotoEDocumento(_ c: Cena) async {
    let foto = pastaBase.appendingPathComponent("praia.png")
    let doc = pastaBase.appendingPathComponent("orcamento.pdf")
    try! pngDe1px.write(to: foto)
    try! Data("%PDF-1.4\n% orçamento de teste\n%%EOF\n".utf8).write(to: doc)

    for (url, tipo, tipoDaBolha) in [(foto, "imagem", WATipoMensagem.imagem), (doc, "documento", .documento)] {
        c.ponte.limpar()
        await c.store.enviarAnexo(url, para: K, legenda: nil)
        await assentar()
        exigir(c.store.erroDeAnexo == nil, "\(url.lastPathComponent): erro de anexo \(c.store.erroDeAnexo ?? "")")
        let p = c.ponte.de("/v1/enviar/midia")
        exigir(p.count == 1, "\(url.lastPathComponent): \(p.count) POST /v1/enviar/midia, esperado 1")
        guard let e = p.first else { continue }
        exigir(e.metodo == "POST", "\(url.lastPathComponent): enviado com \(e.metodo)")
        exigir(e.corpo["tipo"] as? String == tipo,
               "\(url.lastPathComponent) saiu com tipo \(String(describing: e.corpo["tipo"])), esperado \(tipo)")
        exigir(e.corpo["conta"] as? String == C8292 && e.corpo["para"] as? String == J4143,
               "\(url.lastPathComponent) com conta/para errados: \(e.corpo)")
        exigir(e.corpo["nome"] as? String == url.lastPathComponent,
               "\(url.lastPathComponent) saiu com nome \(String(describing: e.corpo["nome"]))")
        exigir(!((e.corpo["ref"] as? String) ?? "").isEmpty, "\(url.lastPathComponent) saiu sem ref")
        let lido = try! Data(contentsOf: url)
        exigir(e.arquivo?.existia == true && e.arquivo?.bytes == [UInt8](lido),
               "\(url.lastPathComponent): o arquivo do pedido não existia ou não é o escolhido no instante do pedido")
        let ultima = c.bolhas.last { $0.mensagem.deMim }
        exigir(ultima?.mensagem.tipo == tipoDaBolha && ultima?.envio == nil,
               "\(url.lastPathComponent): a bolha enviada é \(String(describing: ultima?.mensagem.tipo)), envio \(String(describing: ultima?.envio))")
    }
}

// MARK: - 6. áudio

@MainActor
private func audio(_ c: Cena) async {
    let fonte = FonteFalsa(amostras: seno2s)
    c.store.fonteDeMicrofone = fonte
    c.store.gravar(em: K)
    exigir(c.store.gravacao?.chave == K, "gravar não começou a gravação na conversa: \(String(describing: c.store.gravacao))")
    for i in 0..<100 { fonte.emitir(Float(0.2 + 0.6 * abs(sin(Double(i) / 7)))) }
    c.ponte.limpar()
    await c.store.pararEEnviarGravacao()
    await assentar()

    let p = c.ponte.de("/v1/enviar/voz")
    exigir(p.count == 1, "áudio: \(p.count) POST /v1/enviar/voz, esperado 1")
    guard let v = p.first else { return }
    exigir(v.corpo["conta"] as? String == C8292 && v.corpo["para"] as? String == J4143,
           "voz com conta/para errados: \(v.corpo)")
    exigir(v.corpo["segundos"] as? Int == 2, "2 s de áudio saíram com segundos \(String(describing: v.corpo["segundos"]))")
    let onda = v.corpo["onda"] as? [Int] ?? []
    exigir(onda.count == 64, "onda com \(onda.count) valores, esperado 64")
    exigir(onda.contains { $0 > 0 }, "onda toda zerada apesar dos níveis do microfone")
    exigir(v.arquivo?.existia == true, "o arquivo da voz não existia no instante do pedido")
    exigir(v.arquivo?.comecaComOggS == true, "o arquivo da voz não começa com OggS")
    exigir(v.arquivo?.canaisOpus == 1, "o OpusHead da voz diz \(String(describing: v.arquivo?.canaisOpus)) canais, esperado 1")
    let ultima = c.bolhas.last { $0.mensagem.deMim }
    exigir(ultima?.mensagem.tipo == .voz && ultima?.envio == nil,
           "a bolha de voz é \(String(describing: ultima?.mensagem.tipo)), envio \(String(describing: ultima?.envio))")
}

// MARK: - 7. recibos

@MainActor
private func recibos(_ c: Cena) async {
    func estadoDaResposta() -> WAEstadoDaBolha? {
        c.bolhas.first { $0.id == idDaResposta }.map { c.store.estado.estadoDaBolha($0) }
    }
    exigir(estadoDaResposta() == .enviada, "antes dos recibos, a resposta está \(String(describing: estadoDaResposta()))")
    for (recibo, esperado) in [("entregue", WAEstadoDaBolha.entregue), ("lida", .lida)] {
        c.canal.numerado("recibo", conta: C8292, ["conversa": J4143, "ids": [idDaResposta], "recibo": recibo,
                                                  "de": J4143, "ts": agoraTs()])
        await assentar()
        exigir(estadoDaResposta() == esperado,
               "recibo \(recibo): a bolha enviada ficou \(String(describing: estadoDaResposta())), esperado \(esperado)")
    }
}

// MARK: - 8. leitura noutro aparelho

@MainActor
private func leituraNoutroAparelho(_ c: Cena) async {
    quadroDaSegunda = chegar(c, id: "3EB-4143-2", texto: "viu?", naoLidas: 1)
    c.canal.estado("conta", conta: C8292, c.ponte.definirConta(C8292, naoLidas: 1, conversasNaoLidas: 1))
    await assentar()
    exigir(c.conversa(C8292, J4143)?.naoLidas == 1, "montagem: a conversa não contou a mensagem nova")
    exigir(c.store.estado.sinalDaFaixa == 1, "montagem: sinal da faixa \(c.store.estado.sinalDaFaixa), esperado 1")

    // o `leitura` traz só a conversa
    c.canal.numerado("leitura", conta: C8292, ["conversa": J4143, "nao_lidas": 0, "marcada_nao_lida": false])
    await assentar()
    exigir(c.conversa(C8292, J4143)?.naoLidas == 0,
           "depois do leitura, a conversa ainda conta \(String(describing: c.conversa(C8292, J4143)?.naoLidas))")
    exigir(c.store.estado.sinalDaFaixa == 1,
           "o sinal da faixa mudou com o leitura (\(c.store.estado.sinalDaFaixa)): ele vem do evento conta, não da soma das conversas carregadas")

    // a contagem agregada sai no `conta`
    c.canal.estado("conta", conta: C8292, c.ponte.definirConta(C8292, naoLidas: 0, conversasNaoLidas: 0))
    await assentar()
    exigir(c.conta(C8292)?.naoLidas == 0,
           "depois do conta, o seletor ainda mostra \(String(describing: c.conta(C8292)?.naoLidas)) na 8292")
    exigir(c.store.estado.sinalDaFaixa == 0, "depois do conta, o sinal da faixa ficou \(c.store.estado.sinalDaFaixa)")
}

// MARK: - 9. queda do canal

private func semRepetir(_ ids: [String]) -> Bool { Set(ids).count == ids.count }

@MainActor
private func queda(_ c: Cena) async {
    c.canal.mudar(.foraDoAr)
    exigir(!c.store.ponteConectada, "canal fora do ar e ponteConectada continua true")
    exigir(c.store.conexao == .foraDoAr, "canal fora do ar e a conexão é \(c.store.conexao)")
    exigir(!c.banner(), "ponte fora do ar e o banner do WhatsApp Desktop continua descartado")

    c.ponte.limpar()
    c.canal.mudar(.aberto)
    await esperar("reabertura voltar a .pronta") { c.store.conexao == .pronta && !c.ponte.de("/v1/pareamento").isEmpty }
    await assentar()
    exigir(c.ponte.de("/v1/contas").count == 1, "reabertura: GET /v1/contas não saiu uma vez")
    exigir(c.ponte.de("/v1/pareamento").count == 1, "reabertura: GET /v1/pareamento não saiu uma vez")
    exigir(c.store.ponteConectada && c.banner(), "reabertura: ponte não voltou a conectada (banner não descartado)")

    // o `desde` reentrega o que já tinha chegado e o que chegou na queda
    let antes = c.bolhas.map(\.id)
    let cards = c.cards.count
    c.canal.quadro(quadroDaPrimeira)
    c.canal.quadro(quadroDaSegunda)
    let durante = mensagemJSON("3EB-4143-3", conversa: J4143, remetente: J4143, deMim: false, ts: agoraTs(),
                               texto: "mandei com a ponte fora")
    c.ponte.guardar(durante, em: K)
    let q = c.canal.numerado("mensagem", conta: C8292, [
        "mensagem": durante, "conversa": conversaJSON(J4143, nome: NOME_4143, naoLidas: 1, ts: agoraTs()),
        "ref": NSNull()])
    c.canal.quadro(q)
    await assentar()
    let depois = c.bolhas.map(\.id)
    exigir(semRepetir(depois), "depois da queda há bolha duplicada: \(depois)")
    exigir(depois.filter { $0 == "3EB-4143-3" }.count == 1, "a mensagem da queda não aparece uma vez: \(depois)")
    exigir(Set(antes).isSubset(of: Set(depois)), "a queda sumiu com bolhas: antes \(antes), depois \(depois)")
    exigir(c.cards.count == cards + 1,
           "reentrega do desde: esperado 1 card novo (só a mensagem da queda), vieram \(c.cards.count - cards)")
}

// MARK: - 10. ressincronize

@MainActor
private func ressincronize(_ c: Cena) async {
    c.ponte.limpar()
    c.canal.aoRessincronizar?("J2", 999)
    await esperar("ressincronize reler a conversa aberta") { !c.ponte.de("/v1/mensagens").isEmpty }
    await esperar("ressincronize terminar em .pronta") { c.store.conexao == .pronta }
    await assentar()
    exigir(c.ponte.de("/v1/contas").count == 1, "ressincronize: GET /v1/contas não saiu uma vez")
    let contasPedidas = Set(c.ponte.de("/v1/conversas").compactMap { $0.query["conta"] })
    exigir(contasPedidas == [C4143, C8292], "ressincronize: /v1/conversas relido para \(contasPedidas.sorted())")
    let m = c.ponte.de("/v1/mensagens")
    exigir(m.count == 1 && m.first?.query["conta"] == C8292 && m.first?.query["conversa"] == J4143,
           "ressincronize: a conversa aberta não foi relida uma vez: \(m.map(\.query))")
    let ids = c.bolhas.map(\.id)
    exigir(semRepetir(ids), "depois do ressincronize há bolha duplicada: \(ids)")
    exigir(Set(ids) == Set(c.ponte.idsGuardados(K)),
           "depois do ressincronize a conversa mostra \(ids), a ponte tem \(c.ponte.idsGuardados(K))")
    exigir(c.conversa(C8292, J4143) != nil && c.conversa(C4143, J8292) != nil,
           "depois do ressincronize as listas das duas contas não voltaram")
}

// MARK: - 11. todos os pedidos

@MainActor
private func pedidosLocais(_ todos: [Pedido]) {
    exigir(!todos.isEmpty, "nenhum pedido gravado")
    for p in todos {
        exigir(p.url.scheme == "http" && p.url.host == "127.0.0.1" && p.url.port == PORTA,
               "\(p.linha) saiu para \(p.url.absoluteString), fora de http://127.0.0.1:\(PORTA)")
        exigir(p.autorizacao == "Bearer \(CHAVE)",
               "\(p.linha) saiu com Authorization \(p.autorizacao ?? "nenhum")")
    }
}

// MARK: - main

@main
enum WhatsAppFumacaCheck {
    @MainActor
    static func main() async {
        defer { try? FileManager.default.removeItem(at: pastaBase) }
        // hermético: nada do histórico real entra nem sai
        NotificationHistory.shared.arquivo = nil
        NotificationHistory.shared.limpar()
        UserDefaults.standard.set(NotchSectionOrder.padrao.map(\.rawValue), forKey: "notchSectionOrder")
        UserDefaults.standard.set([String](), forKey: "notchSectionsFixadas")

        let c = Cena()
        await iniciar(c)
        await chegada(c)
        await resposta(c)
        await abrirEReagir(c)
        await fotoEDocumento(c)
        await audio(c)
        await recibos(c)
        await leituraNoutroAparelho(c)
        await queda(c)
        await ressincronize(c)
        pedidosLocais(c.ponte.historico)
        print("whatsappfumacacheck ok")
    }
}
