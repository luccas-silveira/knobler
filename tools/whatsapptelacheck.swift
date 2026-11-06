// Gate da etapa 22 do WhatsApp: a seção de duas colunas decidida fora da view
// (Knobler/WhatsApp/WhatsAppTela.swift) e a paginação da lista de conversas
// (`WhatsAppStore.carregarMaisConversas`).
//
//   ver a linha `swift_teste tools/whatsapptelacheck.swift $VM_FONTES $WA_NUCLEO
//   Knobler/WhatsApp/WhatsAppTela.swift` em tools/check.sh.
//
// O que se prova:
//   - `WhatsAppTela.direita`: o que a coluna direita mostra para cada estado da
//     conexão, da conta e do pareamento; a conversa que aparece por padrão;
//   - `WhatsAppTela.conversaEfetiva`, `esquerda`, `contaInicial`,
//     `precisaIniciarPareamento` e o `sinalDaFaixa` (número do ícone na faixa);
//   - `WhatsAppTela.adotarPadrao`: a conversa que aparece por padrão vira a
//     conversa aberta da tela — carrega as bolhas uma vez, nunca marca lida, e
//     o card dela não desce por cima naquela tela (só na outra);
//   - `carregarMaisConversas(conta:)`: pede a página seguinte com o cursor da
//     conta, acrescenta sem repetir e para no fim.
//
// Nada sai pela rede: o cliente fala com um transporte falso que responde por
// caminho e grava cada pedido; o canal é um falso cujos callbacks o teste
// dispara. A chave mora numa pasta de NSTemporaryDirectory(); a chave de
// verdade da ponte nunca é lida, e o `WhatsAppStore.shared` não é tocado.
// O histórico persiste em disco: `arquivo = nil` antes de qualquer card.

import AppKit

private func exigir(_ cond: Bool, _ msg: String, linha: UInt = #line) {
    if !cond {
        print("FALHOU: \(msg) (tools/whatsapptelacheck.swift:\(linha))")
        exit(1)
    }
}

// MARK: - números do teste (fictícios, como no mockup)

private let C4143 = "554791744143"   // ZOI Business, padrão
private let C8292 = "554792508292"   // Pessoal
private let MARINA = "554799990010@s.whatsapp.net"  // a mais recente da 4143
private let CARLOS = "554799990011@s.whatsapp.net"
private let FAMILIA = "554799990012@s.whatsapp.net" // só na segunda página
private let RAFA = "554799990013@s.whatsapp.net"    // da 8292

private let kMarina = WAChave(conta: C4143, jid: MARINA)
private let kCarlos = WAChave(conta: C4143, jid: CARLOS)
private let kRafa = WAChave(conta: C8292, jid: RAFA)

// MARK: - JSON do contrato

private func js(_ s: String?) -> String {
    guard let s else { return "null" }
    let d = try! JSONSerialization.data(withJSONObject: [s], options: [.fragmentsAllowed])
    let t = String(decoding: d, as: UTF8.self)
    return String(t.dropFirst().dropLast())
}

private func contaJSON(_ numero: String, padrao: Bool, estado: String = "conectada",
                       conversasNaoLidas: Int = 0) -> String {
    #"{"conta": \#(js(numero)), "jid": \#(js(numero + ":17@s.whatsapp.net")), "nome": null, "padrao": \#(padrao), "estado": \#(js(estado)), "motivo": null, "desde": 1762270000, "nao_lidas": \#(conversasNaoLidas), "conversas_nao_lidas": \#(conversasNaoLidas)}"#
}

private func conversaJSON(_ jid: String, nome: String, ts: Int, naoLidas: Int = 0) -> String {
    #"{"jid": \#(js(jid)), "jids": [\#(js(jid))], "tipo": "individual", "nome": \#(js(nome)), "nao_lidas": \#(naoLidas), "marcada_nao_lida": false, "ts": \#(ts), "ultima": null}"#
}

private func pareamentoJSON(_ estado: String) -> String {
    #"{"id": "p-1", "estado": \#(js(estado)), "qr": "2@abc", "qr_expira_em": 1762270160, "fim": null, "conta": null, "motivo": null}"#
}

