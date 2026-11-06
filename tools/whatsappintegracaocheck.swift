// Gate da etapa 26 do WhatsApp: o card de chegada ligado ao app.
// `WhatsAppIntegracao` (Knobler/WhatsApp/WhatsAppIntegracao.swift) recebe a
// mensagem do store, monta o card UMA vez (fora do laço das telas), marca o
// evento `.whatsapp` em cada tela e entrega ao `publicar` do app; no
// WhatsAppStore, `responderCartao`/`dispensarCartao` e o `aoDispensarCartao`.
//
//   ver a linha `swift_teste tools/whatsappintegracaocheck.swift $VM_FONTES
//   $WA_NUCLEO Knobler/WhatsApp/WhatsAppCartao.swift
//   Knobler/WhatsApp/WhatsAppIntegracao.swift` em tools/check.sh.
//
// O que se prova (o que quem usa vê), com duas telas = dois `NotchViewModel`
// reais e um `publicar` falso que entrega o card a cada tela pelo `enqueue`
// (como o app faz quando não está silenciando):
//   - uma mensagem recebida vira UM card, o mesmo nas duas telas, promove a
//     seção do WhatsApp nas duas e vira uma linha no histórico;
//   - mensagem velha (> 120 s), minha ou apagada não vira card nem promove;
//   - três mensagens seguidas da mesma conversa: um card só na tela, com
//     "3 mensagens novas · …", e três linhas no histórico;
//   - conversa aberta na tela A: o card aparece só na B;
//   - `respondeu` some com o card daquela conversa nas duas telas (e só com
//     ele) e recomeça a contagem; `abrir` abre a conversa naquela tela;
//   - silêncio é do app: o `publicar` é chamado do mesmo jeito e a integração
//     não põe card em tela nenhuma por conta própria;
//   - responder pelo card: envia com a citação, marca lida e só então fecha o
//     card; envio recusado não marca lida, deixa a bolha "não enviada", não
//     fecha o card e devolve o texto ao campo; o X só fecha;
//   - integração ligada ao store como o app liga: a mensagem que chega pelo
//     canal aparece nas duas telas e responder some com ela nas duas.
//
// Nada sai pela rede: o cliente fala com um transporte falso que responde por
// caminho e grava cada pedido, e o canal é um falso cujos callbacks o teste
// dispara. A chave mora numa pasta de NSTemporaryDirectory(); a chave de
// verdade da ponte nunca é lida, e o `WhatsAppStore.shared` não é tocado. O
// histórico não grava em disco (`arquivo = nil`).

import AppKit

private func exigir(_ cond: Bool, _ msg: String, linha: UInt = #line) {
    if !cond {
        print("FALHOU: \(msg) (tools/whatsappintegracaocheck.swift:\(linha))")
        exit(1)
    }
}

// MARK: - números do teste (fictícios)

private let A = "554791744143"                       // conta
private let EU = A + "@s.whatsapp.net"
private let X = "554799990001@s.whatsapp.net"        // Marina (individual)
private let Y = "554799990002@s.whatsapp.net"        // Carlos (individual)
private let kX = WAChave(conta: A, jid: X)
private let kY = WAChave(conta: A, jid: Y)

private let contaA = WAConta(conta: A, jid: A + ":17@s.whatsapp.net", nome: "ZOI Business", padrao: true,
                             estado: .conectada, motivo: nil, desde: 1_762_000_000,
                             naoLidas: 0, conversasNaoLidas: 0)

private func conversa(_ jid: String, _ nome: String) -> WAConversa {
    WAConversa(jid: jid, jids: [jid], tipo: .individual, nome: nome, naoLidas: 1,
               marcadaNaoLida: false, ts: Int(Date().timeIntervalSince1970), ultima: nil)
}

private let cvX = conversa(X, "Marina Duarte")
private let cvY = conversa(Y, "Carlos")

private func msg(_ id: String, conversa: String = X, em quando: Date, deMim: Bool = false,
                 texto: String, apagada: Int? = nil) -> WAMensagem {
    WAMensagem(id: id, conversa: conversa, remetente: deMim ? EU : conversa, remetenteNome: nil,
               deMim: deMim, ts: Int(quando.timeIntervalSince1970), tipo: .texto, texto: texto,
               midia: nil, citacao: nil, reacoes: [], editada: nil, apagada: apagada, status: nil)
}

