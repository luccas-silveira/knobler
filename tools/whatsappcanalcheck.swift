// Gate da etapa 5 do WhatsApp: canal ao vivo por WebSocket
// (Knobler/WhatsApp/WhatsAppCanal.swift). Contrato: docs/whatsapp-ponte.md
// (handshake em :730-743, fluxo e regra do `desde` em :746-779, sinal de vida
// em :781-788, fechamento 1013 em :790-795).
//
//   xcrun swiftc -parse-as-library -swift-version 5 \
//     Knobler/WhatsApp/WhatsAppModelos.swift Knobler/WhatsApp/WhatsAppChave.swift \
//     Knobler/WhatsApp/WhatsAppCanal.swift tools/whatsappcanalcheck.swift \
//     -o /tmp/whatsappcanalcheck && /tmp/whatsappcanalcheck
//
// Nada sai pela rede: a fábrica de socket é falsa (cada socket guarda o pedido
// e expõe abrir/entregar/fechar/pong), o relógio é falso (guarda cada bloco com
// o atraso pedido e só roda quando o teste manda, num tempo de mentira) e o
// `aleatorio` devolve o limite de cima do intervalo. O arquivo da chave é uma
// variável: a chave de verdade da ponte nunca é lida.

import Foundation

private func exigir(_ cond: Bool, _ msg: String, linha: UInt = #line) {
    if !cond {
        print("FALHOU: \(msg) (tools/whatsappcanalcheck.swift:\(linha))")
        exit(1)
    }
}

private struct ErroFalso: Error {}

// MARK: - socket falso

private final class SocketFalso: WASocket {
    let pedido: URLRequest
    private let aoAbrir: () -> Void
    private let aoFechar: (Int?, Int?) -> Void
    private(set) var iniciado = 0
    /// Código do primeiro `cancelar`, `nil` enquanto o canal não cancelou.
    private(set) var cancelado: Int?
    private(set) var pings = 0
    private var ouvintes: [(Result<String, Error>) -> Void] = []
    private var esperandoPong: [(Error?) -> Void] = []

    init(_ pedido: URLRequest, aoAbrir: @escaping () -> Void, aoFechar: @escaping (Int?, Int?) -> Void) {
        self.pedido = pedido
        self.aoAbrir = aoAbrir
        self.aoFechar = aoFechar
    }

    // WASocket
    func iniciar() { iniciado += 1 }
    func receber(_ h: @escaping (Result<String, Error>) -> Void) { ouvintes.append(h) }
    func ping(_ h: @escaping (Error?) -> Void) { pings += 1; esperandoPong.append(h) }
    func cancelar(codigo: Int) { if cancelado == nil { cancelado = codigo } }

    // lado da ponte
    var ouvindo: Bool { !ouvintes.isEmpty }
    func abrir() { aoAbrir() }
    func entregar(_ texto: String, linha: UInt = #line) {
        exigir(!ouvintes.isEmpty, "o canal não está ouvindo o socket quando a ponte manda \(texto)", linha: linha)
        let h = ouvintes.removeFirst()
        h(.success(texto))
    }
    func fechar(codigo: Int?, status: Int?) { aoFechar(codigo, status) }
    /// O `didCloseWith`/`didCompleteWithError` que o URLSession manda depois de um cancelamento.
    func fecharDepoisDeCancelar() { aoFechar(cancelado ?? 1001, nil) }
    func pong(ok: Bool, linha: UInt = #line) {
        exigir(!esperandoPong.isEmpty, "pong sem ping pendente", linha: linha)
        let h = esperandoPong.removeFirst()
        h(ok ? nil : ErroFalso())
    }
}

private final class FabricaFalsa: WAFabricaDeSocket {
    private(set) var sockets: [SocketFalso] = []
    func criar(_ pedido: URLRequest, aoAbrir: @escaping () -> Void,
               aoFechar: @escaping (_ codigo: Int?, _ statusHTTP: Int?) -> Void) -> WASocket {
        let s = SocketFalso(pedido, aoAbrir: aoAbrir, aoFechar: aoFechar)
        sockets.append(s)
        return s
    }
}

// MARK: - relógio falso

private final class Agendado: WACancelavel {
    let atraso: TimeInterval
    let prazo: TimeInterval
    let bloco: () -> Void
    var cancelado = false
    var rodado = false
    init(atraso: TimeInterval, prazo: TimeInterval, bloco: @escaping () -> Void) {
        self.atraso = atraso
        self.prazo = prazo
        self.bloco = bloco
    }
    func cancelar() { cancelado = true }
}