private func mensagemJSON(_ id: String, conversa: String, ts: Int) -> String {
    #"{"id": \#(js(id)), "conversa": \#(js(conversa)), "remetente": \#(js(conversa)), "remetente_nome": null, "de_mim": false, "ts": \#(ts), "tipo": "texto", "texto": "oi", "midia": null, "citacao": null, "reacoes": [], "editada": null, "apagada": null, "status": null}"#
}

private func decodificar<T: Decodable>(_ tipo: T.Type, _ json: String) -> T {
    do { return try WAJSON.decodificador.decode(tipo, from: Data(json.utf8)) } catch {
        print("FALHOU: fixture não decodifica como \(tipo): \(error) (tools/whatsapptelacheck.swift)")
        exit(1)
    }
}

private func conta(_ numero: String, padrao: Bool, estado: String = "conectada",
                   conversasNaoLidas: Int = 0) -> WAConta {
    decodificar(WAConta.self, contaJSON(numero, padrao: padrao, estado: estado,
                                        conversasNaoLidas: conversasNaoLidas))
}

private func conversa(_ jid: String, _ nome: String, ts: Int) -> WAConversa {
    decodificar(WAConversa.self, conversaJSON(jid, nome: nome, ts: ts))
}

private func pareamento(_ estado: String) -> WAPareamento {
    decodificar(WAPareamento.self, pareamentoJSON(estado))
}

// MARK: - transporte falso

private struct Pedido {
    let metodo: String
    let caminho: String
    let query: [String: String]
    let corpo: [String: Any]

    var conta: String? { query["conta"] ?? corpo["conta"] as? String }
}

/// Responde por caminho e grava cada pedido. A 4143 tem duas páginas de
/// conversas (`antes "c1"`, depois `antes null`); a 8292, uma só.
private final class TransporteFalso: WATransporte {
    private let trava = NSLock()
    private var _pedidos: [Pedido] = []
    /// `GET /v1/mensagens` responde 502: a conversa fica sem bolhas.
    var mensagensFalham = false

    var pedidos: [Pedido] { trava.lock(); defer { trava.unlock() }; return _pedidos }
    func limpar() { trava.lock(); _pedidos = []; trava.unlock() }
    func de(_ metodo: String, _ caminho: String) -> [Pedido] {
        pedidos.filter { $0.metodo == metodo && $0.caminho == caminho }
    }

