// Gate da etapa 8 do WhatsApp: o estado como singleton inerte até `start`
// (Knobler/WhatsApp/WhatsAppStore.swift), ligando cliente, canal e estado.
// Contrato: docs/whatsapp-ponte.md (rotas em :449-722, `ref` em :272-275,
// `ressincronize` em :773-775, `sincronizacao` em :932-939, eventos de estado
// em :941-950).
//
//   xcrun swiftc -parse-as-library -swift-version 5 \
//     Knobler/WhatsApp/WhatsAppModelos.swift Knobler/WhatsApp/WhatsAppChave.swift \
//     Knobler/WhatsApp/WhatsAppCliente.swift Knobler/WhatsApp/WhatsAppCanal.swift \
//     Knobler/WhatsApp/WhatsAppEstado.swift Knobler/WhatsApp/WhatsAppStore.swift \
//     tools/whatsappstorecheck.swift \
//     -o /tmp/whatsappstorecheck && /tmp/whatsappstorecheck
//
// Nada sai pela rede: o cliente fala com um transporte falso que responde por
// caminho e grava cada pedido, e o canal é um falso cujos callbacks o teste
// dispara. A chave mora numa pasta de NSTemporaryDirectory(); a chave de
// verdade da ponte nunca é lida, e nenhum `WhatsAppStore()` sem injeção é
// criado aqui (ele leria a chave real).

import Foundation

private func exigir(_ cond: Bool, _ msg: String, linha: UInt = #line) {
    if !cond {
        print("FALHOU: \(msg) (tools/whatsappstorecheck.swift:\(linha))")
        exit(1)
    }
}

// MARK: - números do teste

private let A = "554791744143"   // conta padrão
private let B = "554792508292"
private let NOVA = "554700000003" // conta que entra pelo pareamento
private let X = "554799990001@s.whatsapp.net" // conversa da conta A
private let Y = "554799990002@s.whatsapp.net" // conversa da conta A
private let Z = "554799990003@s.whatsapp.net" // conversa da conta B

private let kX = WAChave(conta: A, jid: X)
private let kY = WAChave(conta: A, jid: Y)

// MARK: - JSON do contrato

private func js(_ s: String?) -> String {
    guard let s else { return "null" }
    let d = try! JSONSerialization.data(withJSONObject: [s], options: [.fragmentsAllowed])
    let t = String(decoding: d, as: UTF8.self)
    return String(t.dropFirst().dropLast())
}

private func contaJSON(_ numero: String, padrao: Bool, estado: String = "conectada") -> String {
    #"{"conta": \#(js(numero)), "jid": \#(js(numero + ":17@s.whatsapp.net")), "nome": null, "padrao": \#(padrao), "estado": \#(js(estado)), "motivo": null, "desde": 1762270000, "nao_lidas": 0, "conversas_nao_lidas": 0}"#
}

private func conversaJSON(_ jid: String, ts: Int, naoLidas: Int = 0) -> String {
    #"{"jid": \#(js(jid)), "jids": [\#(js(jid))], "tipo": "individual", "nome": \#(js("Nome " + jid.prefix(12))), "nao_lidas": \#(naoLidas), "marcada_nao_lida": false, "ts": \#(ts), "ultima": null}"#
}

private func mensagemJSON(_ id: String, conversa: String, deMim: Bool = false, remetente: String? = nil,
                          ts: Int, texto: String = "oi", status: String? = nil) -> String {
    let r = remetente ?? (deMim ? A + "@s.whatsapp.net" : conversa)
    return #"{"id": \#(js(id)), "conversa": \#(js(conversa)), "remetente": \#(js(r)), "remetente_nome": null, "de_mim": \#(deMim), "ts": \#(ts), "tipo": "texto", "texto": \#(js(texto)), "midia": null, "citacao": null, "reacoes": [], "editada": null, "apagada": null, "status": \#(js(status))}"#
}

private func decodificar<T: Decodable>(_ tipo: T.Type, _ json: String) -> T {
    do { return try WAJSON.decodificador.decode(tipo, from: Data(json.utf8)) } catch {
        print("FALHOU: fixture não decodifica como \(tipo): \(error) (tools/whatsappstorecheck.swift)")
        exit(1)
    }
}

private func mensagem(_ id: String, conversa: String = X, deMim: Bool = false, ts: Int,
                      texto: String = "oi") -> WAMensagem {
    decodificar(WAMensagem.self, mensagemJSON(id, conversa: conversa, deMim: deMim, ts: ts, texto: texto,
                                              status: deMim ? "enviada" : nil))
}

private func conversa(_ jid: String, ts: Int, naoLidas: Int = 0) -> WAConversa {
    decodificar(WAConversa.self, conversaJSON(jid, ts: ts, naoLidas: naoLidas))
}

private func conta(_ numero: String, padrao: Bool, estado: String) -> WAConta {
    decodificar(WAConta.self, contaJSON(numero, padrao: padrao, estado: estado))
}

// MARK: - transporte falso

private struct Pedido {
    let metodo: String
    let caminho: String
    let query: [String: String]
    let corpo: [String: Any]

    /// `conta` da query (GET) ou do corpo (POST).
    var conta: String? { query["conta"] ?? corpo["conta"] as? String }
}

