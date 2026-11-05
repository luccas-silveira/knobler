import AppKit
import Foundation
import os

// Canal ao vivo da ponte do WhatsApp: `GET /v1/eventos` em WebSocket
// (docs/whatsapp-ponte.md: handshake em :730-743, fluxo e `desde` em :746-779,
// sinal de vida em :781-788, fechamento em :790-795). Segue o PADRÃO do
// `WebhookClient` (espera crescente com jitter e teto de 30 s, reconexão no
// wake, ping 25 s/pong 10 s com guarda de época, App Nap), não a classe. Sem
// `NWPathMonitor`: a ponte é loopback e o canal não desiste quando o Mac fica
// sem internet. Roda inteiro na main (tráfego baixo), sem fila própria.

private let log = Logger(subsystem: "com.zoi.knobler", category: "whatsapp")

enum WAEstadoDoCanal: Equatable {
    case parado, semChave, conectando, aberto, foraDoAr, chaveNaoConfere, incompativel(Int)
}

/// Último ponto aplicado do diário da ponte. `jornal == nil` = nunca recebeu `ola`.
struct WACursor: Equatable {
    var jornal: String?
    var ultimoSeq: Int
}

// MARK: - costuras (socket, relógio, App Nap)

protocol WASocket: AnyObject {
    func iniciar()
    func receber(_ h: @escaping (Result<String, Error>) -> Void)
    func ping(_ h: @escaping (Error?) -> Void)
    func cancelar(codigo: Int)
}

protocol WAFabricaDeSocket {
    /// `aoFechar(código, statusHTTP)`: `código` é o do fechamento do WebSocket
    /// (nil quando não houve), `statusHTTP` é o da resposta quando o handshake
    /// não virou WebSocket (nil quando nem houve resposta).
    func criar(_ pedido: URLRequest, aoAbrir: @escaping () -> Void,
               aoFechar: @escaping (_ codigo: Int?, _ statusHTTP: Int?) -> Void) -> WASocket
}

protocol WACancelavel {
    func cancelar()
}

protocol WARelogio {
    func depois(_ segundos: TimeInterval, _ bloco: @escaping () -> Void) -> WACancelavel
}

protocol WAAtividade {
    func comecar()
    func terminar()
}

/// É por aqui que o estado do WhatsApp fala com o canal (e com um canal falso nos testes).
protocol WACanalProtocolo: AnyObject {
    var aoEvento: ((WAEvento) -> Void)? { get set }
    var aoRessincronizar: ((String, Int) -> Void)? { get set }
    var aoMudarEstado: ((WAEstadoDoCanal) -> Void)? { get set }
    func iniciar()
    func parar()
    func acordou()
}

// MARK: - canal

final class WACanal: WACanalProtocolo {
    var aoEvento: ((WAEvento) -> Void)?
    var aoRessincronizar: ((String, Int) -> Void)?
    var aoMudarEstado: ((WAEstadoDoCanal) -> Void)?

    private(set) var estado: WAEstadoDoCanal = .parado
    private(set) var cursor = WACursor(jornal: nil, ultimoSeq: 0)
    /// Quedas seguidas sem `ola`; escolhe o teto da próxima espera.
    private(set) var tentativa = 0

    private static let contrato = 1
    private static let tetoDeEspera: Double = 30
    private static let intervaloDePing: TimeInterval = 25
    private static let prazoDoPong: TimeInterval = 10
    private static let releituraSemChave: TimeInterval = 5
    private static let jitterRapido: ClosedRange<Double> = 0...1.5

    private let porta: Int
    private let chave: (_ relendo: Bool) -> String?
    private let fabrica: WAFabricaDeSocket
    private let relogio: WARelogio
    private let aleatorio: (ClosedRange<Double>) -> Double
    private let atividade: WAAtividade

    private var rodando = false
    /// Sobe a cada conexão e a cada derrubada: callback de socket velho não passa.
    private var epoca: UInt64 = 0
    private var socket: WASocket?
    /// O pedido da conexão atual saiu com `desde`/`jornal`.
    private var pedidoComDesde = false
    /// A conexão atual já recebeu um `ola` compatível.
    private var recebeuOla = false
    /// 401 seguidos sem `ola` no meio.
    private var falhas401 = 0
    private var reconexao, ping, pong: WACancelavel?
    /// Sobe a cada reconexão agendada: bloco que chegue atrasado não conecta.
    private var geracaoDaReconexao: UInt64 = 0
    private var observadorDeWake: NSObjectProtocol?