// MARK: - telas, relógio e publicar falsos

/// Relógio que o teste avança à mão.
@MainActor
private final class Relogio {
    var agora = Date()
    func avancar(_ s: TimeInterval) { agora = agora.addingTimeInterval(s) }
}

/// Duas telas, a integração e o `publicar` que grava cada chamada.
@MainActor
private final class Cena {
    let a = NotchViewModel()
    let b = NotchViewModel()
    let relogio = Relogio()
    var publicados: [NotchNotification] = []
    var integracao: WhatsAppIntegracao!

    /// `silenciando`: o `publicar` do app manda direto para o histórico.
    init(silenciando: Bool = false) {
        let telas = [a, b]
        integracao = WhatsAppIntegracao(
            telas: { telas },
            publicar: { [unowned self] card in
                self.publicados.append(card)
                if silenciando {
                    NotificationHistory.shared.record(card)
                } else {
                    for vm in telas { vm.enqueue(card) }
                }
            },
            agora: { [unowned self] in self.relogio.agora })
    }

    func chegou(_ m: WAMensagem, _ c: WAConversa = cvX) {
        integracao.chegou(mensagem: m, conversa: c, conta: contaA, numero: A)
    }
}

private func noHistorico(_ id: UUID) -> Int {
    NotificationHistory.shared.items.filter { $0.id == id }.count
}

/// Card aberto nesta tela, na seção do WhatsApp.
@MainActor
private func abrirNaSecao(_ vm: NotchViewModel) {
    vm.setExpandedDirect(true)
    vm.secoes = [.whatsapp, .musica]
    vm.focar(.whatsapp)
}

/// Cede o main actor (deixa rodar o `asyncAfter` de 0,35 s da fila).
@MainActor
private func dormir(_ s: Double) async {
    try? await Task.sleep(nanoseconds: UInt64(s * 1_000_000_000))
}

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

// MARK: - integração: chegada

/// Uma mensagem: um `publicar`, o mesmo card nas duas telas, seção promovida
/// nas duas, uma linha no histórico.
@MainActor
private func umaMensagem() {
    let c = Cena()
    let antes = NotificationHistory.shared.items.count
    exigir(c.a.eventos[.whatsapp] == nil && c.b.eventos[.whatsapp] == nil, "montagem: tela nasce com evento .whatsapp")

    c.chegou(msg("m1", em: c.relogio.agora, texto: "Fechado! Mando o briefing até sexta."))

    exigir(c.publicados.count == 1,
           "uma mensagem chamou publicar \(c.publicados.count) vezes (card montado dentro do laço das telas?)")
    guard let card = c.publicados.first else { return }
    exigir(card.whatsapp?.chave == kX.texto, "o card não é da conversa: chave \(String(describing: card.whatsapp?.chave))")
    exigir(card.body == "Fechado! Mando o briefing até sexta.", "corpo do card: \"\(card.body)\"")
    exigir(card.title == "Marina Duarte", "título do card: \"\(card.title)\"")
    exigir(c.a.activeNotification?.id == card.id, "o card não apareceu na tela A")
    exigir(c.b.activeNotification?.id == card.id, "o card não apareceu na tela B (ou é outro card, com outro id)")
    exigir(c.a.eventos[.whatsapp] != nil, "a mensagem não marcou o evento .whatsapp na tela A (seção não promove)")
    exigir(c.b.eventos[.whatsapp] != nil, "a mensagem não marcou o evento .whatsapp na tela B (seção não promove)")
    exigir(NotificationHistory.shared.items.count == antes + 1,
           "o histórico ganhou \(NotificationHistory.shared.items.count - antes) linhas com uma mensagem")
    exigir(noHistorico(card.id) == 1, "o card não está no histórico")
}