/// Responde por caminho, grava cada pedido e segura os que o teste mandar
/// segurar até `soltar`. O cliente chama `enviar` fora do main actor: tudo
/// passa pela trava.
private final class TransporteFalso: WATransporte {
    private let trava = NSLock()
    private var _pedidos: [Pedido] = []
    private var segurados: Set<String> = []
    private var liberados: Set<String> = []
    private var presos: [String: CheckedContinuation<Void, Never>] = [:]
    private var _contas: [String] = [contaJSON(A, padrao: true), contaJSON(B, padrao: false)]
    private var falharUmaVez: Set<String> = []
    private var enviados = 0

    var pedidos: [Pedido] { trava.lock(); defer { trava.unlock() }; return _pedidos }
    func limpar() { trava.lock(); _pedidos = []; trava.unlock() }
    func definirContas(_ c: [String]) { trava.lock(); _contas = c; trava.unlock() }
    /// O próximo envio com esse texto responde `502 whatsapp_recusou`.
    func falharEnvio(de texto: String) { trava.lock(); falharUmaVez.insert(texto); trava.unlock() }

    func de(_ caminho: String, conta: String? = nil) -> [Pedido] {
        pedidos.filter { $0.caminho == caminho && (conta == nil || $0.conta == conta) }
    }
    func indice(_ caminho: String, conta: String? = nil) -> Int? {
        pedidos.firstIndex { $0.caminho == caminho && (conta == nil || $0.conta == conta) }
    }

    /// Segura o próximo pedido nesse caminho (de qualquer conta, ou só da `conta`).
    func segurar(_ caminho: String, conta: String? = nil) {
        trava.lock(); segurados.insert(caminho + "|" + (conta ?? "*")); trava.unlock()
    }
    func soltar(_ caminho: String, conta: String? = nil) {
        let k = caminho + "|" + (conta ?? "*")
        trava.lock()
        let c = presos.removeValue(forKey: k)
        if c == nil { liberados.insert(k) }
        trava.unlock()
        c?.resume()
    }

    func enviar(_ pedido: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let comps = URLComponents(url: pedido.url!, resolvingAgainstBaseURL: false)!
        var q: [String: String] = [:]
        for item in comps.queryItems ?? [] { q[item.name] = item.value ?? "" }
        let corpo = pedido.httpBody.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } ?? [:]
        let p = Pedido(metodo: pedido.httpMethod ?? "GET", caminho: comps.path, query: q, corpo: corpo)