    init(porta: Int,
         chave: @escaping (_ relendo: Bool) -> String?,
         fabrica: WAFabricaDeSocket = WAFabricaURLSession(),
         relogio: WARelogio = WARelogioMain(),
         aleatorio: @escaping (ClosedRange<Double>) -> Double = { Double.random(in: $0) },
         atividade: WAAtividade = WAAtividadeDoSistema()) {
        self.porta = porta
        self.chave = chave
        self.fabrica = fabrica
        self.relogio = relogio
        self.aleatorio = aleatorio
        self.atividade = atividade
        observadorDeWake = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.acordou() }
    }

    deinit {
        if let observadorDeWake { NSWorkspace.shared.notificationCenter.removeObserver(observadorDeWake) }
    }

    /// Teto da espera da tentativa `n`: `min(30, 2^n)` segundos.
    static func teto(tentativa: Int) -> Double {
        guard tentativa < 5 else { return tetoDeEspera }
        return min(tetoDeEspera, pow(2, Double(max(0, tentativa))))
    }

    /// `ws://127.0.0.1:<porta>/v1/eventos`, com `desde` e `jornal` juntos só
    /// quando o cursor tem jornal. A chave vai no cabeçalho, nunca na URL.
    static func pedido(porta: Int, chave: String, cursor: WACursor) -> URLRequest {
        var c = URLComponents()
        c.scheme = "ws"
        c.host = "127.0.0.1"
        c.port = porta
        c.path = "/v1/eventos"
        if let jornal = cursor.jornal {
            c.queryItems = [URLQueryItem(name: "desde", value: String(cursor.ultimoSeq)),
                            URLQueryItem(name: "jornal", value: jornal)]
        }
        // ponytail: os componentes acima sempre formam URL válida
        var p = URLRequest(url: c.url!)
        p.setValue("Bearer \(chave)", forHTTPHeaderField: "Authorization")
        return p
    }

    // MARK: API

    func iniciar() {
        guard !rodando else { return }
        rodando = true
        atividade.comecar()
        conectar(relendo: false)
    }

    func parar() {
        guard rodando else { return }
        rodando = false
        derrubar(cancelando: true)
        cancelarReconexao()
        atividade.terminar()
        mudar(.parado)
    }

    /// Volta do sleep: a conexão pode ter morrido sem aviso. Zera a espera e
    /// reconecta logo, com jitter curto.
    func acordou() {
        guard rodando else { return }
        log.notice("canal do WhatsApp: acordou, reconectando")
        tentativa = 0
        let estavaAberto = recebeuOla
        derrubar(cancelando: true)
        if estavaAberto { mudar(.conectando) }
        agendarReconexao(em: aleatorio(Self.jitterRapido), relendo: false)
    }

    // MARK: conexão

    private func conectar(relendo: Bool) {
        guard rodando else { return }
        guard let k = chave(relendo) else {
            mudar(.semChave)
            agendarReconexao(em: Self.releituraSemChave, relendo: true)
            return
        }
        if estado == .parado || estado == .semChave { mudar(.conectando) }

        epoca &+= 1
        let e = epoca
        pedidoComDesde = cursor.jornal != nil
        recebeuOla = false
        let s = fabrica.criar(Self.pedido(porta: porta, chave: k, cursor: cursor),
                              aoAbrir: { [weak self] in self?.abriu(e) },
                              aoFechar: { [weak self] codigo, status in self?.fechou(e, codigo: codigo, status: status) })
        socket = s
        s.iniciar()
        escutar(e)
    }

    private func abriu(_ e: UInt64) {
        guard rodando, e == epoca else { return }
        log.debug("canal do WhatsApp: socket aberto, esperando ola")
    }

    private func escutar(_ e: UInt64) {
        guard rodando, e == epoca, let socket else { return }
        socket.receber { [weak self] r in
            guard let self, self.rodando, e == self.epoca else { return }
            switch r {
            case .success(let texto):
                self.processar(texto, e)
                self.escutar(e)
            case .failure(let erro):
                // quem decide a reconexão é o `aoFechar`, que sempre vem depois
                log.notice("canal do WhatsApp: leitura falhou: \(erro.localizedDescription, privacy: .public)")
            }
        }
    }

    private func fechou(_ e: UInt64, codigo: Int?, status: Int?) {
        guard rodando, e == epoca else { return }
        let estavaAberto = recebeuOla
        derrubar(cancelando: false)
        log.notice("canal do WhatsApp: fechou (código \(codigo ?? -1), HTTP \(status ?? -1))")

        if status == 401 {
            falhas401 += 1
            if falhas401 == 1 {
                // a ponte pode ter trocado a chave: relê o arquivo e tenta na hora
                agendarReconexao(em: 0, relendo: true)
            } else {
                mudar(.chaveNaoConfere)
                agendarComEspera(relendo: true)
            }
            return
        }
        if codigo == 1013 {
            // ficou para trás: reconecta logo, com `desde`
            mudar(.conectando)
            agendarReconexao(em: aleatorio(Self.jitterRapido), relendo: false)
            return
        }
        if codigo == nil && !estavaAberto {
            // conexão recusada ou handshake sem WebSocket: a ponte não está lá
            mudar(.foraDoAr)
        } else if estavaAberto {
            mudar(.conectando)
        }
        agendarComEspera(relendo: false)
    }

    /// Para o socket atual e os timers dele. Não mexe na reconexão agendada.
    private func derrubar(cancelando: Bool) {
        epoca &+= 1
        ping?.cancelar(); ping = nil
        pong?.cancelar(); pong = nil
        if cancelando { socket?.cancelar(codigo: 1001) }
        socket = nil
        recebeuOla = false
    }

    private func agendarComEspera(relendo: Bool) {
        let atraso = aleatorio(0...Self.teto(tentativa: tentativa))
        tentativa += 1
        agendarReconexao(em: atraso, relendo: relendo)
    }

    private func agendarReconexao(em atraso: TimeInterval, relendo: Bool) {
        cancelarReconexao()
        let g = geracaoDaReconexao
        reconexao = relogio.depois(atraso) { [weak self] in
            guard let self, self.rodando, g == self.geracaoDaReconexao else { return }
            self.reconexao = nil
            self.conectar(relendo: relendo)
        }
    }

    private func cancelarReconexao() {
        geracaoDaReconexao &+= 1
        reconexao?.cancelar()
        reconexao = nil
    }

    // MARK: quadros

    private func processar(_ texto: String, _ e: UInt64) {
        guard let evento = WAEvento.decodificar(texto) else {
            log.notice("canal do WhatsApp: quadro ignorado (não decodificou)")
            return
        }
        switch evento {
        case let .ola(contrato, jornal, seqAtual, _):
            ola(contrato: contrato, jornal: jornal, seqAtual: seqAtual, e)
        case let .ressincronize(jornal, seqAtual):
            cursor = WACursor(jornal: jornal, ultimoSeq: seqAtual)
            aoRessincronizar?(jornal, seqAtual)
        case let .numerado(seq, _, _, _):
            // evento com `seq` <= último aplicado é ignorado (docs/whatsapp-ponte.md:777-778)
            guard recebeuOla, seq > cursor.ultimoSeq else { return }
            cursor.ultimoSeq = seq
            aoEvento?(evento)
        case .conta, .pareamento:
            aoEvento?(evento)
        case .desconhecido(let tipo):
            log.debug("canal do WhatsApp: evento de tipo desconhecido \(tipo, privacy: .public)")
        }
    }

    private func ola(contrato: Int, jornal: String, seqAtual: Int, _ e: UInt64) {
        guard contrato == Self.contrato else {
            log.error("canal do WhatsApp: contrato \(contrato) incompatível")
            derrubar(cancelando: true)
            mudar(.incompativel(contrato))
            agendarReconexao(em: Self.tetoDeEspera, relendo: false)
            return
        }
        recebeuOla = true
        tentativa = 0
        falhas401 = 0
        if !pedidoComDesde {
            cursor = WACursor(jornal: jornal, ultimoSeq: seqAtual)
        } else if jornal != cursor.jornal {
            // outra contagem sem `ressincronize` antes: não confia nos eventos dela
            cursor = WACursor(jornal: jornal, ultimoSeq: seqAtual)
            aoRessincronizar?(jornal, seqAtual)
        }
        // com `desde` e o mesmo jornal o cursor fica: os eventos de desde+1 até
        // seqAtual vêm a seguir e é o `seq` de cada um que avança o cursor
        mudar(.aberto)
        agendarPing(e)
    }

    // MARK: sinal de vida

    private func agendarPing(_ e: UInt64) {
        ping?.cancelar()
        ping = relogio.depois(Self.intervaloDePing) { [weak self] in
            guard let self, self.rodando, e == self.epoca, let socket = self.socket else { return }
            self.pong?.cancelar()
            self.pong = self.relogio.depois(Self.prazoDoPong) { [weak self] in
                guard let self, self.rodando, e == self.epoca else { return }
                log.notice("canal do WhatsApp: sem pong em 10 s, reconectando")
                self.derrubar(cancelando: true)
                self.mudar(.conectando)
                self.agendarComEspera(relendo: false)
            }
            socket.ping { [weak self] erro in
                guard let self, self.rodando, e == self.epoca else { return }
                self.pong?.cancelar(); self.pong = nil
                if erro == nil { self.agendarPing(e) }
                // com erro, o `aoFechar` do socket cuida da reconexão
            }
        }
    }

    private func mudar(_ novo: WAEstadoDoCanal) {
        guard novo != estado else { return }
        estado = novo
        aoMudarEstado?(novo)
    }
}