/// Velha (> 120 s), minha ou apagada: nada de card, nada de promoção. E elas
/// não contam na rajada: a próxima mensagem de verdade é "1", não "4".
@MainActor
private func mensagensQueNaoViramCard() {
    let c = Cena()
    let antes = NotificationHistory.shared.items.count
    let agora = c.relogio.agora

    c.chegou(msg("v1", em: agora.addingTimeInterval(-121), texto: "de antes da ponte cair"))
    exigir(c.publicados.isEmpty, "mensagem com 121 s de idade virou card")
    c.chegou(msg("v2", em: agora, deMim: true, texto: "eu mesmo, do celular"))
    exigir(c.publicados.isEmpty, "mensagem minha (de_mim) virou card")
    c.chegou(msg("v3", em: agora, texto: "", apagada: Int(agora.timeIntervalSince1970)))
    exigir(c.publicados.isEmpty, "mensagem apagada virou card")

    exigir(c.a.activeNotification == nil && c.b.activeNotification == nil, "mensagem ignorada apareceu numa tela")
    exigir(c.a.eventos[.whatsapp] == nil && c.b.eventos[.whatsapp] == nil,
           "mensagem ignorada promoveu a seção do WhatsApp (marcou evento)")
    exigir(NotificationHistory.shared.items.count == antes, "mensagem ignorada entrou no histórico")

    c.chegou(msg("v4", em: agora, texto: "agora sim"))
    exigir(c.publicados.count == 1, "mensagem recente depois das ignoradas não virou card")
    exigir(c.publicados.first?.body == "agora sim",
           "as mensagens ignoradas contaram na rajada: corpo \"\(c.publicados.first?.body ?? "")\"")
}

/// Três mensagens da mesma conversa em 20 s: um card só na tela, com a
/// contagem; três linhas no histórico.
@MainActor
private func rajadaDeTres() async {
    let c = Cena()
    let antes = NotificationHistory.shared.items.count

    c.chegou(msg("r1", em: c.relogio.agora, texto: "Bora pedalar sábado?"))
    c.relogio.avancar(10)
    c.chegou(msg("r2", em: c.relogio.agora, texto: "Saio às 6"))
    c.relogio.avancar(10)
    c.chegou(msg("r3", em: c.relogio.agora, texto: "Bora pedalar sábado cedo?"))

    exigir(c.publicados.count == 3, "três mensagens chamaram publicar \(c.publicados.count) vezes")
    let corpos = c.publicados.map(\.body)
    exigir(corpos.first == "Bora pedalar sábado?", "primeira da rajada: \"\(corpos.first ?? "")\"")
    exigir(corpos.count == 3 && corpos[1] == "2 mensagens novas · Saio às 6", "segunda da rajada: \(corpos)")
    for (nome, vm) in [("A", c.a), ("B", c.b)] {
        let body = vm.activeNotification?.body ?? ""
        exigir(body.hasPrefix("3 mensagens novas · "),
               "tela \(nome): o card deveria começar por \"3 mensagens novas · \", veio \"\(body)\"")
        exigir(vm.activeNotification?.id == c.publicados.last?.id, "tela \(nome) não mostra o card da última mensagem")
    }

    exigir(NotificationHistory.shared.items.count == antes + 3,
           "a rajada deveria deixar 3 linhas no histórico, deixou \(NotificationHistory.shared.items.count - antes)")
    for card in c.publicados {
        exigir(noHistorico(card.id) == 1, "a mensagem \"\(card.body)\" sumiu do histórico (uma apagou a anterior?)")
    }

    // um card só: fechar não revela outro da mesma conversa empilhado atrás
    for vm in [c.a, c.b] { vm.dismissActiveNotification() }
    await dormir(0.6)
    exigir(c.a.activeNotification == nil && c.b.activeNotification == nil,
           "a rajada empilhou cards: fechar o card mostrou outro (\(c.a.activeNotification?.body ?? c.b.activeNotification?.body ?? ""))")
}