private final class RelogioFalso: WARelogio {
    private(set) var agora: TimeInterval = 1000
    private(set) var lista: [Agendado] = []

    func depois(_ segundos: TimeInterval, _ bloco: @escaping () -> Void) -> WACancelavel {
        let a = Agendado(atraso: segundos, prazo: agora + segundos, bloco: bloco)
        lista.append(a)
        return a
    }

    var pendentes: [Agendado] { lista.filter { !$0.cancelado && !$0.rodado } }

    /// Roda o bloco de prazo mais cedo (empate: o pedido primeiro) e avança o
    /// tempo até ele. `forcar` roda também o que foi cancelado: o bloco que
    /// "chega atrasado", já tirado da fila quando o `cancel` veio.
    @discardableResult
    func rodarProximo(forcar: Bool = false) -> Bool {
        let candidatos = lista.filter { !$0.rodado && (forcar || !$0.cancelado) }
        guard let p = candidatos.min(by: { $0.prazo < $1.prazo }) else { return false }
        agora = max(agora, p.prazo)
        p.rodado = true
        p.bloco()
        return true
    }
}

private final class AtividadeFalsa: WAAtividade {
    private(set) var comecos = 0
    private(set) var fins = 0
    func comecar() { comecos += 1 }
    func terminar() { fins += 1 }
}

/// Arquivo da chave com o cache do cliente: `relendo == false` devolve o que
/// já leu (lê o arquivo só na primeira vez); `relendo == true` lê de novo.
private final class ArquivoFalso {
    var arquivo: String?
    private var cache: String?
    private(set) var releituras = 0
    func ler(_ relendo: Bool) -> String? {
        if relendo { releituras += 1 }
        if relendo || cache == nil { cache = arquivo }
        return cache
    }
}

// MARK: - cena

private final class Cena {
    let fabrica = FabricaFalsa()
    let relogio = RelogioFalso()
    let atividade = AtividadeFalsa()
    let chave = ArquivoFalso()
    var eventos: [WAEvento] = []
    var estados: [WAEstadoDoCanal] = []
    var ressincs: [(String, Int)] = []
    var canal: WACanal!

    init(chave inicial: String?) {
        chave.arquivo = inicial
        canal = WACanal(porta: 8099,
                        chave: { [unowned self] relendo in self.chave.ler(relendo) },
                        fabrica: fabrica,
                        relogio: relogio,
                        aleatorio: { $0.upperBound },
                        atividade: atividade)
        canal.aoEvento = { [unowned self] in self.eventos.append($0) }
        canal.aoMudarEstado = { [unowned self] in self.estados.append($0) }
        canal.aoRessincronizar = { [unowned self] in self.ressincs.append(($0, $1)) }
    }

    var sockets: [SocketFalso] { fabrica.sockets }
    var ultimo: SocketFalso { fabrica.sockets.last! }

    var seqs: [Int] {
        eventos.compactMap { if case .numerado(let s, _, _, _) = $0 { return s } else { return nil } }
    }
    var contas: Int { eventos.filter { if case .conta = $0 { return true } else { return false } }.count }
    var pareamentos: Int { eventos.filter { if case .pareamento = $0 { return true } else { return false } }.count }

    func estado(_ e: WAEstadoDoCanal, _ msg: String, linha: UInt = #line) {
        exigir(canal.estado == e, "\(msg): estado \(canal.estado), esperado \(e)", linha: linha)
        exigir(estados.last == e, "\(msg): aoMudarEstado não avisou \(e) (último aviso: \(String(describing: estados.last)))",
               linha: linha)
    }

    func cursor(_ jornal: String?, _ seq: Int, _ msg: String, linha: UInt = #line) {
        exigir(canal.cursor == WACursor(jornal: jornal, ultimoSeq: seq),
               "\(msg): cursor \(canal.cursor), esperado (\(jornal ?? "nil"), \(seq))", linha: linha)
    }

    /// Roda o relógio até nascer um socket novo. Devolve o socket e quanto
    /// tempo de mentira passou (com `aleatorio` no teto, é o atraso pedido).
    func esperarSocket(_ msg: String, linha: UInt = #line) -> (SocketFalso, TimeInterval) {
        let t0 = relogio.agora
        let n0 = sockets.count
        var passos = 0
        while sockets.count == n0 {
            passos += 1
            exigir(passos < 200 && relogio.agora - t0 <= 120, "\(msg): nenhum socket novo em 120 s", linha: linha)
            exigir(relogio.rodarProximo(), "\(msg): nenhum socket novo e nada agendado no relógio", linha: linha)
        }
        exigir(sockets.count == n0 + 1, "\(msg): \(sockets.count - n0) sockets novos de uma vez", linha: linha)
        exigir(ultimo.iniciado == 1, "\(msg): socket novo criado mas não iniciado (iniciar() chamado \(ultimo.iniciado)x)",
               linha: linha)
        return (ultimo, relogio.agora - t0)
    }