// MARK: - implementações do sistema

/// `URLSessionWebSocketTask` com o `URLRequest` (a chave vai no cabeçalho).
/// Delegate na fila main: abertura e fechamento chegam já na main.
final class WAFabricaURLSession: WAFabricaDeSocket {
    private let delegado = Delegado()
    private let session: URLSession

    init() {
        let c = URLSessionConfiguration.default
        c.timeoutIntervalForRequest = 30
        session = URLSession(configuration: c, delegate: delegado, delegateQueue: .main)
    }

    deinit { session.invalidateAndCancel() }

    func criar(_ pedido: URLRequest, aoAbrir: @escaping () -> Void,
               aoFechar: @escaping (_ codigo: Int?, _ statusHTTP: Int?) -> Void) -> WASocket {
        let task = session.webSocketTask(with: pedido)
        delegado.ouvintes[task.taskIdentifier] = (aoAbrir, aoFechar)
        return Socket(task)
    }

    private final class Socket: WASocket {
        private let task: URLSessionWebSocketTask
        init(_ task: URLSessionWebSocketTask) { self.task = task }

        func iniciar() { task.resume() }

        func receber(_ h: @escaping (Result<String, Error>) -> Void) {
            task.receive { r in
                let texto: Result<String, Error>
                switch r {
                case .success(.string(let s)): texto = .success(s)
                case .success(.data(let d)): texto = .success(String(decoding: d, as: UTF8.self))
                case .success: texto = .success("")
                case .failure(let erro): texto = .failure(erro)
                }
                DispatchQueue.main.async { h(texto) }
            }
        }