/// Conversa aberta na tela A: o card aparece só na B.
@MainActor
private func conversaAbertaNumaTela() {
    let c = Cena()
    abrirNaSecao(c.a)
    c.a.whatsappConversaAberta = kX.texto
    exigir(c.a.expanded && c.a.focus == .whatsapp, "montagem: tela A não ficou na seção do WhatsApp")
    let antes = NotificationHistory.shared.items.count

    c.chegou(msg("s1", em: c.relogio.agora, texto: "tá vendo aí?"))
    exigir(c.publicados.count == 1, "publicar chamado \(c.publicados.count) vezes")
    exigir(c.a.activeNotification == nil, "o card apareceu na tela que está com a conversa aberta")
    exigir(c.b.activeNotification?.whatsapp?.chave == kX.texto, "o card não apareceu na tela B")
    exigir(NotificationHistory.shared.items.count == antes + 1, "a mensagem não foi para o histórico uma vez")
}

/// `respondeu` fecha o card dessa conversa nas duas telas, só ele, e a
/// contagem recomeça; `abrir` abre a conversa na tela.
@MainActor
private func respondeuEAbrir() async {
    let c = Cena()
    // tela B com outro card na frente: o de X entra na fila dela
    let outro = NotchNotification(appName: "Mail", title: "Boleto", body: "vence hoje")
    c.b.enqueue(outro)

    c.chegou(msg("p1", em: c.relogio.agora, texto: "oi"))
    c.relogio.avancar(5)
    c.chegou(msg("p2", em: c.relogio.agora, texto: "tudo certo?"))
    exigir(c.a.activeNotification?.body.hasPrefix("2 mensagens novas · ") == true,
           "montagem: segunda mensagem não contou, veio \"\(c.a.activeNotification?.body ?? "")\"")
    exigir(c.b.activeNotification?.id == outro.id, "montagem: tela B deveria seguir com o card do Mail")

    c.integracao.respondeu(chave: kX.texto)
    exigir(c.a.activeNotification == nil, "respondeu não fechou o card da conversa na tela A")
    exigir(c.b.activeNotification?.id == outro.id, "respondeu fechou o card de outra coisa na tela B")

    // a contagem recomeça: a próxima mensagem não é "3 mensagens novas"
    c.relogio.avancar(5)
    c.chegou(msg("p3", em: c.relogio.agora, texto: "valeu"))
    exigir(c.publicados.last?.body == "valeu",
           "respondeu não zerou a contagem da conversa: \"\(c.publicados.last?.body ?? "")\"")

    // card nas duas telas: respondeu fecha nas duas
    let d = Cena()
    d.chegou(msg("q1", em: d.relogio.agora, texto: "oi"))
    exigir(d.a.activeNotification != nil && d.b.activeNotification != nil, "montagem: card não chegou às duas telas")
    d.integracao.respondeu(chave: kY.texto)
    exigir(d.a.activeNotification != nil && d.b.activeNotification != nil, "respondeu de outra conversa fechou o card")
    d.integracao.respondeu(chave: kX.texto)
    exigir(d.a.activeNotification == nil, "respondeu não fechou o card na tela A")
    exigir(d.b.activeNotification == nil, "respondeu não fechou o card na tela B")

    // abrir: dispensa o card, grava conversa e conta na tela, pede foco
    let e = Cena()
    e.chegou(msg("o1", em: e.relogio.agora, texto: "me liga"))
    e.integracao.abrir(chave: kX.texto, conta: A, em: e.a)
    exigir(e.a.activeNotification == nil, "abrir não dispensou o card naquela tela")
    exigir(e.a.whatsappConversaAberta == kX.texto, "abrir não abriu a conversa na tela: \(String(describing: e.a.whatsappConversaAberta))")
    exigir(e.a.whatsappContaSelecionada == A, "abrir não selecionou a conta: \(String(describing: e.a.whatsappContaSelecionada))")
    exigir(e.a.expanded, "abrir não abriu o notch")
    exigir(e.a.focus == .whatsapp || e.a.focoPendente == .whatsapp,
           "abrir não pediu foco na seção do WhatsApp: foco \(String(describing: e.a.focus))")
    exigir(e.b.whatsappConversaAberta == nil, "abrir numa tela abriu a conversa na outra")
    await dormir(0.5)
}