        if let k = registrar(p) {
            await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
                trava.lock()
                if liberados.remove(k) != nil {
                    trava.unlock(); c.resume()
                } else {
                    presos[k] = c; trava.unlock()
                }
            }
        }

        let (status, texto) = responder(p)
        let r = HTTPURLResponse(url: pedido.url!, statusCode: status, httpVersion: "HTTP/1.1",
                                headerFields: ["Content-Type": "application/json"])!
        return (Data(texto.utf8), r)
    }

    /// Grava o pedido; devolve a chave de `segurar` que ele casou, se casou.
    private func registrar(_ p: Pedido) -> String? {
        trava.lock(); defer { trava.unlock() }
        _pedidos.append(p)
        for k in [p.caminho + "|" + (p.conta ?? ""), p.caminho + "|*"] where segurados.contains(k) {
            segurados.remove(k)
            return k
        }
        return nil
    }

    private func responder(_ p: Pedido) -> (Int, String) {
        trava.lock(); defer { trava.unlock() }
        switch (p.metodo, p.caminho) {
        case ("GET", "/v1/contas"):
            return (200, #"{"ok": true, "contas": [\#(_contas.joined(separator: ", "))]}"#)
        case ("GET", "/v1/conversas"):
            let lista: [String]
            switch p.query["conta"] {
            case A?: lista = [conversaJSON(X, ts: 300, naoLidas: 1), conversaJSON(Y, ts: 200)]
            case B?: lista = [conversaJSON(Z, ts: 250)]
            default: lista = []
            }
            return (200, #"{"ok": true, "conversas": [\#(lista.joined(separator: ", "))], "antes": null}"#)
        case ("GET", "/v1/pareamento"):
            return (404, #"{"ok": false, "erro": "sem_pareamento", "detalhe": "nada em andamento"}"#)
        case ("GET", "/v1/mensagens"):
            let jid = p.query["conversa"] ?? ""
            let msgs: [String]
            var antes: String? = nil
            switch (jid, p.query["antes"]) {
            case (X, nil):
                msgs = [mensagemJSON("m1", conversa: X, ts: 100, texto: "primeira"),
                        mensagemJSON("m2", conversa: X, ts: 110, texto: "segunda")]
                antes = "cur-1"
            case (X, "cur-1"?):
                msgs = [mensagemJSON("m0", conversa: X, ts: 50, texto: "a mais velha")]
            case (Y, nil):
                msgs = [mensagemJSON("y1", conversa: Y, ts: 90)]
            default:
                msgs = []
            }
            return (200, #"{"ok": true, "conversa": \#(js(jid)), "mensagens": [\#(msgs.joined(separator: ", "))], "antes": \#(js(antes))}"#)
        case ("GET", "/v1/conversa"):
            return (404, #"{"ok": false, "erro": "conversa_inexistente", "detalhe": "x"}"#)
        case ("POST", "/v1/lida"):
            return (200, #"{"ok": true, "marcadas": 1}"#)
        case ("POST", "/v1/reagir"):
            return (200, #"{"ok": true}"#)
        case ("POST", "/v1/enviar/texto"):
            let texto = p.corpo["texto"] as? String ?? ""
            if falharUmaVez.remove(texto) != nil {
                return (502, #"{"ok": false, "erro": "whatsapp_recusou", "detalhe": "recusado"}"#)
            }
            enviados += 1
            let ref = p.corpo["ref"] as? String
            let para = p.corpo["para"] as? String ?? ""
            let m = mensagemJSON("3EB-ENV-\(enviados)", conversa: para, deMim: true,
                                 remetente: (p.conta ?? A) + "@s.whatsapp.net",
                                 ts: Int(Date().timeIntervalSince1970), texto: texto, status: "enviada")
            return (200, #"{"ok": true, "ref": \#(js(ref)), "mensagem": \#(m)}"#)
        default:
            return (404, #"{"ok": false, "erro": "rota_inexistente", "detalhe": "x"}"#)
        }
    }
}

// MARK: - canal falso

private final class CanalFalso: WACanalProtocolo {
    var aoEvento: ((WAEvento) -> Void)?
    var aoRessincronizar: ((String, Int) -> Void)?
    var aoMudarEstado: ((WAEstadoDoCanal) -> Void)?
    private(set) var iniciados = 0
    private(set) var parados = 0

    func iniciar() { iniciados += 1 }
    /// Como o `WACanal` de verdade: parar avisa `.parado`.
    func parar() { parados += 1; aoMudarEstado?(.parado) }
    func acordou() {}

    func mudar(_ e: WAEstadoDoCanal) { aoMudarEstado?(e) }
    func entregar(_ e: WAEvento) { aoEvento?(e) }
    func ressincronizar(_ jornal: String, _ seq: Int) { aoRessincronizar?(jornal, seq) }
}

// MARK: - montagem

private let pastaBase = URL(fileURLWithPath: NSTemporaryDirectory())
    .appendingPathComponent("whatsappstorecheck-\(getpid())", isDirectory: true)
private let arquivoDaChave: URL = {
    let u = pastaBase.appendingPathComponent("api-key")
    try! FileManager.default.createDirectory(at: pastaBase, withIntermediateDirectories: true)
    try! Data("chave-de-teste\n".utf8).write(to: u)
    return u
}()

@MainActor
private final class Montagem {
    let t = TransporteFalso()
    var canais: [CanalFalso] = []
    var chegadas: [(WAMensagem, WAConversa, WAConta?)] = []
    var store: WhatsAppStore!

    init() {
        let cliente = WACliente(porta: 18099, caminhoDaChave: arquivoDaChave, transporte: t)
        store = WhatsAppStore(cliente: cliente, fabricaDeCanal: { [unowned self] _ in
            let c = CanalFalso()
            self.canais.append(c)
            return c
        })
        store.aoChegarMensagem = { [unowned self] m, c, conta in self.chegadas.append((m, c, conta)) }
    }

    func canal(linha: UInt = #line) -> CanalFalso {
        exigir(!canais.isEmpty, "nenhum canal foi criado", linha: linha)
        return canais.last!
    }
}

/// Espera a condição virar verdadeira (até 3 s), cedendo o main actor.
@MainActor
private func esperar(_ desc: String, linha: UInt = #line, _ cond: () -> Bool) async {
    for _ in 0..<3000 {
        if cond() { return }
        try? await Task.sleep(nanoseconds: 1_000_000)
    }
    exigir(cond(), "esperou 3 s e não aconteceu: \(desc)", linha: linha)
}

/// Deixa as tarefas pendentes rodarem: base das provas de "não aconteceu".
@MainActor
private func assentar() async {
    for _ in 0..<60 { try? await Task.sleep(nanoseconds: 1_000_000) }
}

/// Store com canal aberto e a primeira carga terminada; pedidos zerados.
@MainActor
private func montarPronta(linha: UInt = #line) async -> Montagem {
    let m = Montagem()
    await m.store.iniciar()
    m.canal(linha: linha).mudar(.aberto)
    await esperar("primeira carga terminar em .pronta", linha: linha) { m.store.conexao == .pronta }
    await assentar()
    m.t.limpar()
    return m
}

@MainActor
private func bolha(_ s: WhatsAppStore, _ k: WAChave, texto: String) -> WABolha? {
    s.estado.bolhas(de: k).last { $0.mensagem.texto == texto }
}

private func evMensagem(_ seq: Int, _ m: WAMensagem, _ c: WAConversa, conta: String = A,
                        ref: String? = nil) -> WAEvento {
    .numerado(seq: seq, conta: conta, ts: 1_762_270_500, .mensagem(m, c, ref: ref))
}

// MARK: - casos

/// Recém-criado: inerte, sem pedido e sem canal; `_zerar()` devolve a isso.
@MainActor
private func inerteAoNascer() async {
    let m = Montagem()
    exigir(m.store.conexao == .inerte, "store novo deveria estar .inerte, está \(m.store.conexao)")
    exigir(!m.store.canalAberto, "store novo com canal aberto")
    exigir(!m.store.ponteConectada, "store novo com ponte conectada")
    exigir(m.store.estado == WAEstado(), "store novo com estado não vazio")
    await assentar()
    exigir(m.t.pedidos.isEmpty, "o init fez \(m.t.pedidos.count) pedido(s) HTTP: \(m.t.pedidos.map(\.caminho))")
    exigir(m.canais.isEmpty, "o init criou canal")

    // depois de uso, _zerar volta ao recém-criado
    let p = await montarPronta()
    p.store.definirRascunho("rascunho velho", para: kX)
    await p.store.abrir(kX)
    exigir(p.store.conexao == .pronta && p.store.canalAberto, "montagem pronta")
    p.store._zerar()
    exigir(p.store.conexao == .inerte, "_zerar deveria voltar a .inerte, está \(p.store.conexao)")
    exigir(!p.store.canalAberto, "_zerar deixou o canal como aberto")
    exigir(!p.store.ponteConectada, "_zerar deixou a ponte conectada")
    exigir(p.store.estado == WAEstado(), "_zerar deixou estado (contas/conversas/rascunho)")
    exigir(p.store.rascunho(kX) == "", "_zerar deixou o rascunho")
}

/// `iniciar()` cria um canal, chama `iniciar()` nele uma vez, não pede nada
/// antes de o canal abrir, e espelha os estados de falha do canal.
@MainActor
private func iniciarEspelhaOCanal() async {
    let m = Montagem()
    await m.store.iniciar()
    exigir(m.canais.count == 1, "iniciar() deveria criar 1 canal, criou \(m.canais.count)")
    exigir(m.canal().iniciados == 1, "iniciar() deveria chamar iniciar() no canal 1 vez, chamou \(m.canal().iniciados)")
    await assentar()
    exigir(m.t.pedidos.isEmpty,
           "antes de o canal abrir não sai pedido HTTP; saíram \(m.t.pedidos.map(\.caminho))")

    let casos: [(WAEstadoDoCanal, WAConexao)] = [
        (.semChave, .semChave), (.foraDoAr, .foraDoAr), (.chaveNaoConfere, .chaveNaoConfere),
        (.incompativel(2), .incompativel(2)),
    ]
    for (doCanal, esperado) in casos {
        m.canal().mudar(doCanal)
        await esperar("canal \(doCanal) → conexao \(esperado)") { m.store.conexao == esperado }
        exigir(!m.store.canalAberto, "canal \(doCanal) não é canal aberto")
        exigir(!m.store.ponteConectada, "canal \(doCanal) não é ponte conectada")
    }
    await assentar()
    exigir(m.t.pedidos.isEmpty, "estados de falha do canal não pedem nada; saíram \(m.t.pedidos.map(\.caminho))")

    // start() só dispara o iniciar(), sem nada antes
    let s = Montagem()
    s.store.start()
    await esperar("start() criar o canal e iniciá-lo") { s.canais.count == 1 && s.canais[0].iniciados == 1 }
    await assentar()
    exigir(s.canais.count == 1, "start() criou \(s.canais.count) canais")
    exigir(s.t.pedidos.isEmpty, "start() sem canal aberto pediu \(s.t.pedidos.map(\.caminho))")
}

/// Primeira abertura: .carregando, contas → conversas de cada conta + pareamento,
/// e só então .pronta com as conversas no estado.
@MainActor
private func primeiraAbertura() async {
    let m = Montagem()
    await m.store.iniciar()
    m.t.segurar("/v1/contas")
    m.canal().mudar(.aberto)
    await esperar("pedido de /v1/contas ao abrir o canal") { !m.t.de("/v1/contas").isEmpty }
    exigir(m.store.conexao == .carregando, "com /v1/contas em voo a conexão é .carregando, está \(m.store.conexao)")
    exigir(m.store.canalAberto, "canal .aberto deveria marcar canalAberto")
    exigir(!m.store.ponteConectada, "sem contas lidas ainda não há ponte conectada")

    // segura as conversas da conta B: até elas chegarem, não está pronta
    m.t.segurar("/v1/conversas", conta: B)
    m.t.soltar("/v1/contas")
    await esperar("pedido de /v1/conversas da conta B") { !m.t.de("/v1/conversas", conta: B).isEmpty }
    await assentar()
    exigir(m.store.conexao == .carregando,
           "com /v1/conversas de uma conta em voo ainda é .carregando, está \(m.store.conexao)")
    m.t.soltar("/v1/conversas", conta: B)
    await esperar("terminar em .pronta") { m.store.conexao == .pronta }
    await assentar()

    let ps = m.t.pedidos
    exigir(ps.first?.caminho == "/v1/contas", "o primeiro pedido é /v1/contas; veio \(ps.map(\.caminho))")
    exigir(ps.first?.metodo == "GET", "/v1/contas é GET")
    for c in [A, B] {
        let n = m.t.de("/v1/conversas", conta: c).count
        exigir(n == 1, "/v1/conversas da conta \(c) deveria sair 1 vez, saiu \(n)")
    }
    exigir(m.t.de("/v1/pareamento").count == 1, "/v1/pareamento deveria sair 1 vez; veio \(ps.map(\.caminho))")
    exigir(m.t.de("/v1/pareamento")[0].metodo == "GET", "/v1/pareamento na carga é GET (nunca inicia pareamento)")
    exigir(m.t.de("/v1/mensagens").isEmpty, "a carga não lê mensagens de conversa nenhuma")
    exigir(m.t.de("/v1/lida").isEmpty, "a carga nunca marca lida")

    exigir(m.store.estado.contas.map(\.conta) == [A, B], "contas no estado: \(m.store.estado.contas.map(\.conta))")
    exigir(m.store.estado.conversas(da: A).map(\.jid) == [X, Y],
           "conversas da conta A no estado: \(m.store.estado.conversas(da: A).map(\.jid))")
    exigir(m.store.estado.conversas(da: B).map(\.jid) == [Z],
           "conversas da conta B no estado: \(m.store.estado.conversas(da: B).map(\.jid))")
    exigir(m.store.ponteConectada, "canal aberto e conta conectada = ponte conectada")
}

/// Reabertura depois de queda (sem ressincronize): só /v1/contas e /v1/pareamento.
@MainActor
private func reaberturaDepoisDeQueda() async {
    let m = await montarPronta()
    await m.store.abrir(kX)
    await assentar()
    m.t.limpar()

    m.canal().mudar(.foraDoAr)
    await esperar("queda → conexao .foraDoAr") { m.store.conexao == .foraDoAr }
    exigir(!m.store.canalAberto, "canal caiu: canalAberto deveria ser false")
    exigir(!m.store.ponteConectada, "canal caiu: ponte não está conectada")
    m.canal().mudar(.conectando)
    m.canal().mudar(.aberto)
    await esperar("reabertura reler /v1/contas e /v1/pareamento") {
        !m.t.de("/v1/contas").isEmpty && !m.t.de("/v1/pareamento").isEmpty
    }
    await esperar("reabertura voltar a .pronta") { m.store.conexao == .pronta }
    await assentar()
    exigir(m.t.de("/v1/contas").count == 1, "reabertura relê /v1/contas uma vez, leu \(m.t.de("/v1/contas").count)")
    exigir(m.t.de("/v1/conversas").isEmpty,
           "reabertura sem ressincronize não relê /v1/conversas; pediu \(m.t.de("/v1/conversas").count)")
    exigir(m.t.de("/v1/mensagens").isEmpty, "reabertura sem ressincronize não relê /v1/mensagens")
    exigir(m.store.estado.conversas(da: A).map(\.jid) == [X, Y], "as conversas ficam no estado depois da queda")
    exigir(m.store.estado.carregada(kX), "a conversa aberta continua carregada depois da queda")
    exigir(m.store.ponteConectada, "reaberto e com conta conectada: ponte conectada de novo")
}

/// `ponteConectada` só com canal aberto E alguma conta conectada.
@MainActor
private func ponteConectada() async {
    let m = Montagem()
    func estado(_ contas: [WAConta]) -> WAEstado { var e = WAEstado(); e.substituirContas(contas); return e }
    let conectada = conta(A, padrao: true, estado: "conectada")
    let deslogada = conta(B, padrao: false, estado: "deslogada")
    let desconectada = conta(A, padrao: true, estado: "desconectada")

    m.store._injetar(estado: estado([conectada]), conexao: .pronta, canalAberto: false)
    exigir(!m.store.ponteConectada, "conta conectada com canal fechado não é ponte conectada")
    m.store._injetar(estado: estado([desconectada, deslogada]), conexao: .pronta, canalAberto: true)
    exigir(!m.store.ponteConectada, "canal aberto sem conta conectada não é ponte conectada")
    m.store._injetar(estado: estado([]), conexao: .pronta, canalAberto: true)
    exigir(!m.store.ponteConectada, "canal aberto sem conta nenhuma não é ponte conectada")
    m.store._injetar(estado: estado([conectada, deslogada]), conexao: .pronta, canalAberto: true)
    exigir(m.store.ponteConectada, "canal aberto e uma conta conectada é ponte conectada")
    exigir(m.store.conexao == .pronta && m.store.canalAberto, "_injetar aplica conexao e canalAberto")
}

/// Mensagem recebida chama `aoChegarMensagem` uma vez; repetida e minha, não.
@MainActor
private func chegadaDeMensagem() async {
    let m = await montarPronta()
    let recebida = mensagem("3EB-NOVA-1", ts: 400, texto: "chegou")
    let cv = conversa(X, ts: 400, naoLidas: 3)
    m.canal().entregar(evMensagem(10, recebida, cv))
    await esperar("aoChegarMensagem para a mensagem recebida") { !m.chegadas.isEmpty }
    exigir(m.chegadas.count == 1, "aoChegarMensagem chamado \(m.chegadas.count) vezes")
    let (mm, cc, ct) = m.chegadas[0]
    exigir(mm.id == "3EB-NOVA-1" && mm.texto == "chegou", "aoChegarMensagem recebeu a mensagem errada: \(mm.id)")
    exigir(cc.jid == X && cc.naoLidas == 3, "aoChegarMensagem recebeu a conversa errada: \(cc.jid)")
    exigir(ct?.conta == A, "aoChegarMensagem deveria receber a conta \(A), recebeu \(String(describing: ct?.conta))")
    exigir(m.store.estado.conversas(da: A).first?.jid == X && m.store.estado.conversas(da: A).first?.naoLidas == 3,
           "a conversa da mensagem nova sobe com as não lidas do evento")

    // o mesmo evento de novo
    m.canal().entregar(evMensagem(10, recebida, cv))
    m.canal().entregar(evMensagem(11, recebida, cv))
    await assentar()
    exigir(m.chegadas.count == 1, "mensagem repetida chamou aoChegarMensagem de novo (\(m.chegadas.count) vezes)")

    // mensagem minha (enviada do celular) não é chegada
    let minha = mensagem("3EB-MINHA-1", deMim: true, ts: 410, texto: "fui eu")
    m.canal().entregar(evMensagem(12, minha, conversa(X, ts: 410, naoLidas: 0)))
    await assentar()
    exigir(m.chegadas.count == 1, "mensagem de_mim true chamou aoChegarMensagem")
    exigir(m.store.estado.conversas(da: A).first?.naoLidas == 0, "evento de mensagem minha também atualiza a conversa")

    // e outra recebida, de outra conta, chega com a conta certa
    m.canal().entregar(evMensagem(13, mensagem("3EB-NOVA-2", conversa: Z, ts: 420), conversa(Z, ts: 420, naoLidas: 1),
                                  conta: B))
    await esperar("aoChegarMensagem da conta B") { m.chegadas.count == 2 }
    exigir(m.chegadas[1].2?.conta == B, "mensagem da conta B chegou com a conta \(String(describing: m.chegadas[1].2?.conta))")
    exigir(m.t.de("/v1/lida").isEmpty, "mensagem que chega nunca marca lida sozinha")
}

/// `abrir` lê a página uma vez e nunca marca lida; `carregarMais` usa o `antes`.
@MainActor
private func abrirECarregarMais() async {
    let m = await montarPronta()
    exigir(!m.store.estado.carregada(kX), "conversa sem bolhas antes de abrir")
    await m.store.abrir(kX)
    await esperar("abrir ler /v1/mensagens") { !m.t.de("/v1/mensagens").isEmpty }
    let p = m.t.de("/v1/mensagens")[0]
    exigir(p.metodo == "GET" && p.query["conta"] == A && p.query["conversa"] == X,
           "/v1/mensagens com conta e conversa: \(p.query)")
    exigir(p.query["antes"] == nil, "a primeira página vai sem antes; veio \(String(describing: p.query["antes"]))")
    await esperar("as bolhas aparecerem") { m.store.estado.bolhas(de: kX).count == 2 }
    exigir(m.store.estado.bolhas(de: kX).map(\.id) == ["m1", "m2"],
           "bolhas da conversa aberta: \(m.store.estado.bolhas(de: kX).map(\.id))")

    await m.store.abrir(kX)
    await assentar()
    exigir(m.t.de("/v1/mensagens").count == 1,
           "abrir de novo não lê outra vez; /v1/mensagens saiu \(m.t.de("/v1/mensagens").count) vezes")

    await m.store.carregarMais(kX)
    await esperar("carregarMais ler a página anterior") { m.t.de("/v1/mensagens").count == 2 }
    let q = m.t.de("/v1/mensagens")[1]
    exigir(q.query["antes"] == "cur-1", "carregarMais usa o antes da página; veio \(String(describing: q.query["antes"]))")
    exigir(q.query["conta"] == A && q.query["conversa"] == X, "carregarMais na mesma conversa: \(q.query)")
    await esperar("a página mais velha entrar") { m.store.estado.bolhas(de: kX).count == 3 }
    exigir(m.store.estado.bolhas(de: kX).map(\.id) == ["m0", "m1", "m2"],
           "página antiga junta na frente: \(m.store.estado.bolhas(de: kX).map(\.id))")

    await assentar()
    exigir(m.t.de("/v1/lida").isEmpty, "abrir e carregarMais nunca marcam lida")
}

/// `marcarLida` → POST /v1/lida com {conta, conversa}.
@MainActor
private func marcarLida() async {
    let m = await montarPronta()
    await m.store.marcarLida(kX)
    await esperar("POST /v1/lida") { !m.t.de("/v1/lida").isEmpty }
    await assentar()
    let ls = m.t.de("/v1/lida")
    exigir(ls.count == 1, "marcarLida saiu \(ls.count) vezes")
    exigir(ls[0].metodo == "POST", "/v1/lida é POST")
    exigir(ls[0].corpo["conta"] as? String == A && ls[0].corpo["conversa"] as? String == X,
           "corpo de /v1/lida com conta e conversa: \(ls[0].corpo)")
}

/// Envio: enviando antes da resposta, enviada depois, e só então POST /v1/lida.
/// Falha deixa .falhou sem lida; retentar reenvia com ref novo.
@MainActor
private func enviarTexto() async {
    let m = await montarPronta()
    await m.store.abrir(kX)
    m.t.limpar()

    m.t.segurar("/v1/enviar/texto")
    let tarefa = Task { await m.store.enviarTexto("oi", para: kX, citando: nil) }
    await esperar("POST /v1/enviar/texto") { !m.t.de("/v1/enviar/texto").isEmpty }
    let e = m.t.de("/v1/enviar/texto")[0]
    exigir(e.metodo == "POST", "/v1/enviar/texto é POST")
    exigir(e.corpo["conta"] as? String == A && e.corpo["para"] as? String == X && e.corpo["texto"] as? String == "oi",
           "corpo do envio com conta, para e texto: \(e.corpo)")
    exigir(e.corpo["citar"] == nil || e.corpo["citar"] is NSNull, "envio sem citação não manda citar")
    let ref1 = e.corpo["ref"] as? String ?? ""
    exigir(ref1.hasPrefix("k-") && ref1.count <= 64, "ref do envio no formato k-N, até 64 caracteres; veio '\(ref1)'")

    await esperar("bolha enviando antes da resposta") { bolha(m.store, kX, texto: "oi") != nil }
    let b = bolha(m.store, kX, texto: "oi")!
    exigir(m.store.estado.estadoDaBolha(b) == .enviando, "antes da resposta a bolha é .enviando, é \(m.store.estado.estadoDaBolha(b))")
    exigir(b.mensagem.deMim, "bolha local é de mim")
    exigir(b.mensagem.remetente == A, "remetente da bolha local é o número da conta; veio \(b.mensagem.remetente)")
    exigir(m.store.estado.bolhas(de: kX).last?.id == b.id, "a bolha enviando vai pro fim da conversa")
    await assentar()
    exigir(m.t.de("/v1/lida").isEmpty, "não marca lida antes de o envio dar certo")

    m.t.soltar("/v1/enviar/texto")
    await tarefa.value
    await esperar("bolha virar enviada") {
        guard let b = bolha(m.store, kX, texto: "oi") else { return false }
        return m.store.estado.estadoDaBolha(b) == .enviada
    }
    exigir(bolha(m.store, kX, texto: "oi")?.id == "3EB-ENV-1", "a bolha enviada é a mensagem real da resposta")
    exigir(m.store.estado.bolhas(de: kX).filter { $0.mensagem.texto == "oi" }.count == 1,
           "uma bolha só depois da confirmação")
    await esperar("POST /v1/lida depois do envio") { !m.t.de("/v1/lida").isEmpty }
    await assentar()
    let ls = m.t.de("/v1/lida")
    exigir(ls.count == 1, "um /v1/lida por envio, saíram \(ls.count)")
    exigir(ls[0].corpo["conta"] as? String == A && ls[0].corpo["conversa"] as? String == X,
           "/v1/lida da conversa respondida: \(ls[0].corpo)")
    exigir(m.t.indice("/v1/lida")! > m.t.indice("/v1/enviar/texto")!, "/v1/lida sai depois do envio")

    // envio com 502: .falhou e sem lida
    m.t.limpar()
    m.t.falharEnvio(de: "vai falhar")
    await m.store.enviarTexto("vai falhar", para: kX, citando: nil)
    await esperar("bolha virar .falhou") {
        guard let b = bolha(m.store, kX, texto: "vai falhar") else { return false }
        return m.store.estado.estadoDaBolha(b) == .falhou
    }
    await assentar()
    exigir(m.t.de("/v1/lida").isEmpty, "envio que falhou não marca lida")
    exigir(m.t.de("/v1/enviar/texto").count == 1, "falha não reenvia sozinha; saíram \(m.t.de("/v1/enviar/texto").count)")
    let ref2 = m.t.de("/v1/enviar/texto")[0].corpo["ref"] as? String ?? ""
    exigir(ref2.hasPrefix("k-") && ref2 != ref1, "cada envio tem ref próprio: '\(ref1)' e '\(ref2)'")
    let idLocal = bolha(m.store, kX, texto: "vai falhar")!.id

    await m.store.retentar(idLocal: idLocal, em: kX)
    await esperar("retentar reenviar") { m.t.de("/v1/enviar/texto").count == 2 }
    let r = m.t.de("/v1/enviar/texto")[1]
    let ref3 = r.corpo["ref"] as? String ?? ""
    exigir(r.corpo["texto"] as? String == "vai falhar" && r.corpo["para"] as? String == X,
           "retentar reenvia o mesmo texto pra mesma conversa: \(r.corpo)")
    exigir(ref3.hasPrefix("k-") && ref3 != ref2 && ref3 != ref1, "retentar usa ref novo; veio '\(ref3)' (falhou com '\(ref2)')")
    await esperar("bolha retentada virar enviada") {
        guard let b = bolha(m.store, kX, texto: "vai falhar") else { return false }
        return m.store.estado.estadoDaBolha(b) == .enviada
    }
    exigir(m.store.estado.bolhas(de: kX).filter { $0.mensagem.texto == "vai falhar" }.count == 1,
           "retentar não duplica a bolha")

    // citação vai como citar
    m.t.limpar()
    let cit = WACitacao(id: "m1", remetente: X, texto: "primeira")
    await m.store.enviarTexto("respondendo", para: kX, citando: cit)
    await esperar("envio com citação") { !m.t.de("/v1/enviar/texto").isEmpty }
    exigir(m.t.de("/v1/enviar/texto")[0].corpo["citar"] as? String == "m1",
           "envio citando manda citar com o id citado: \(m.t.de("/v1/enviar/texto")[0].corpo)")
}

/// `reagir` → POST /v1/reagir.
@MainActor
private func reagir() async {
    let m = await montarPronta()
    await m.store.abrir(kX)
    m.t.limpar()
    await m.store.reagir("👍", a: "m1", em: kX)
    await esperar("POST /v1/reagir") { !m.t.de("/v1/reagir").isEmpty }
    let r = m.t.de("/v1/reagir")[0]
    exigir(r.metodo == "POST", "/v1/reagir é POST")
    exigir(r.corpo["conta"] as? String == A && r.corpo["conversa"] as? String == X
           && r.corpo["alvo"] as? String == "m1" && r.corpo["emoji"] as? String == "👍",
           "corpo de /v1/reagir: \(r.corpo)")
}

/// `ressincronize`: esvazia, relê contas, conversas de cada conta e mensagens
/// das conversas abertas (contadas por tela). `sincronizacao`: conversas da conta.
@MainActor
private func ressincronizeESincronizacao() async {
    let m = await montarPronta()
    // X aberta em duas telas e fechada numa: continua aberta. Y aberta e fechada.
    await m.store.abrir(kX)
    await m.store.abrir(kX)
    m.store.fechar(kX)
    await m.store.abrir(kY)
    m.store.fechar(kY)
    await esperar("Y carregada") { m.store.estado.carregada(kY) }
    await assentar()
    m.t.limpar()

    m.t.segurar("/v1/contas")
    m.canal().ressincronizar("jornal-novo", 900)
    await esperar("ressincronize reler /v1/contas") { !m.t.de("/v1/contas").isEmpty }
    exigir(m.store.estado.conversas(da: A).isEmpty && m.store.estado.conversas(da: B).isEmpty,
           "ressincronize esvazia as conversas antes de reler")
    exigir(!m.store.estado.carregada(kX), "ressincronize esvazia as bolhas antes de reler")
    m.t.soltar("/v1/contas")

    await esperar("ressincronize reler conversas das duas contas e a conversa aberta") {
        !m.t.de("/v1/conversas", conta: A).isEmpty && !m.t.de("/v1/conversas", conta: B).isEmpty
            && !m.t.de("/v1/mensagens").isEmpty
    }
    await esperar("conversas de volta no estado") { m.store.estado.conversas(da: A).map(\.jid) == [X, Y] }
    await esperar("conversa aberta recarregada") { m.store.estado.bolhas(de: kX).count == 2 }
    await assentar()
    exigir(m.t.indice("/v1/contas")! < m.t.indice("/v1/conversas")!, "contas antes das conversas")
    let ms = m.t.de("/v1/mensagens")
    exigir(ms.count == 1 && ms[0].query["conversa"] == X && ms[0].query["conta"] == A,
           "ressincronize relê só a conversa aberta (X, aberta em 2 telas e fechada em 1); leu \(ms.map { $0.query["conversa"] ?? "?" })")
    exigir(!m.store.estado.carregada(kY), "conversa fechada não volta carregada depois do ressincronize")
    exigir(m.store.estado.conversas(da: B).map(\.jid) == [Z], "conversas da conta B de volta")

    // sincronizacao da conta B relê só as conversas dela
    m.t.limpar()
    m.canal().entregar(.numerado(seq: 901, conta: B, ts: 1_762_270_600, .sincronizacao(conversas: 5)))
    await esperar("sincronizacao reler /v1/conversas da conta B") { !m.t.de("/v1/conversas", conta: B).isEmpty }
    await assentar()
    exigir(m.t.de("/v1/conversas", conta: A).isEmpty, "sincronizacao da conta B não relê a conta A")
    exigir(m.t.de("/v1/contas").isEmpty, "sincronizacao não relê /v1/contas")
}

/// Pareamento com sucesso relê /v1/contas e a conta nova aparece.
@MainActor
private func pareamentoSucesso() async {
    let m = await montarPronta()
    m.t.definirContas([contaJSON(A, padrao: true), contaJSON(B, padrao: false), contaJSON(NOVA, padrao: false)])
    let p = WAPareamento(id: "p-1", estado: .sucesso, qr: nil, qrExpiraEm: nil, fim: 1_762_270_720,
                         conta: NOVA, motivo: nil)
    m.canal().entregar(.pareamento(p))
    await esperar("pareamento sucesso reler /v1/contas") { !m.t.de("/v1/contas").isEmpty }
    await esperar("a conta pareada aparecer") { m.store.estado.contas.contains { $0.conta == NOVA } }
}

/// Rascunho sobrevive a fechar e a abrir outra conversa.
@MainActor
private func rascunho() async {
    let m = await montarPronta()
    await m.store.abrir(kX)
    m.store.definirRascunho("meio caminho", para: kX)
    exigir(m.store.rascunho(kX) == "meio caminho", "rascunho definido não volta")
    m.store.fechar(kX)
    await m.store.abrir(kY)
    exigir(m.store.rascunho(kX) == "meio caminho", "rascunho sumiu ao fechar e abrir outra conversa")
    exigir(m.store.rascunho(kY) == "", "conversa nova começa sem rascunho")
    await m.store.abrir(kX)
    exigir(m.store.rascunho(kX) == "meio caminho", "rascunho volta ao reabrir a conversa")
}

/// `stop()` para o canal; o que o canal entregar depois não muda nada.
@MainActor
private func stopSilencia() async {
    let m = await montarPronta()
    let c = m.canal()
    m.store.stop()
    exigir(c.parados == 1, "stop() deveria chamar parar() no canal 1 vez, chamou \(c.parados)")
    await assentar()
    let conexao = m.store.conexao
    let estado = m.store.estado
    let aberto = m.store.canalAberto
    m.t.limpar()

    c.entregar(evMensagem(50, mensagem("3EB-DEPOIS", ts: 900, texto: "tarde demais"), conversa(X, ts: 900, naoLidas: 9)))
    c.entregar(.numerado(seq: 51, conta: A, ts: 1, .sincronizacao(conversas: 2)))
    c.entregar(.pareamento(WAPareamento(id: "p-2", estado: .sucesso, qr: nil, qrExpiraEm: nil, fim: nil,
                                        conta: NOVA, motivo: nil)))
    c.ressincronizar("outro", 1)
    c.mudar(.aberto)
    c.mudar(.foraDoAr)
    await assentar()
    exigir(m.chegadas.isEmpty, "evento depois do stop chamou aoChegarMensagem")
    exigir(m.store.estado == estado, "evento depois do stop mudou o estado")
    exigir(m.store.conexao == conexao, "evento depois do stop mudou a conexão (\(conexao) → \(m.store.conexao))")
    exigir(m.store.canalAberto == aberto, "evento depois do stop mudou canalAberto")
    exigir(m.t.pedidos.isEmpty, "evento depois do stop fez pedido HTTP: \(m.t.pedidos.map(\.caminho))")
}

@main
enum Gate {
    @MainActor
    static func main() async {
        defer { try? FileManager.default.removeItem(at: pastaBase) }
        await inerteAoNascer()
        await iniciarEspelhaOCanal()
        await primeiraAbertura()
        await reaberturaDepoisDeQueda()
        await ponteConectada()
        await chegadaDeMensagem()
        await abrirECarregarMais()
        await marcarLida()
        await enviarTexto()
        await reagir()
        await ressincronizeESincronizacao()
        await pareamentoSucesso()
        await rascunho()
        await stopSilencia()
        try? FileManager.default.removeItem(at: pastaBase)
        print("whatsappstorecheck: ok")
    }
}