        func ping(_ h: @escaping (Error?) -> Void) {
            task.sendPing { erro in DispatchQueue.main.async { h(erro) } }
        }

        func cancelar(codigo: Int) {
            task.cancel(with: URLSessionWebSocketTask.CloseCode(rawValue: codigo) ?? .goingAway, reason: nil)
        }
    }

    private final class Delegado: NSObject, URLSessionWebSocketDelegate {
        /// Só mexido na main (criar e callbacks do delegate).
        var ouvintes: [Int: (abrir: () -> Void, fechar: (Int?, Int?) -> Void)] = [:]

        func urlSession(_ s: URLSession, webSocketTask t: URLSessionWebSocketTask, didOpenWithProtocol p: String?) {
            DispatchQueue.main.async { self.ouvintes[t.taskIdentifier]?.abrir() }
        }

        func urlSession(_ s: URLSession, webSocketTask t: URLSessionWebSocketTask,
                        didCloseWith codigo: URLSessionWebSocketTask.CloseCode, reason: Data?) {
            DispatchQueue.main.async { self.fechar(t, codigo: codigo.rawValue) }
        }

        func urlSession(_ s: URLSession, task t: URLSessionTask, didCompleteWithError erro: Error?) {
            DispatchQueue.main.async {
                let ws = t as? URLSessionWebSocketTask
                let codigo = ws.flatMap { $0.closeCode == .invalid ? nil : $0.closeCode.rawValue }
                self.fechar(t, codigo: codigo)
            }
        }

        /// O primeiro aviso de fechamento vale; o segundo da mesma task não acha ouvinte.
        private func fechar(_ t: URLSessionTask, codigo: Int?) {
            guard let o = ouvintes.removeValue(forKey: t.taskIdentifier) else { return }
            // 101 = o handshake virou WebSocket; só o status de handshake recusado interessa
            let status = (t.response as? HTTPURLResponse)?.statusCode
            o.fechar(codigo, status == 101 ? nil : status)
        }
    }
}

struct WARelogioMain: WARelogio {
    func depois(_ segundos: TimeInterval, _ bloco: @escaping () -> Void) -> WACancelavel {
        let item = DispatchWorkItem(block: bloco)
        DispatchQueue.main.asyncAfter(deadline: .now() + segundos, execute: item)
        return item
    }
}

extension DispatchWorkItem: WACancelavel {
    func cancelar() { cancel() }
}

/// Segura o App Nap enquanto o canal roda, sem impedir o sleep ocioso.
final class WAAtividadeDoSistema: WAAtividade {
    private var token: NSObjectProtocol?

    func comecar() {
        guard token == nil else { return }
        token = ProcessInfo.processInfo.beginActivity(
            options: .userInitiatedAllowingIdleSystemSleep, reason: "canal ao vivo do WhatsApp do Knobler")
    }

    func terminar() {
        if let token { ProcessInfo.processInfo.endActivity(token) }
        token = nil
    }
}