    func enviar(_ pedido: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let comps = URLComponents(url: pedido.url!, resolvingAgainstBaseURL: false)!
        var q: [String: String] = [:]
        for item in comps.queryItems ?? [] { q[item.name] = item.value ?? "" }
        let corpo = pedido.httpBody.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } ?? [:]
        let p = Pedido(metodo: pedido.httpMethod ?? "GET", caminho: comps.path, query: q, corpo: corpo)
        let (status, texto) = responder(p, mensagensFalham: registrar(p))
        let r = HTTPURLResponse(url: pedido.url!, statusCode: status, httpVersion: "HTTP/1.1",
                                headerFields: ["Content-Type": "application/json"])!
        return (Data(texto.utf8), r)
    }

    /// Grava o pedido; devolve se `GET /v1/mensagens` deve falhar agora.
    private func registrar(_ p: Pedido) -> Bool {
        trava.lock(); defer { trava.unlock() }
        _pedidos.append(p)
        return mensagensFalham
    }

    private func responder(_ p: Pedido, mensagensFalham: Bool) -> (Int, String) {
        switch (p.metodo, p.caminho) {
        case ("GET", "/v1/contas"):
            return (200, #"{"ok": true, "contas": [\#(contaJSON(C4143, padrao: true)), \#(contaJSON(C8292, padrao: false))]}"#)
        case ("GET", "/v1/conversas"):
            let lista: [String]
            var antes: String? = nil
            switch (p.query["conta"], p.query["antes"]) {
            case (C4143?, nil):
                lista = [conversaJSON(MARINA, nome: "Marina Duarte", ts: 300),
                         conversaJSON(CARLOS, nome: "Carlos (Seller Veículos)", ts: 200)]
                antes = "c1"
            case (C4143?, "c1"?):
                // o Carlos volta na página seguinte: não pode aparecer duas vezes
                lista = [conversaJSON(CARLOS, nome: "Carlos (Seller Veículos)", ts: 200),
                         conversaJSON(FAMILIA, nome: "Família", ts: 100)]
            case (C8292?, nil):
                lista = [conversaJSON(RAFA, nome: "Rafa Lima", ts: 250)]
            default:
                lista = []
            }
            return (200, #"{"ok": true, "conversas": [\#(lista.joined(separator: ", "))], "antes": \#(js(antes))}"#)
        case ("GET", "/v1/pareamento"):
            return (404, #"{"ok": false, "erro": "sem_pareamento", "detalhe": "nada em andamento"}"#)
        case ("GET", "/v1/mensagens"):
            if mensagensFalham {
                return (502, #"{"ok": false, "erro": "whatsapp_recusou", "detalhe": "x"}"#)
            }
            let jid = p.query["conversa"] ?? ""
            let m = mensagemJSON("m-\(jid.prefix(12))", conversa: jid, ts: 290)
            return (200, #"{"ok": true, "conversa": \#(js(jid)), "mensagens": [\#(m)], "antes": null}"#)
        case ("POST", "/v1/lida"):
            return (200, #"{"ok": true, "marcadas": 1}"#)
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

    func iniciar() {}
    func parar() { aoMudarEstado?(.parado) }
    func acordou() {}
    func mudar(_ e: WAEstadoDoCanal) { aoMudarEstado?(e) }
}

// MARK: - montagem

private let pastaBase = URL(fileURLWithPath: NSTemporaryDirectory())
    .appendingPathComponent("whatsapptelacheck-\(getpid())", isDirectory: true)
private let arquivoDaChave: URL = {
    let u = pastaBase.appendingPathComponent("api-key")
    try! FileManager.default.createDirectory(at: pastaBase, withIntermediateDirectories: true)
    try! Data("chave-de-teste\n".utf8).write(to: u)
    return u
}()

@MainActor
private final class Montagem {
    let t = TransporteFalso()
    var canal: CanalFalso?
    var store: WhatsAppStore!

    init() {
        let cliente = WACliente(porta: 18099, caminhoDaChave: arquivoDaChave, transporte: t)
        store = WhatsAppStore(cliente: cliente, fabricaDeCanal: { [unowned self] _ in
            let c = CanalFalso()
            self.canal = c
            return c
        })
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

/// Store com o canal aberto e a primeira carga (contas, primeira página de
/// conversas de cada conta) terminada; pedidos zerados.
@MainActor
private func montarPronta(linha: UInt = #line) async -> Montagem {
    let m = Montagem()
    await m.store.iniciar()
    exigir(m.canal != nil, "montagem: store não criou o canal", linha: linha)
    m.canal!.mudar(.aberto)
    await esperar("primeira carga terminar em .pronta", linha: linha) { m.store.conexao == .pronta }
    await esperar("conversas da 4143 carregadas", linha: linha) {
        m.store.estado.conversas(da: C4143).count == 2
    }
    await assentar()
    exigir(m.store.estado.conversas(da: C4143).first?.jid == MARINA,
           "montagem: a Marina deveria ser a mais recente da 4143", linha: linha)
    m.t.limpar()
    return m
}

/// Tela com a seção do WhatsApp aberta e em foco, na conta 4143.
@MainActor
private func telaNaSecao(conta: String? = C4143) -> NotchViewModel {
    let vm = NotchViewModel()
    vm.setExpandedDirect(true)
    vm.secoes = [.whatsapp, .musica]
    vm.focus = .whatsapp
    vm.whatsappContaSelecionada = conta
    exigir(vm.expanded && vm.focus == .whatsapp, "montagem: a tela não ficou na seção do WhatsApp")
    return vm
}

private func cartaoDaMarina(_ texto: String) -> NotchNotification {
    NotchNotification(
        appName: "WhatsApp", title: "Marina Duarte", body: texto, subtitle: "4143",
        whatsapp: CartaoWhatsApp(chave: kMarina.texto, conta: C4143, jid: MARINA,
                                 rotuloDaConta: "4143", grupo: nil, contagem: 1,
                                 temMiniatura: false, mensagemID: UUID().uuidString))
}

// MARK: - coluna direita (puro)

private let contaOk = conta(C4143, padrao: true)
private let contaDeslogada = conta(C4143, padrao: true, estado: "deslogada")
private let duas = [conversa(MARINA, "Marina Duarte", ts: 300), conversa(CARLOS, "Carlos (Seller Veículos)", ts: 200)]

private func direita(_ conexao: WAConexao, conta: WAConta? = contaOk, pareamento: WAPareamento? = nil,
                     conversas: [WAConversa] = duas, aberta: WAChave? = nil) -> WATelaDireita {
    WhatsAppTela.direita(conexao: conexao, conta: conta, pareamento: pareamento,
                         conversas: conversas, aberta: aberta)
}

private func colunaDireita() {
    // a conexão vence o conteúdo: com conta conectada e conversas na mão,
    // ponte fora continua dizendo que a ponte está fora
    exigir(direita(.foraDoAr) == .ponteFora, "ponte fora: \(direita(.foraDoAr)), esperado .ponteFora")
    exigir(direita(.foraDoAr, conta: contaDeslogada, pareamento: pareamento("qr")) == .ponteFora,
           "ponte fora com conta deslogada não disse .ponteFora")
    exigir(direita(.chaveNaoConfere) == .chave(ausente: false),
           "chave recusada: \(direita(.chaveNaoConfere)), esperado .chave(ausente: false)")
    // arquivo da chave ausente: é a chave que não confere, nunca "ponte fora"
    exigir(direita(.semChave) == .chave(ausente: true),
           "sem arquivo de chave: \(direita(.semChave)), esperado .chave(ausente: true)")
    exigir(direita(.semChave) != .ponteFora, "sem arquivo de chave virou .ponteFora")
    exigir(direita(.incompativel(2)) == .incompativel,
           "contrato incompatível: \(direita(.incompativel(2))), esperado .incompativel")
    exigir(direita(.carregando) == .carregando, "carregando: \(direita(.carregando))")
    exigir(direita(.inerte) == .carregando, "peça recém-ligada (.inerte): \(direita(.inerte)), esperado .carregando")

    // conta deslogada: o QR, mesmo com conversas guardadas
    exigir(direita(.pronta, conta: contaDeslogada, pareamento: pareamento("qr")) == .qr,
           "deslogada com QR no ar: \(direita(.pronta, conta: contaDeslogada, pareamento: pareamento("qr")))")
    exigir(direita(.pronta, conta: contaDeslogada, pareamento: pareamento("expirado")) == .qrExpirado,
           "deslogada com QR expirado: \(direita(.pronta, conta: contaDeslogada, pareamento: pareamento("expirado")))")
    exigir(direita(.pronta, conta: contaDeslogada, pareamento: nil) == .qr,
           "deslogada sem pareamento: \(direita(.pronta, conta: contaDeslogada, pareamento: nil)), esperado .qr")
    exigir(WhatsAppTela.precisaIniciarPareamento(conta: contaDeslogada, pareamento: nil),
           "deslogada sem pareamento não pede para iniciar o pareamento")
    exigir(!WhatsAppTela.precisaIniciarPareamento(conta: contaDeslogada, pareamento: pareamento("qr")),
           "QR já no ar e mesmo assim pede outro pareamento")
    exigir(!WhatsAppTela.precisaIniciarPareamento(conta: contaOk, pareamento: nil),
           "conta conectada pedindo pareamento")

    // conta sem conversas
    exigir(direita(.pronta, conversas: []) == .vazio,
           "conta sem conversas: \(direita(.pronta, conversas: [])), esperado .vazio")

    // conversa aberta (não a mais recente) fica a aberta
    exigir(direita(.pronta, aberta: kCarlos) == .conversa(kCarlos),
           "conversa aberta (Carlos): \(direita(.pronta, aberta: kCarlos)), esperado .conversa(Carlos)")
    // nenhuma aberta: a mais recente
    exigir(direita(.pronta) == .conversa(kMarina),
           "nenhuma aberta: \(direita(.pronta)), esperado .conversa da Marina (a mais recente)")
    // aberta de outra conta não vale nesta
    exigir(direita(.pronta, aberta: kRafa) == .conversa(kMarina),
           "aberta da outra conta: \(direita(.pronta, aberta: kRafa)), esperado .conversa da Marina")
}

private func conversaEfetiva() {
    func ef(_ aberta: WAChave?, _ conta: String = C4143, _ cs: [WAConversa] = duas) -> WAChave? {
        WhatsAppTela.conversaEfetiva(aberta: aberta, conta: conta, conversas: cs)
    }
    exigir(ef(kCarlos) == kCarlos, "aberta da mesma conta: \(String(describing: ef(kCarlos))), esperado Carlos")
    exigir(ef(nil) == kMarina, "sem aberta: \(String(describing: ef(nil))), esperado a Marina (primeira)")
    exigir(ef(kRafa) == kMarina, "aberta de outra conta: \(String(describing: ef(kRafa))), esperado a Marina")
    exigir(ef(nil, C4143, []) == nil, "sem conversas: \(String(describing: ef(nil, C4143, []))), esperado nil")
    exigir(ef(kRafa, C4143, []) == nil, "sem conversas e aberta de outra conta: esperado nil")
    // a chave leva a conta pedida, não a da aberta
    exigir(ef(nil)?.conta == C4143, "a chave efetiva não é da conta pedida")

    // é sempre a mesma chave que `direita` mostra em .conversa
    for aberta in [nil, kCarlos, kMarina, kRafa] as [WAChave?] {
        let d = direita(.pronta, aberta: aberta)
        let e = ef(aberta)
        exigir(e.map { WATelaDireita.conversa($0) } == d,
               "direita (\(d)) e conversaEfetiva (\(String(describing: e))) discordam com aberta \(String(describing: aberta))")
    }
}

// MARK: - coluna esquerda, conta inicial e faixa (puro)

private func colunaEsquerda() {
    exigir(WhatsAppTela.esquerda(conta: contaDeslogada) == .semPareamento,
           "conta deslogada: a lista deveria dar lugar ao aviso de parear")
    exigir(WhatsAppTela.esquerda(conta: contaOk) == .lista, "conta conectada sem a lista")
    for e in ["desconectada", "conectando", "suspensa", "substituida"] {
        exigir(WhatsAppTela.esquerda(conta: conta(C4143, padrao: true, estado: e)) == .lista,
               "conta \(e): só a deslogada troca a lista pelo aviso")
    }
    exigir(WhatsAppTela.esquerda(conta: nil) == .lista, "sem conta: esperado .lista")
}

private func contaInicial() {
    // a padrão de propósito em segundo: quem pega a primeira erra
    let contas = [conta(C8292, padrao: false), conta(C4143, padrao: true)]
    exigir(WhatsAppTela.contaInicial(selecionada: C8292, contas: contas) == C8292,
           "selecionada que existe não foi mantida")
    exigir(WhatsAppTela.contaInicial(selecionada: nil, contas: contas) == C4143,
           "sem selecionada: \(String(describing: WhatsAppTela.contaInicial(selecionada: nil, contas: contas))), esperado a padrão 4143")
    exigir(WhatsAppTela.contaInicial(selecionada: "554700000000", contas: contas) == C4143,
           "selecionada que sumiu não voltou para a padrão")
    exigir(WhatsAppTela.contaInicial(selecionada: nil, contas: []) == nil, "sem contas: esperado nil")
    exigir(WhatsAppTela.contaInicial(selecionada: C4143, contas: []) == nil,
           "sem contas, a selecionada não pode valer")
}

private func sinalDaFaixa() {
    var e = WAEstado()
    e.substituirContas([conta(C4143, padrao: true, conversasNaoLidas: 3),
                        conta(C8292, padrao: false, conversasNaoLidas: 4)])
    exigir(e.sinalDaFaixa == 7, "faixa: \(e.sinalDaFaixa), esperado 7 (3 + 4 conversas não lidas)")
    e.substituirContas([conta(C4143, padrao: true), conta(C8292, padrao: false)])
    exigir(e.sinalDaFaixa == 0, "faixa sem não lidas: \(e.sinalDaFaixa), esperado 0 (nada desenhado)")
}

// MARK: - adotarPadrao (VM + store com transporte falso)

@MainActor
private func adotarPadrao() async {
    let m = await montarPronta()

    // controle: sem adotar, o card da Marina desce na tela com a seção aberta
    let controle = telaNaSecao()
    let c0 = cartaoDaMarina("antes de adotar")
    controle.enqueue(c0)
    exigir(controle.activeNotification?.id == c0.id,
           "montagem: sem conversa aberta o card da Marina deveria aparecer")

    let a = telaNaSecao(), b = NotchViewModel()
    exigir(a.whatsappConversaAberta == nil, "montagem: a tela A já nasceu com conversa aberta")
    await WhatsAppTela.adotarPadrao(vm: a, store: m.store)
    exigir(a.whatsappConversaAberta == kMarina.texto,
           "adotarPadrao gravou \(String(describing: a.whatsappConversaAberta)), esperado \(kMarina.texto)")
    await esperar("GET /v1/mensagens da Marina") { !m.t.de("GET", "/v1/mensagens").isEmpty }
    await assentar()
    let msgs = m.t.de("GET", "/v1/mensagens")
    exigir(msgs.count == 1, "adotarPadrao pediu \(msgs.count) página(s) de mensagens, esperado 1")
    exigir(msgs.first?.query["conversa"] == MARINA && msgs.first?.query["conta"] == C4143,
           "adotarPadrao pediu mensagens de \(String(describing: msgs.first?.query)), esperado a Marina na 4143")
    exigir(m.store.estado.carregada(kMarina), "as bolhas da Marina não carregaram")
    exigir(m.t.de("POST", "/v1/lida").isEmpty, "adotarPadrao marcou lida: abrir nunca marca lida")

    // o card da conversa que está na tela não desce nela, só na outra tela
    let c = cartaoDaMarina("chegou na conversa aberta")
    a.enqueue(c)
    b.enqueue(c)
    exigir(a.activeNotification == nil, "card da Marina desceu por cima da conversa aberta na tela A")
    exigir(b.activeNotification?.id == c.id, "card da Marina sumiu da tela B, que não tem a conversa aberta")

    // de novo: nada muda, nada é pedido
    await WhatsAppTela.adotarPadrao(vm: a, store: m.store)
    await assentar()
    exigir(a.whatsappConversaAberta == kMarina.texto, "a segunda chamada trocou a conversa aberta")
    exigir(m.t.de("GET", "/v1/mensagens").count == 1,
           "a segunda chamada pediu mensagens de novo (\(m.t.de("GET", "/v1/mensagens").count) no total)")
    exigir(m.t.de("POST", "/v1/lida").isEmpty, "a segunda chamada marcou lida")

    // com o Carlos já aberto, não troca para a mais recente
    let carlos = telaNaSecao()
    carlos.whatsappConversaAberta = kCarlos.texto
    await WhatsAppTela.adotarPadrao(vm: carlos, store: m.store)
    await assentar()
    exigir(carlos.whatsappConversaAberta == kCarlos.texto,
           "com o Carlos aberto, adotarPadrao trocou para \(String(describing: carlos.whatsappConversaAberta))")
    exigir(m.t.de("POST", "/v1/lida").isEmpty, "com o Carlos aberto, adotarPadrao marcou lida")

    // aberta de outra conta: a 4143 selecionada mostra (e abre) a Marina
    let outra = telaNaSecao()
    outra.whatsappConversaAberta = kRafa.texto
    await WhatsAppTela.adotarPadrao(vm: outra, store: m.store)
    exigir(outra.whatsappConversaAberta == kMarina.texto,
           "aberta da 8292 com a 4143 selecionada: ficou \(String(describing: outra.whatsappConversaAberta)), esperado a Marina")

    // sem conta selecionada: vale a padrão (4143), e a Marina vira a aberta
    let semConta = telaNaSecao(conta: nil)
    await WhatsAppTela.adotarPadrao(vm: semConta, store: m.store)
    exigir(semConta.whatsappConversaAberta == kMarina.texto,
           "sem conta selecionada: ficou \(String(describing: semConta.whatsappConversaAberta)), esperado a Marina da padrão")
    await assentar()
    exigir(m.t.de("POST", "/v1/lida").isEmpty, "adotarPadrao marcou lida em algum caso")
}

/// A página que falhou não faz `adotarPadrao` pedir de novo a cada chamada: a
/// conversa já é a aberta da tela, e quem relê é o fluxo da conversa.
@MainActor
private func adotarPadraoNaoRepete() async {
    let m = await montarPronta()
    m.t.mensagensFalham = true
    let a = telaNaSecao()
    await WhatsAppTela.adotarPadrao(vm: a, store: m.store)
    await esperar("GET /v1/mensagens da Marina (que falha)") { !m.t.de("GET", "/v1/mensagens").isEmpty }
    await assentar()
    exigir(a.whatsappConversaAberta == kMarina.texto, "com a página falhando, a Marina não virou a aberta")
    await WhatsAppTela.adotarPadrao(vm: a, store: m.store)
    await WhatsAppTela.adotarPadrao(vm: a, store: m.store)
    await assentar()
    exigir(m.t.de("GET", "/v1/mensagens").count == 1,
           "adotarPadrao repetido com a mesma conversa pediu \(m.t.de("GET", "/v1/mensagens").count) páginas, esperado 1")
}

// MARK: - paginação da lista

@MainActor
private func carregarMaisConversas() async {
    let m = await montarPronta()

    // 8292: a primeira página já veio com `antes null` — nada a pedir
    await m.store.carregarMaisConversas(conta: C8292)
    await assentar()
    exigir(m.t.de("GET", "/v1/conversas").isEmpty,
           "8292 chegou ao fim na primeira página e mesmo assim pediu \(m.t.de("GET", "/v1/conversas").map(\.query))")

    // 4143: segunda página com o cursor da primeira
    await m.store.carregarMaisConversas(conta: C4143)
    await esperar("GET /v1/conversas da segunda página") { !m.t.de("GET", "/v1/conversas").isEmpty }
    await assentar()
    let ps = m.t.de("GET", "/v1/conversas")
    exigir(ps.count == 1, "segunda página: \(ps.count) pedidos, esperado 1")
    let q = ps.first?.query ?? [:]
    exigir(q["conta"] == C4143, "segunda página com conta \(String(describing: q["conta"])), esperado \(C4143)")
    exigir(q["limite"] == "50", "segunda página com limite \(String(describing: q["limite"])), esperado 50")
    exigir(q["antes"] == "c1", "segunda página com antes \(String(describing: q["antes"])), esperado c1")

    await esperar("Família entrar na lista da 4143") {
        m.store.estado.conversas(da: C4143).contains { $0.jid == FAMILIA }
    }
    let jids = m.store.estado.conversas(da: C4143).map(\.jid)
    exigir(jids == [MARINA, CARLOS, FAMILIA],
           "lista da 4143 depois da segunda página: \(jids), esperado Marina, Carlos, Família (sem repetir)")
    exigir(m.store.estado.conversas(da: C8292).map(\.jid) == [RAFA], "a página da 4143 mexeu na lista da 8292")

    // a segunda página respondeu `antes null`: fim da lista
    m.t.limpar()
    await m.store.carregarMaisConversas(conta: C4143)
    await assentar()
    exigir(m.t.de("GET", "/v1/conversas").isEmpty,
           "depois de `antes null` a terceira chamada pediu \(m.t.de("GET", "/v1/conversas").map(\.query))")
    exigir(m.store.estado.conversas(da: C4143).count == 3, "a terceira chamada mexeu na lista")
}

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

        colunaDireita()
        conversaEfetiva()
        colunaEsquerda()
        contaInicial()
        sinalDaFaixa()
        await adotarPadrao()
        await adotarPadraoNaoRepete()
        await carregarMaisConversas()
        print("whatsapptelacheck ok")
    }
}