/// Silenciando, o `publicar` do app manda direto para o histórico: a
/// integração chama do mesmo jeito e não põe card em tela nenhuma sozinha.
@MainActor
private func silenciando() {
    let c = Cena(silenciando: true)
    let antes = NotificationHistory.shared.items.count
    c.chegou(msg("z1", em: c.relogio.agora, texto: "em reunião"))
    exigir(c.publicados.count == 1, "silenciando: publicar chamado \(c.publicados.count) vezes (o silêncio é do app)")
    exigir(c.a.activeNotification == nil && c.b.activeNotification == nil,
           "silenciando: o card apareceu na tela sem passar pelo publicar")
    exigir(NotificationHistory.shared.items.count == antes + 1, "silenciando: a mensagem não foi para o histórico")
}

// MARK: - transporte e canal falsos

private func js(_ s: String?) -> String {
    guard let s else { return "null" }
    let d = try! JSONSerialization.data(withJSONObject: [s], options: [.fragmentsAllowed])
    let t = String(decoding: d, as: UTF8.self)
    return String(t.dropFirst().dropLast())
}

private func mensagemJSON(_ id: String, conversa: String, deMim: Bool = false, ts: Int,
                          texto: String, status: String? = nil) -> String {
    let r = deMim ? EU : conversa
    return #"{"id": \#(js(id)), "conversa": \#(js(conversa)), "remetente": \#(js(r)), "remetente_nome": null, "de_mim": \#(deMim), "ts": \#(ts), "tipo": "texto", "texto": \#(js(texto)), "midia": null, "citacao": null, "reacoes": [], "editada": null, "apagada": null, "status": \#(js(status))}"#
}

private func conversaJSON(_ jid: String, nome: String, ts: Int) -> String {
    #"{"jid": \#(js(jid)), "jids": [\#(js(jid))], "tipo": "individual", "nome": \#(js(nome)), "nao_lidas": 1, "marcada_nao_lida": false, "ts": \#(ts), "ultima": null}"#
}

private struct Pedido {
    let metodo: String
    let caminho: String
    let query: [String: String]
    let corpo: [String: Any]
}

/// Linha do tempo única: pedidos HTTP e chamadas do `aoDispensarCartao`.
private final class Linha {
    private let trava = NSLock()
    private var _itens: [String] = []
    var itens: [String] { trava.lock(); defer { trava.unlock() }; return _itens }
    func anotar(_ s: String) { trava.lock(); _itens.append(s); trava.unlock() }
    func limpar() { trava.lock(); _itens = []; trava.unlock() }
}

private final class TransporteFalso: WATransporte {
    let linha: Linha
    private let trava = NSLock()
    private var _pedidos: [Pedido] = []
    private var _falhar = false
    private var enviados = 0

    init(linha: Linha) { self.linha = linha }

    var pedidos: [Pedido] { trava.lock(); defer { trava.unlock() }; return _pedidos }
    func de(_ caminho: String) -> [Pedido] { pedidos.filter { $0.caminho == caminho } }
    func limpar() { trava.lock(); _pedidos = []; trava.unlock() }
    /// O próximo `POST /v1/enviar/texto` responde 502.
    var falhar: Bool {
        get { trava.lock(); defer { trava.unlock() }; return _falhar }
        set { trava.lock(); _falhar = newValue; trava.unlock() }
    }