    /// Roda tudo o que vence nos próximos `segundos` e exige que nenhum socket nasça.
    func semSocketNovo(por segundos: TimeInterval, forcar: Bool = false, _ msg: String, linha: UInt = #line) {
        let n0 = sockets.count
        let limite = relogio.agora + segundos
        var passos = 0
        while passos < 200 {
            let candidatos = relogio.lista.filter { !$0.rodado && (forcar || !$0.cancelado) }
            guard let p = candidatos.min(by: { $0.prazo < $1.prazo }), forcar || p.prazo <= limite else { break }
            relogio.rodarProximo(forcar: forcar)
            passos += 1
        }
        exigir(sockets.count == n0, "\(msg): nasceram \(sockets.count - n0) sockets", linha: linha)
    }
}

// MARK: - quadros da ponte

private func ola(_ jornal: String, _ seqAtual: Int, contrato: Int = 1) -> String {
    #"{"tipo": "ola", "contrato": \#(contrato), "jornal": "\#(jornal)", "seq_atual": \#(seqAtual), "seq_minimo": 1}"#
}

private func ressincronize(_ jornal: String, _ seqAtual: Int) -> String {
    #"{"tipo": "ressincronize", "jornal": "\#(jornal)", "seq_atual": \#(seqAtual)}"#
}

private func num(_ seq: Int) -> String {
    #"{"seq": \#(seq), "tipo": "sincronizacao", "conta": "554791744143", "ts": 1762270601, "dados": {"conversas": \#(seq)}}"#
}

private let quadroConta = #"""
{"tipo": "conta", "conta": "554791744143", "ts": 1762270700, "dados": {"conta": "554791744143",
 "jid": "554791744143:17@s.whatsapp.net", "nome": "Luccas", "padrao": true, "estado": "conectada",
 "motivo": null, "desde": 1762270000, "nao_lidas": 12, "conversas_nao_lidas": 3}}
"""#

private let quadroPareamento = #"""
{"tipo": "pareamento", "conta": "", "ts": 1762270700, "dados": {"id": "p-7f3a9c", "estado": "qr",
 "qr": "2@AbCd", "qr_expira_em": 1762270620, "fim": 1762270720, "conta": null, "motivo": null}}