    func enviar(_ pedido: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let comps = URLComponents(url: pedido.url!, resolvingAgainstBaseURL: false)!
        var q: [String: String] = [:]
        for item in comps.queryItems ?? [] { q[item.name] = item.value ?? "" }
        let corpo = pedido.httpBody.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } ?? [:]
        let p = Pedido(metodo: pedido.httpMethod ?? "GET", caminho: comps.path, query: q, corpo: corpo)
        registrar(p)
        let (status, texto) = responder(p)
        let r = HTTPURLResponse(url: pedido.url!, statusCode: status, httpVersion: "HTTP/1.1",
                                headerFields: ["Content-Type": "application/json"])!
        return (Data(texto.utf8), r)
    }

    private func registrar(_ p: Pedido) {
        trava.lock(); _pedidos.append(p); trava.unlock()
        linha.anotar("\(p.metodo) \(p.caminho)")
    }

    private func responder(_ p: Pedido) -> (Int, String) {
        trava.lock(); defer { trava.unlock() }
        let agora = Int(Date().timeIntervalSince1970)
        switch (p.metodo, p.caminho) {
        case ("GET", "/v1/contas"):
            return (200, #"{"ok": true, "contas": [{"conta": \#(js(A)), "jid": \#(js(A + ":17@s.whatsapp.net")), "nome": "ZOI Business", "padrao": true, "estado": "conectada", "motivo": null, "desde": 1762270000, "nao_lidas": 1, "conversas_nao_lidas": 1}]}"#)
        case ("GET", "/v1/conversas"):
            let lista = p.query["conta"] == A
                ? [conversaJSON(X, nome: "Marina Duarte", ts: agora - 30), conversaJSON(Y, nome: "Carlos", ts: agora - 60)]
                : []
            return (200, #"{"ok": true, "conversas": [\#(lista.joined(separator: ", "))], "antes": null}"#)
        case ("GET", "/v1/pareamento"):
            return (404, #"{"ok": false, "erro": "sem_pareamento", "detalhe": "nada em andamento"}"#)
        case ("GET", "/v1/mensagens"):
            let jid = p.query["conversa"] ?? ""
            let msgs = jid == X
                ? [mensagemJSON("m1", conversa: X, ts: agora - 90, texto: "Oi! Tudo certo pra sexta?"),
                   mensagemJSON("m2", conversa: X, ts: agora - 30, texto: "Fechado! Mando o briefing até sexta.")]
                : []
            return (200, #"{"ok": true, "conversa": \#(js(jid)), "mensagens": [\#(msgs.joined(separator: ", "))], "antes": null}"#)
        case ("POST", "/v1/enviar/texto"):
            if _falhar {
                _falhar = false
                return (502, #"{"ok": false, "erro": "whatsapp_recusou", "detalhe": "recusado"}"#)
            }
            enviados += 1
            let ref = p.corpo["ref"] as? String
            let m = mensagemJSON("3EB-ENV-\(enviados)", conversa: p.corpo["para"] as? String ?? "", deMim: true,
                                 ts: agora, texto: p.corpo["texto"] as? String ?? "", status: "enviada")
            return (200, #"{"ok": true, "ref": \#(js(ref)), "mensagem": \#(m)}"#)
        case ("POST", "/v1/lida"):
            return (200, #"{"ok": true, "marcadas": 1}"#)
        default:
            return (404, #"{"ok": false, "erro": "rota_inexistente", "detalhe": "x"}"#)
        }
    }
}

private final class CanalFalso: WACanalProtocolo {
    var aoEvento: ((WAEvento) -> Void)?
    var aoRessincronizar: ((String, Int) -> Void)?
    var aoMudarEstado: ((WAEstadoDoCanal) -> Void)?
    func iniciar() {}
    func parar() { aoMudarEstado?(.parado) }
    func acordou() {}
    func mudar(_ e: WAEstadoDoCanal) { aoMudarEstado?(e) }
    func entregar(_ e: WAEvento) { aoEvento?(e) }
}

private let pastaBase = URL(fileURLWithPath: NSTemporaryDirectory())
    .appendingPathComponent("whatsappintegracaocheck-\(getpid())", isDirectory: true)
private let arquivoDaChave: URL = {
    let u = pastaBase.appendingPathComponent("api-key")
    try! FileManager.default.createDirectory(at: pastaBase, withIntermediateDirectories: true)
    try! Data("chave-de-teste\n".utf8).write(to: u)
    return u
}()

/// Store com transporte e canal falsos, canal aberto, primeira carga feita,
/// conversa X carregada; `aoDispensarCartao` anota na linha do tempo.
@MainActor
private final class Loja {
    let linha = Linha()
    let t: TransporteFalso
    var canais: [CanalFalso] = []
    var dispensados: [String] = []
    var store: WhatsAppStore!

    init() {
        t = TransporteFalso(linha: linha)
        let cliente = WACliente(porta: 18099, caminhoDaChave: arquivoDaChave, transporte: t)
        store = WhatsAppStore(cliente: cliente, fabricaDeCanal: { [unowned self] _ in
            let c = CanalFalso()
            self.canais.append(c)
            return c
        })
        store.pastaDeEnvio = pastaBase.appendingPathComponent("envio", isDirectory: true)
        store.aoDispensarCartao = { [unowned self] chave in
            self.dispensados.append(chave)
            self.linha.anotar("dispensar \(chave)")
        }
    }

    func pronta() async {
        await store.iniciar()
        exigir(!canais.isEmpty, "montagem: o store não criou o canal")
        canais.last!.mudar(.aberto)
        await esperar("primeira carga terminar em .pronta") { self.store.conexao == .pronta }
        await assentar()
        await store.abrir(kX)
        exigir(store.estado.bolhas(de: kX).contains { $0.id == "m2" }, "montagem: a conversa X não carregou")
        t.limpar()
        linha.limpar()
    }

    /// m2 da conversa X, como carregada.
    var m2: WAMensagem { store.estado.bolhas(de: kX).first { $0.id == "m2" }!.mensagem }
}

// MARK: - store: resposta pelo card

/// Responder pelo card: envia com a citação, marca lida e só então fecha o
/// card, uma vez.
@MainActor
private func responderPeloCartao() async {
    let l = Loja()
    await l.pronta()
    let s = l.store!
    s.citar(l.m2, em: kX)
    s.definirRascunho("Perfeito, obrigado!", para: kX)

    await s.responderCartao(chave: kX, texto: "Perfeito, obrigado!")
    await assentar()

    let envios = l.t.de("/v1/enviar/texto")
    exigir(envios.count == 1, "responder pelo card: 1 POST /v1/enviar/texto, foram \(envios.count)")
    if let p = envios.first {
        exigir(p.metodo == "POST", "envio com método \(p.metodo)")
        exigir(p.corpo["conta"] as? String == A, "envio com conta \(String(describing: p.corpo["conta"]))")
        exigir(p.corpo["para"] as? String == X, "envio para \(String(describing: p.corpo["para"]))")
        exigir(p.corpo["texto"] as? String == "Perfeito, obrigado!", "envio com texto \(String(describing: p.corpo["texto"]))")
        exigir(p.corpo["citar"] as? String == "m2",
               "a resposta pelo card não levou a citação guardada (citar = m2): \(String(describing: p.corpo["citar"]))")
        exigir(!((p.corpo["ref"] as? String) ?? "").isEmpty, "envio sem ref: \(String(describing: p.corpo["ref"]))")
    }
    let lidas = l.t.de("/v1/lida")
    exigir(lidas.count == 1, "responder pelo card deveria marcar lida uma vez, foram \(lidas.count) POST /v1/lida")
    if let p = lidas.first {
        exigir(p.corpo["conta"] as? String == A && p.corpo["conversa"] as? String == X,
               "POST /v1/lida com corpo errado: \(p.corpo)")
    }
    exigir(l.dispensados == [kX.texto],
           "aoDispensarCartao deveria ser chamado uma vez com \(kX.texto), veio \(l.dispensados)")
    let esperado = ["POST /v1/enviar/texto", "POST /v1/lida", "dispensar \(kX.texto)"]
    exigir(l.linha.itens == esperado, "ordem: esperado \(esperado), veio \(l.linha.itens)")
    exigir(s.rascunho(kX) == "", "depois de responder, o campo não esvaziou: \"\(s.rascunho(kX))\"")
    exigir(s.citacao(kX) == nil, "depois de responder, a citação continuou: \(String(describing: s.citacao(kX)))")
}

/// Envio recusado (502): não marca lida, bolha "não enviada", card fica e o
/// texto volta ao campo.
@MainActor
private func responderQueFalha() async {
    let l = Loja()
    await l.pronta()
    let s = l.store!
    s.definirRascunho("Perfeito, obrigado!", para: kX)
    l.t.falhar = true

    await s.responderCartao(chave: kX, texto: "Perfeito, obrigado!")
    await assentar()

    exigir(l.t.de("/v1/enviar/texto").count == 1, "montagem: o envio não saiu")
    exigir(l.t.de("/v1/lida").isEmpty, "envio recusado (502) e mesmo assim marcou lida")
    let b = s.estado.bolhas(de: kX).last { $0.mensagem.texto == "Perfeito, obrigado!" }
    var falhou = false
    if case .falhou? = b?.envio { falhou = true }
    exigir(falhou, "envio recusado: a bolha deveria ficar .falhou, veio \(String(describing: b?.envio))")
    exigir(l.dispensados.isEmpty, "envio recusado fechou o card (aoDispensarCartao chamado: \(l.dispensados))")
    exigir(s.rascunho(kX) == "Perfeito, obrigado!",
           "envio recusado: o texto tem que continuar no campo para tentar de novo, veio \"\(s.rascunho(kX))\"")
}

/// O X do card: só chama o callback, uma vez, sem rede.
@MainActor
private func xDoCartao() async {
    let l = Loja()
    await l.pronta()
    l.store.dispensarCartao(chave: kX.texto)
    await assentar()
    exigir(l.dispensados == [kX.texto], "dispensarCartao deveria chamar aoDispensarCartao uma vez, veio \(l.dispensados)")
    exigir(l.t.pedidos.isEmpty, "dispensarCartao fez pedido HTTP: \(l.t.pedidos.map { "\($0.metodo) \($0.caminho)" })")
}

/// Ligada como o app liga: a mensagem que chega pelo canal aparece nas duas
/// telas; responder pelo card some com ele nas duas.
@MainActor
private func ligadaComoOApp() async {
    let l = Loja()
    await l.pronta()
    let s = l.store!
    let a = NotchViewModel(), b = NotchViewModel()
    let telas = [a, b]
    var publicados = 0
    let integracao = WhatsAppIntegracao(telas: { telas },
                                        publicar: { card in publicados += 1; for vm in telas { vm.enqueue(card) } })
    s.aoChegarMensagem = { m, c, conta in
        integracao.chegou(mensagem: m, conversa: c, conta: conta, numero: conta?.conta ?? "")
    }
    s.aoDispensarCartao = { integracao.respondeu(chave: $0) }

    let agora = Int(Date().timeIntervalSince1970)
    let nova = WAMensagem(id: "m9", conversa: X, remetente: X, remetenteNome: nil, deMim: false, ts: agora,
                          tipo: .texto, texto: "Consegue me mandar o orçamento?", midia: nil, citacao: nil,
                          reacoes: [], editada: nil, apagada: nil, status: nil)
    l.canais.last!.entregar(.numerado(seq: 900, conta: A, ts: agora, .mensagem(nova, cvX, ref: nil)))
    await esperar("o card da mensagem do canal aparecer nas duas telas") {
        a.activeNotification?.whatsapp?.chave == kX.texto && b.activeNotification?.whatsapp?.chave == kX.texto
    }
    exigir(publicados == 1, "uma mensagem do canal chamou publicar \(publicados) vezes")

    await s.responderCartao(chave: kX, texto: "Mando já")
    await assentar()
    exigir(a.activeNotification == nil, "respondi pelo card e ele continuou na tela A")
    exigir(b.activeNotification == nil, "respondi pelo card e ele continuou na tela B")
    exigir(l.t.de("/v1/lida").count == 1, "responder pelo card ligado ao app não marcou lida uma vez")
}

// MARK: - main

@main
enum Gate {
    @MainActor
    static func main() async {
        defer { try? FileManager.default.removeItem(at: pastaBase) }
        // hermético: nada do histórico real entra nem sai
        NotificationHistory.shared.arquivo = nil
        NotificationHistory.shared.limpar()
        UserDefaults.standard.set(NotchSectionOrder.padrao.map(\.rawValue), forKey: "notchSectionOrder")
        UserDefaults.standard.set([String](), forKey: "notchSectionsFixadas")

        umaMensagem()
        mensagensQueNaoViramCard()
        await rajadaDeTres()
        conversaAbertaNumaTela()
        await respondeuEAbrir()
        silenciando()
        await responderPeloCartao()
        await responderQueFalha()
        await xDoCartao()
        await ligadaComoOApp()
        print("whatsappintegracaocheck ok")
    }
}