"""#

/// Itens da query como dicionário; `nil` quando a URL não tem query.
private func consulta(_ p: URLRequest) -> [String: String]? {
    guard let url = p.url, let c = URLComponents(url: url, resolvingAgainstBaseURL: false),
          let itens = c.queryItems else { return nil }
    var d: [String: String] = [:]
    for i in itens { d[i.name] = i.value ?? "" }
    return d
}

private func confereDesde(_ p: URLRequest, desde: Int, jornal: String, chave: String, _ msg: String, linha: UInt = #line) {
    let url = p.url?.absoluteString ?? "nil"
    exigir(url.hasPrefix("ws://127.0.0.1:8099/v1/eventos?"), "\(msg): URL \(url)", linha: linha)
    exigir(consulta(p) == ["desde": String(desde), "jornal": jornal],
           "\(msg): query \(String(describing: consulta(p))), esperado desde=\(desde)&jornal=\(jornal)", linha: linha)
    exigir(p.value(forHTTPHeaderField: "Authorization") == "Bearer \(chave)",
           "\(msg): Authorization \(p.value(forHTTPHeaderField: "Authorization") ?? "nil")", linha: linha)
}

/// Cena com o canal já aberto: `ola(J1, 10)` no primeiro socket.
private func aberta() -> Cena {
    let c = Cena(chave: "K1")
    c.canal.iniciar()
    exigir(c.sockets.count == 1, "iniciar() com chave criou \(c.sockets.count) sockets")
    c.ultimo.abrir()
    c.ultimo.entregar(ola("J1", 10))
    c.estado(.aberto, "depois do ola")
    return c
}

// MARK: - casos

@main
enum WhatsAppCanalCheck {
    static func main() {
        estaticos()
        semChave()
        cursorEReentrega()
        olaDeOutroJornal()
        ressincronizeMudaJornal()
        contratoIncompativel()
        esperaCrescente()
        fechamento1013ERecusa()
        handshake401()
        sinalDeVida()
        acordou()
        parar()
        print("whatsappcanalcheck: ok")
    }

    static func estaticos() {
        let tetos = (0...7).map { WACanal.teto(tentativa: $0) }
        exigir(tetos == [1, 2, 4, 8, 16, 30, 30, 30], "teto(tentativa: 0...7) = \(tetos)")
        exigir(WACanal.teto(tentativa: 100) == 30, "teto(tentativa: 100) = \(WACanal.teto(tentativa: 100))")

        let p = WACanal.pedido(porta: 8099, chave: "K", cursor: WACursor(jornal: nil, ultimoSeq: 0))
        exigir(p.url?.absoluteString == "ws://127.0.0.1:8099/v1/eventos", "pedido sem jornal: \(p.url?.absoluteString ?? "nil")")
        exigir(p.value(forHTTPHeaderField: "Authorization") == "Bearer K", "pedido sem a chave no cabeçalho")

        // `desde` e `jornal` vêm juntos ou não vêm (docs/whatsapp-ponte.md:742-743)
        let semJornal = WACanal.pedido(porta: 8099, chave: "K", cursor: WACursor(jornal: nil, ultimoSeq: 7))
        exigir(semJornal.url?.query == nil, "cursor sem jornal pôs query: \(semJornal.url?.absoluteString ?? "nil")")

        let d = WACanal.pedido(porta: 9100, chave: "segredo", cursor: WACursor(jornal: "J1", ultimoSeq: 12))
        exigir(d.url?.host == "127.0.0.1" && d.url?.port == 9100 && d.url?.scheme == "ws" && d.url?.path == "/v1/eventos",
               "pedido na porta 9100: \(d.url?.absoluteString ?? "nil")")
        exigir(consulta(d) == ["desde": "12", "jornal": "J1"], "query do pedido com cursor: \(String(describing: consulta(d)))")
        exigir(!(d.url?.absoluteString ?? "").contains("segredo"), "a chave foi parar na URL")
        exigir(d.value(forHTTPHeaderField: "Authorization") == "Bearer segredo", "pedido com cursor sem a chave no cabeçalho")
    }

    static func semChave() {
        let c = Cena(chave: nil)
        c.canal.iniciar()
        c.estado(.semChave, "iniciar() sem chave")
        exigir(c.sockets.isEmpty, "sem chave criou \(c.sockets.count) sockets")
        exigir(c.relogio.pendentes.count == 1, "sem chave: \(c.relogio.pendentes.count) blocos agendados, esperado 1 (reler o arquivo)")
        exigir(c.atividade.comecos == 1, "atividade.comecar() chamado \(c.atividade.comecos)x")

        // ainda sem arquivo: relê, continua sem chave e reagenda
        c.relogio.rodarProximo()
        exigir(c.sockets.isEmpty, "sem chave na segunda leitura criou socket")
        exigir(c.relogio.pendentes.count == 1, "sem chave na segunda leitura: \(c.relogio.pendentes.count) blocos agendados")
        exigir(c.canal.estado == .semChave, "sem chave na segunda leitura: estado \(c.canal.estado)")

        // a ponte cria o arquivo: a próxima releitura conecta
        c.chave.arquivo = "K1"
        let (s, _) = c.esperarSocket("arquivo da chave apareceu")
        exigir(s.pedido.value(forHTTPHeaderField: "Authorization") == "Bearer K1", "socket depois da chave sem Bearer K1")
        exigir(c.atividade.comecos == 1, "atividade.comecar() chamado \(c.atividade.comecos)x depois de conectar")
    }

    static func cursorEReentrega() {
        let c = Cena(chave: "K1")
        c.canal.iniciar()
        exigir(c.sockets.count == 1, "iniciar() com chave criou \(c.sockets.count) sockets")
        exigir(c.atividade.comecos == 1, "atividade.comecar() chamado \(c.atividade.comecos)x")
        let s1 = c.sockets[0]
        exigir(s1.iniciado == 1, "primeiro socket não foi iniciado")
        exigir(s1.pedido.url?.absoluteString == "ws://127.0.0.1:8099/v1/eventos",
               "primeiro pedido: \(s1.pedido.url?.absoluteString ?? "nil")")
        exigir(s1.pedido.value(forHTTPHeaderField: "Authorization") == "Bearer K1", "primeiro pedido sem Bearer K1")

        s1.abrir()
        s1.entregar(ola("J1", 10))
        c.estado(.aberto, "ola do primeiro pedido")
        c.cursor("J1", 10, "ola do primeiro pedido (sem desde)")
        exigir(c.ressincs.isEmpty, "ola do primeiro pedido chamou aoRessincronizar \(c.ressincs)")

        s1.entregar(num(11))
        exigir(c.seqs == [11], "seq 11: entregues \(c.seqs)")
        c.cursor("J1", 11, "depois do seq 11")
        s1.entregar(num(11))
        s1.entregar(num(9))
        exigir(c.seqs == [11], "seq 11 repetido e seq 9 deviam ser ignorados: entregues \(c.seqs)")
        c.cursor("J1", 11, "depois do 11 repetido e do 9")
        s1.entregar(num(12))
        exigir(c.seqs == [11, 12], "seq 12: entregues \(c.seqs)")
        c.cursor("J1", 12, "depois do seq 12")

        s1.entregar(quadroConta)
        s1.entregar(quadroPareamento)
        exigir(c.contas == 1, "evento conta entregue \(c.contas)x")
        exigir(c.pareamentos == 1, "evento pareamento entregue \(c.pareamentos)x")
        c.cursor("J1", 12, "conta e pareamento mexeram no cursor")

        let total = c.eventos.count
        s1.entregar("isto não é JSON")
        s1.entregar("{}")
        s1.entregar(#"{"tipo": "mensagem", "seq": 13}"#)
        exigir(c.eventos.count == total, "texto inválido chegou a aoEvento")
        c.cursor("J1", 12, "texto inválido mexeu no cursor")
        exigir(s1.cancelado == nil, "texto inválido cancelou o socket")
        exigir(s1.ouvindo, "depois de texto inválido o canal parou de ouvir")
        c.estado(.aberto, "depois de texto inválido")
        exigir(c.sockets.count == 1, "texto inválido criou socket novo")

        // queda e reconexão com desde
        s1.fechar(codigo: 1006, status: nil)
        let (s2, _) = c.esperarSocket("reconexão depois da queda")
        confereDesde(s2.pedido, desde: 12, jornal: "J1", chave: "K1", "reconexão depois da queda")

        // reentrega: ola com desde e o mesmo jornal não mexe no cursor
        s2.abrir()
        s2.entregar(ola("J1", 20))
        c.estado(.aberto, "ola da reconexão")
        c.cursor("J1", 12, "ola com desde moveu o cursor (descartaria os eventos da queda)")
        exigir(c.ressincs.isEmpty, "ola com desde e mesmo jornal chamou aoRessincronizar \(c.ressincs)")
        for seq in 13...15 { s2.entregar(num(seq)) }
        s2.entregar(num(12))
        for seq in 16...20 { s2.entregar(num(seq)) }
        exigir(c.seqs == [11, 12] + Array(13...20), "reentrega 13…20 (com 12 repetido no meio): entregues \(c.seqs)")
        c.cursor("J1", 20, "depois da reentrega")
        exigir(c.ressincs.isEmpty, "reentrega chamou aoRessincronizar \(c.ressincs)")
    }

    static func olaDeOutroJornal() {
        let c = aberta()
        c.ultimo.entregar(num(11))
        c.ultimo.fechar(codigo: 1006, status: nil)
        let (s2, _) = c.esperarSocket("reconexão antes do jornal novo")
        confereDesde(s2.pedido, desde: 11, jornal: "J1", chave: "K1", "reconexão antes do jornal novo")
        s2.abrir()
        s2.entregar(ola("J9", 3))
        exigir(c.ressincs.count == 1 && c.ressincs[0] == ("J9", 3),
               "ola com desde e outro jornal: aoRessincronizar \(c.ressincs), esperado [(J9, 3)]")
        c.cursor("J9", 3, "ola com desde e outro jornal")
        c.estado(.aberto, "ola de outro jornal")
        s2.entregar(num(2))
        exigir(c.seqs == [11], "seq 2 do jornal J9 (<= 3) devia ser ignorado: entregues \(c.seqs)")
        s2.entregar(num(4))
        exigir(c.seqs == [11, 4], "seq 4 do jornal J9: entregues \(c.seqs)")
        c.cursor("J9", 4, "depois do seq 4 do J9")
    }

    static func ressincronizeMudaJornal() {
        let c = aberta()
        c.ultimo.entregar(num(11))
        c.ultimo.entregar(ressincronize("J2", 50))
        exigir(c.ressincs.count == 1 && c.ressincs[0] == ("J2", 50),
               "ressincronize: aoRessincronizar \(c.ressincs), esperado [(J2, 50)]")
        c.cursor("J2", 50, "depois do ressincronize")
        c.ultimo.entregar(num(50))
        c.ultimo.entregar(num(49))
        exigir(c.seqs == [11], "seq 50 e 49 depois do ressincronize(J2, 50) deviam ser ignorados: \(c.seqs)")
        c.ultimo.entregar(num(51))
        exigir(c.seqs == [11, 51], "seq 51 depois do ressincronize: entregues \(c.seqs)")
        c.cursor("J2", 51, "depois do seq 51")

        c.ultimo.fechar(codigo: 1006, status: nil)
        let (s2, _) = c.esperarSocket("reconexão depois do ressincronize")
        confereDesde(s2.pedido, desde: 51, jornal: "J2", chave: "K1", "reconexão depois do ressincronize")
    }

    static func contratoIncompativel() {
        let c = Cena(chave: "K1")
        c.canal.iniciar()
        let s1 = c.ultimo
        s1.abrir()
        s1.entregar(ola("J1", 10, contrato: 2))
        c.estado(.incompativel(2), "ola com contrato 2")
        exigir(s1.cancelado != nil, "ola com contrato 2 não cancelou o socket")
        exigir(c.seqs.isEmpty && c.ressincs.isEmpty, "ola com contrato 2 entregou eventos")
        // o URLSession avisa o fechamento depois do cancelamento
        s1.fecharDepoisDeCancelar()
        c.estado(.incompativel(2), "fechamento depois do cancelamento por contrato")
        let (_, atraso) = c.esperarSocket("reconexão depois do contrato incompatível")
        exigir(atraso == 30, "contrato incompatível reagendou com \(atraso) s, esperado o teto de 30 s")
        c.semSocketNovo(por: 60, "depois da reconexão por contrato incompatível")
    }

    static func esperaCrescente() {
        let c = Cena(chave: "K1")
        c.canal.iniciar()
        var atrasos: [TimeInterval] = []
        // quedas seguidas sem ola: recusa (sem abrir) e queda depois de abrir
        for i in 0..<7 {
            let s = c.ultimo
            if i % 2 == 0 {
                s.fechar(codigo: nil, status: nil)
                c.estado(.foraDoAr, "conexão recusada \(i + 1)")
            } else {
                s.abrir()
                s.fechar(codigo: 1006, status: nil)
            }
            let (_, atraso) = c.esperarSocket("queda \(i + 1) sem ola")
            atrasos.append(atraso)
        }
        exigir(atrasos == [1, 2, 4, 8, 16, 30, 30], "quedas seguidas sem ola pediram \(atrasos), esperado [1, 2, 4, 8, 16, 30, 30]")

        let s = c.ultimo
        s.abrir()
        s.entregar(ola("J1", 10))
        c.estado(.aberto, "ola depois das quedas")
        exigir(c.canal.tentativa == 0, "ola não zerou a tentativa (\(c.canal.tentativa))")
        s.fechar(codigo: 1006, status: nil)
        let (_, atraso) = c.esperarSocket("queda depois do ola")
        exigir(atraso == 1, "queda depois do ola pediu \(atraso) s, esperado 1")
    }

    static func fechamento1013ERecusa() {
        let c = aberta()
        c.ultimo.entregar(num(11))
        c.ultimo.fechar(codigo: 1013, status: nil)
        let (s2, atraso) = c.esperarSocket("fechamento 1013")
        exigir(atraso <= 1.5, "fechamento 1013 reconectou em \(atraso) s, esperado <= 1,5")
        confereDesde(s2.pedido, desde: 11, jornal: "J1", chave: "K1", "reconexão depois do 1013")

        // a ponte saiu do ar: conexão recusada, espera crescente
        s2.fechar(codigo: nil, status: nil)
        c.estado(.foraDoAr, "conexão recusada")
        let (s3, a1) = c.esperarSocket("primeira recusa")
        s3.fechar(codigo: nil, status: nil)
        c.estado(.foraDoAr, "segunda recusa")
        let (s4, a2) = c.esperarSocket("segunda recusa")
        s4.fechar(codigo: nil, status: nil)
        let (_, a3) = c.esperarSocket("terceira recusa")
        exigir(a1 < a2 && a2 < a3, "recusas seguidas pediram \(a1), \(a2), \(a3) s: a espera devia crescer")
    }

    static func handshake401() {
        let c = Cena(chave: "K1")
        c.canal.iniciar()
        let s1 = c.ultimo
        exigir(s1.pedido.value(forHTTPHeaderField: "Authorization") == "Bearer K1", "primeiro pedido sem Bearer K1")

        // a ponte trocou a chave: o primeiro 401 relê o arquivo e tenta na hora
        c.chave.arquivo = "K2"
        s1.fechar(codigo: nil, status: 401)
        exigir(c.canal.estado != .chaveNaoConfere, "primeiro 401 já virou chaveNaoConfere")
        let (s2, a0) = c.esperarSocket("primeiro 401")
        exigir(a0 == 0, "primeiro 401 tentou de novo em \(a0) s, esperado na hora")
        exigir(c.chave.releituras >= 1, "primeiro 401 não releu o arquivo da chave")
        exigir(s2.pedido.value(forHTTPHeaderField: "Authorization") == "Bearer K2",
               "tentativa depois do 401 não usou a chave relida: \(s2.pedido.value(forHTTPHeaderField: "Authorization") ?? "nil")")

        // segundo 401 seguido: chave não confere e espera crescente
        s2.fechar(codigo: nil, status: 401)
        c.estado(.chaveNaoConfere, "segundo 401 seguido")
        let (s3, a1) = c.esperarSocket("segundo 401")
        exigir(a1 > 0, "segundo 401 tentou de novo na hora")
        s3.fechar(codigo: nil, status: 401)
        c.estado(.chaveNaoConfere, "terceiro 401 seguido")
        let (s4, a2) = c.esperarSocket("terceiro 401")
        exigir(a2 > a1, "401 seguidos pediram \(a1) e \(a2) s: a espera devia crescer")

        // um ola zera a contagem: o próximo 401 volta a reler e tentar na hora
        s4.abrir()
        s4.entregar(ola("J1", 10))
        c.estado(.aberto, "ola depois dos 401")
        s4.fechar(codigo: 1006, status: nil)
        let (s5, _) = c.esperarSocket("queda depois do ola")
        s5.fechar(codigo: nil, status: 401)
        exigir(c.canal.estado != .chaveNaoConfere, "401 depois de um ola virou chaveNaoConfere direto")
        let (_, a3) = c.esperarSocket("401 depois do ola")
        exigir(a3 == 0, "401 depois de um ola tentou de novo em \(a3) s, esperado na hora")
    }

    static func sinalDeVida() {
        // sem pong
        do {
            let c = aberta()
            let s1 = c.ultimo
            let t0 = c.relogio.agora
            var passos = 0
            while s1.pings == 0 {
                passos += 1
                exigir(passos < 50 && c.relogio.rodarProximo(), "nenhum ping depois do ola")
            }
            exigir(c.relogio.agora - t0 == 25, "primeiro ping \(c.relogio.agora - t0) s depois do ola, esperado 25")
            exigir(s1.cancelado == nil && c.sockets.count == 1, "o ping derrubou o socket antes do prazo do pong")
            let tPing = c.relogio.agora
            passos = 0
            while s1.cancelado == nil {
                passos += 1
                exigir(passos < 50 && c.relogio.agora - tPing <= 10 && c.relogio.rodarProximo(),
                       "sem pong em 10 s o canal não cancelou o socket")
            }
            exigir(c.relogio.agora - tPing == 10, "sem pong: cancelou \(c.relogio.agora - tPing) s depois do ping, esperado 10")
            s1.fecharDepoisDeCancelar()
            let (s2, _) = c.esperarSocket("reconexão sem pong")
            confereDesde(s2.pedido, desde: 10, jornal: "J1", chave: "K1", "reconexão sem pong")
            c.semSocketNovo(por: 60, "depois da reconexão sem pong")
            exigir(s2.cancelado == nil, "bloco velho do sinal de vida cancelou o socket novo")
        }
        // com pong
        do {
            let c = aberta()
            let s1 = c.ultimo
            var passos = 0
            while s1.pings == 0 {
                passos += 1
                exigir(passos < 50 && c.relogio.rodarProximo(), "nenhum ping depois do ola")
            }
            let tPing = c.relogio.agora
            s1.pong(ok: true)
            passos = 0
            while s1.pings == 1 {
                passos += 1
                exigir(s1.cancelado == nil, "com pong o canal cancelou o socket")
                exigir(passos < 50 && c.relogio.rodarProximo(), "com pong o canal não agendou o próximo ping")
            }
            exigir(c.relogio.agora - tPing == 25, "segundo ping \(c.relogio.agora - tPing) s depois do primeiro, esperado 25")
            exigir(s1.cancelado == nil && c.sockets.count == 1, "com pong o canal derrubou o socket")
            c.estado(.aberto, "depois do pong")
        }
    }

    static func acordou() {
        // dormindo com a ponte fora: tentativa alta e reconexão de 16 s pendente
        do {
            let c = Cena(chave: "K1")
            c.canal.iniciar()
            for _ in 0..<4 {
                c.ultimo.fechar(codigo: nil, status: nil)
                _ = c.esperarSocket("recusa antes do sleep")
            }
            c.ultimo.fechar(codigo: nil, status: nil)
            exigir(c.canal.tentativa > 0, "depois de 5 recusas a tentativa é \(c.canal.tentativa)")
            c.canal.acordou()
            exigir(c.canal.tentativa == 0, "acordou() não zerou a tentativa (\(c.canal.tentativa))")
            let (s, atraso) = c.esperarSocket("acordou com reconexão pendente")
            exigir(atraso <= 1.5, "acordou() reconectou em \(atraso) s, esperado <= 1,5")
            c.semSocketNovo(por: 60, "reconexão velha depois do acordou")
            s.fechar(codigo: nil, status: nil)
            let (_, a1) = c.esperarSocket("recusa depois do acordou")
            exigir(a1 == 1, "recusa depois do acordou pediu \(a1) s, esperado 1 (tentativa zerada)")
        }
        // dormindo com o canal aberto
        do {
            let c = aberta()
            let s1 = c.ultimo
            s1.entregar(num(11))
            c.canal.acordou()
            exigir(s1.cancelado != nil, "acordou() não cancelou o socket atual")
            s1.fecharDepoisDeCancelar()
            let (s2, atraso) = c.esperarSocket("acordou com o canal aberto")
            exigir(atraso <= 1.5, "acordou() reconectou em \(atraso) s, esperado <= 1,5")
            confereDesde(s2.pedido, desde: 11, jornal: "J1", chave: "K1", "reconexão do acordou")
            c.semSocketNovo(por: 60, "blocos velhos depois do acordou")
            exigir(s2.cancelado == nil, "bloco velho do socket anterior cancelou o socket do acordou")
        }
    }

    static func parar() {
        // aberto
        do {
            let c = aberta()
            let s1 = c.ultimo
            c.canal.parar()
            c.estado(.parado, "parar()")
            exigir(s1.cancelado != nil, "parar() não cancelou o socket")
            exigir(c.atividade.comecos == 1 && c.atividade.fins == 1,
                   "atividade: comecar \(c.atividade.comecos)x, terminar \(c.atividade.fins)x, esperado 1 e 1")
            s1.fecharDepoisDeCancelar()
            s1.fechar(codigo: 1006, status: nil)
            c.semSocketNovo(por: 0, forcar: true, "aoFechar e blocos atrasados depois do parar()")
            c.canal.acordou()
            c.semSocketNovo(por: 0, forcar: true, "wake depois do parar()")
            exigir(c.canal.estado == .parado, "depois do parar() o estado virou \(c.canal.estado)")
            exigir(c.atividade.fins == 1, "atividade.terminar() chamado \(c.atividade.fins)x")
        }
        // com reconexão pendente
        do {
            let c = Cena(chave: "K1")
            c.canal.iniciar()
            c.ultimo.fechar(codigo: nil, status: nil)
            exigir(!c.relogio.pendentes.isEmpty, "recusa não agendou reconexão")
            c.canal.parar()
            c.estado(.parado, "parar() com reconexão pendente")
            exigir(c.relogio.pendentes.isEmpty, "parar() deixou \(c.relogio.pendentes.count) blocos agendados")
            c.semSocketNovo(por: 0, forcar: true, "reconexão atrasada depois do parar()")
            exigir(c.canal.estado == .parado, "reconexão atrasada mudou o estado para \(c.canal.estado)")
            exigir(c.atividade.fins == 1, "atividade.terminar() chamado \(c.atividade.fins)x")
        }
        // sem chave, com releitura pendente
        do {
            let c = Cena(chave: nil)
            c.canal.iniciar()
            c.canal.parar()
            c.estado(.parado, "parar() sem chave")
            c.chave.arquivo = "K1"
            c.semSocketNovo(por: 0, forcar: true, "releitura atrasada depois do parar()")
            exigir(c.canal.estado == .parado, "releitura atrasada mudou o estado para \(c.canal.estado)")
        }
    }
}
