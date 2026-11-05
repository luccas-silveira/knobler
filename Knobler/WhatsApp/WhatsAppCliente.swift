import Foundation
import os

// Cliente HTTP da ponte do WhatsApp (docs/whatsapp-ponte.md: chave em :28-66,
// rotas em :424-722, erros em :982-1020). Fala só com http://127.0.0.1:<porta>;
// a exceção de ATS para esse IP está no project.yml (tools/whatsappatscheck.sh).

private let log = Logger(subsystem: "com.zoi.knobler", category: "whatsapp")

/// Quem leva o pedido até a ponte. O gate troca por um transporte falso.
protocol WATransporte {
    func enviar(_ pedido: URLRequest) async throws -> (Data, HTTPURLResponse)
}

/// Transporte real: sessão efêmera, sem cache e sem cookies.
struct WATransporteURLSession: WATransporte {
    private let sessao: URLSession

    init() {
        let config = URLSessionConfiguration.ephemeral
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.urlCache = nil
        config.httpCookieStorage = nil
        config.httpShouldSetCookies = false
        sessao = URLSession(configuration: config)
    }

    func enviar(_ pedido: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (dados, resposta) = try await sessao.data(for: pedido)
        guard let http = resposta as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        return (dados, http)
    }
}

enum WAErroDoCliente: Error, Equatable {
    /// Não há arquivo de chave: nenhuma conexão foi aberta.
    case semChave
    /// Conexão recusada, tempo esgotado ou ATS barrando o loopback.
    case foraDoAr
    /// Dois `401` seguidos, mesmo depois de reler o arquivo.
    case chaveNaoConfere
    /// `2xx` com corpo que não decodifica.
    case respostaInvalida
    /// Corpo de erro do contrato (`{"ok": false, "erro": …, "detalhe": …}`).
    case ponte(status: Int, erro: String, detalhe: String?)

    var contaDesconectada: Bool {
        if case .ponte(409, "conta_desconectada", _) = self { return true }
        return false
    }

    var midiaExpirada: Bool {
        if case .ponte(410, "midia_expirada", _) = self { return true }
        return false
    }
}

/// Resposta de `GET /v1/foto`.
enum WAFoto: Equatable {
    case nova(Data, etag: String?)
    case igual
    case semFoto
}

final class WACliente {
    private let porta: Int
    private let caminhoDaChave: URL
    private let transporte: WATransporte

    private let trava = NSLock()
    private var chaveEmMemoria: String?

    private static let prazoLeitura: TimeInterval = 15
    private static let prazoArquivo: TimeInterval = 120

    init(porta: Int = WAConfig.porta(), caminhoDaChave: URL = WAChaveDaPonte.caminhoPadrao,
         transporte: WATransporte = WATransporteURLSession()) {
        self.porta = porta
        self.caminhoDaChave = caminhoDaChave
        self.transporte = transporte
    }

    /// A chave fica em memória: lê o arquivo na primeira vez (ou enquanto ele
    /// não existir) e quando `relendo == true` (docs/whatsapp-ponte.md:60-63).
    func chave(relendo: Bool = false) -> String? {
        trava.lock(); defer { trava.unlock() }
        if relendo || chaveEmMemoria == nil {
            chaveEmMemoria = WAChaveDaPonte.ler(em: caminhoDaChave)
        }
        return chaveEmMemoria
    }

    // MARK: - Identificação

    /// Sonda `GET /v1/ponte`. Sem arquivo de chave não abre conexão nenhuma.
    func identificar() async -> WAConclusaoDaSonda {
        do {
            let (dados, resposta) = try await executar("GET", "/v1/ponte", corpo: SemCorpo?.none,
                                                      prazo: Self.prazoLeitura)
            return WAConclusaoDaSonda.concluir(status: resposta.statusCode, corpo: dados)
        } catch WAErroDoCliente.semChave {
            return .semChave
        } catch WAErroDoCliente.chaveNaoConfere {
            return .chaveNaoConfere
        } catch {
            return .foraDoAr
        }
    }

    // MARK: - Leituras

    func contas() async throws -> [WAConta] {
        let r: WARespostaContas = try await json("GET", "/v1/contas")
        return r.contas
    }

    func conversas(conta: String, limite: Int = 50, antes: String? = nil) async throws -> WARespostaConversas {
        try await json("GET", "/v1/conversas",
                       query: [("conta", conta), ("limite", String(limite)), ("antes", antes)])
    }

    func conversa(conta: String, jid: String) async throws -> WAConversa {
        let r: WARespostaConversa = try await json("GET", "/v1/conversa", query: [("conta", conta), ("jid", jid)])
        return r.conversa
    }

    func mensagens(conta: String, conversa: String, limite: Int = 50,
                   antes: String? = nil) async throws -> WARespostaMensagens {
        try await json("GET", "/v1/mensagens",
                       query: [("conta", conta), ("conversa", conversa), ("limite", String(limite)),
                               ("antes", antes)])
    }

    func midia(conta: String, conversa: String, id: String,
               miniatura: Bool) async throws -> (dados: Data, mimetype: String?) {
        let (dados, resposta) = try await pedir(
            "GET", "/v1/midia",
            query: [("conta", conta), ("conversa", conversa), ("id", id), ("miniatura", miniatura ? "1" : nil)],
            prazo: Self.prazoArquivo)
        return (dados, resposta.value(forHTTPHeaderField: "Content-Type"))
    }

    func recuperarMidia(conta: String, conversa: String, id: String) async throws {
        struct Corpo: Encodable { let conta, conversa, id: String }
        _ = try await pedir("POST", "/v1/midia/recuperar", corpo: Corpo(conta: conta, conversa: conversa, id: id))
    }

    /// `etag` é o valor sem aspas que veio na última `.nova`; vai em `If-None-Match`.
    func foto(conta: String, jid: String, etag: String?) async throws -> WAFoto {
        let cabecalhos = etag.map { ["If-None-Match": "\"\($0)\""] } ?? [:]
        do {
            let (dados, resposta) = try await pedir(
                "GET", "/v1/foto", query: [("conta", conta), ("jid", jid), ("tamanho", "miniatura")],
                cabecalhos: cabecalhos, aceitos: [304])
            if resposta.statusCode == 304 { return .igual }
            let novaEtag = resposta.value(forHTTPHeaderField: "ETag")
                .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "\"")) }
            return .nova(dados, etag: novaEtag)
        } catch WAErroDoCliente.ponte(404, "sem_foto", _) {
            return .semFoto
        }
    }

    func grupo(conta: String, jid: String) async throws -> WAGrupo {
        let r: WARespostaGrupo = try await json("GET", "/v1/grupo", query: [("conta", conta), ("jid", jid)])
        return r.grupo
    }

    // MARK: - Envios

    func enviarTexto(conta: String, para: String, texto: String, citar: String?,
                     ref: String) async throws -> WARespostaEnvio {
        struct Corpo: Encodable { let conta, para, texto: String; let citar: String?; let ref: String }
        return try await json("POST", "/v1/enviar/texto",
                              corpo: Corpo(conta: conta, para: para, texto: texto, citar: citar, ref: ref),
                              prazo: Self.prazoArquivo)
    }

    /// `arquivo` vai como caminho absoluto: a ponte lê do disco.
    func enviarMidia(conta: String, para: String, tipo: String, arquivo: URL, nome: String?, legenda: String?,
                     citar: String?, ref: String) async throws -> WARespostaEnvio {
        struct Corpo: Encodable {
            let conta, para, tipo, arquivo: String
            let nome, legenda, citar: String?
            let ref: String
        }
        return try await json("POST", "/v1/enviar/midia",
                              corpo: Corpo(conta: conta, para: para, tipo: tipo, arquivo: arquivo.path,
                                           nome: nome, legenda: legenda, citar: citar, ref: ref),
                              prazo: Self.prazoArquivo)
    }

    func enviarVoz(conta: String, para: String, arquivo: URL, segundos: Int, onda: [Int], citar: String?,
                   ref: String) async throws -> WARespostaEnvio {
        struct Corpo: Encodable {
            let conta, para, arquivo: String
            let segundos: Int
            let onda: [Int]
            let citar: String?
            let ref: String
        }
        return try await json("POST", "/v1/enviar/voz",
                              corpo: Corpo(conta: conta, para: para, arquivo: arquivo.path, segundos: segundos,
                                           onda: onda, citar: citar, ref: ref),
                              prazo: Self.prazoArquivo)
    }

    /// `emoji` vazio remove a reação.
    func reagir(conta: String, conversa: String, alvo: String, emoji: String) async throws {
        struct Corpo: Encodable { let conta, conversa, alvo, emoji: String }
        _ = try await pedir("POST", "/v1/reagir",
                            corpo: Corpo(conta: conta, conversa: conversa, alvo: alvo, emoji: emoji))
    }

    /// Devolve quantas mensagens a ponte marcou como lidas.
    func marcarLida(conta: String, conversa: String) async throws -> Int {
        struct Corpo: Encodable { let conta, conversa: String }
        let r: WARespostaLida = try await json("POST", "/v1/lida", corpo: Corpo(conta: conta, conversa: conversa))
        return r.marcadas
    }

    // MARK: - Pareamento

    /// Com outro pareamento aberto (`409 pareamento_em_andamento`), devolve o que veio no corpo.
    func iniciarPareamento() async throws -> WAPareamento {
        let (dados, resposta) = try await pedir("POST", "/v1/pareamento", aceitos: [409])
        if resposta.statusCode == 409 {
            guard let e = try? WAJSON.decodificador.decode(WAErroDaPonte.self, from: dados),
                  e.erro == "pareamento_em_andamento",
                  let r = try? WAJSON.decodificador.decode(WARespostaPareamento.self, from: dados) else {
                throw Self.erroDaPonte(status: 409, dados: dados)
            }
            return r.pareamento
        }
        return try Self.decodificar(WARespostaPareamento.self, dados).pareamento
    }

    /// `nil` quando não há pareamento (`404 sem_pareamento`).
    func pareamentoAtual() async throws -> WAPareamento? {
        do {
            let r: WARespostaPareamento = try await json("GET", "/v1/pareamento")
            return r.pareamento
        } catch WAErroDoCliente.ponte(404, "sem_pareamento", _) {
            return nil
        }
    }

    func cancelarPareamento() async throws {
        _ = try await pedir("DELETE", "/v1/pareamento")
    }

    // MARK: - Pedido

    private struct SemCorpo: Encodable {}

    private func json<T: Decodable>(_ metodo: String, _ caminho: String, query: [(String, String?)] = [],
                                    prazo: TimeInterval = WACliente.prazoLeitura) async throws -> T {
        try await json(metodo, caminho, query: query, corpo: SemCorpo?.none, prazo: prazo)
    }

    private func json<T: Decodable, C: Encodable>(_ metodo: String, _ caminho: String,
                                                  query: [(String, String?)] = [], corpo: C?,
                                                  prazo: TimeInterval = WACliente.prazoLeitura) async throws -> T {
        let (dados, _) = try await pedir(metodo, caminho, query: query, corpo: corpo, prazo: prazo)
        return try Self.decodificar(T.self, dados)
    }

    private func pedir(_ metodo: String, _ caminho: String, query: [(String, String?)] = [],
                       cabecalhos: [String: String] = [:], aceitos: Set<Int> = [],
                       prazo: TimeInterval = WACliente.prazoLeitura) async throws -> (Data, HTTPURLResponse) {
        try await pedir(metodo, caminho, query: query, corpo: SemCorpo?.none, cabecalhos: cabecalhos,
                        aceitos: aceitos, prazo: prazo)
    }

    /// Devolve a resposta `2xx` (ou de status em `aceitos`); o resto vira
    /// `.ponte(status:erro:detalhe:)`.
    private func pedir<C: Encodable>(_ metodo: String, _ caminho: String, query: [(String, String?)] = [],
                                     corpo: C?, cabecalhos: [String: String] = [:], aceitos: Set<Int> = [],
                                     prazo: TimeInterval = WACliente.prazoLeitura) async throws -> (Data, HTTPURLResponse) {
        let (dados, resposta) = try await executar(metodo, caminho, query: query, corpo: corpo,
                                                   cabecalhos: cabecalhos, prazo: prazo)
        let status = resposta.statusCode
        guard (200..<300).contains(status) || aceitos.contains(status) else {
            let erro = Self.erroDaPonte(status: status, dados: dados)
            if case let .ponte(_, codigo, _) = erro {
                log.info("ponte respondeu \(status) \(codigo, privacy: .public) em \(metodo, privacy: .public) \(caminho, privacy: .public)")
            }
            throw erro
        }
        return (dados, resposta)
    }

    /// Monta o pedido, aplica a chave, trata `401` com uma releitura do arquivo
    /// e mapeia `URLError`. Devolve qualquer status que não seja `401`.
    private func executar<C: Encodable>(_ metodo: String, _ caminho: String, query: [(String, String?)] = [],
                                        corpo: C?, cabecalhos: [String: String] = [:],
                                        prazo: TimeInterval) async throws -> (Data, HTTPURLResponse) {
        guard let primeira = chave() else { throw WAErroDoCliente.semChave }

        var componentes = URLComponents(url: WAConfig.base(porta: porta), resolvingAgainstBaseURL: false)!
        componentes.path = caminho
        let itens = query.compactMap { nome, valor in
            valor.map { URLQueryItem(name: nome, value: Self.codificar($0)) }
        }
        componentes.percentEncodedQueryItems = itens.isEmpty ? nil : itens
        guard let url = componentes.url else { throw WAErroDoCliente.respostaInvalida }

        var pedido = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: prazo)
        pedido.httpMethod = metodo
        for (nome, valor) in cabecalhos { pedido.setValue(valor, forHTTPHeaderField: nome) }
        if let corpo {
            pedido.setValue("application/json", forHTTPHeaderField: "Content-Type")
            pedido.httpBody = try WAJSON.codificador.encode(corpo)
        }

        let (dados, resposta) = try await enviar(pedido, chave: primeira)
        guard resposta.statusCode == 401 else { return (dados, resposta) }

        log.info("401 da ponte em \(caminho, privacy: .public): relendo o arquivo da chave")
        guard let segunda = chave(relendo: true) else { throw WAErroDoCliente.semChave }
        let (dados2, resposta2) = try await enviar(pedido, chave: segunda)
        guard resposta2.statusCode != 401 else {
            log.error("a chave da ponte não confere (dois 401 seguidos)")
            throw WAErroDoCliente.chaveNaoConfere
        }
        return (dados2, resposta2)
    }

    private func enviar(_ pedido: URLRequest, chave: String) async throws -> (Data, HTTPURLResponse) {
        var pedido = pedido
        pedido.setValue("Bearer \(chave)", forHTTPHeaderField: "Authorization")
        do {
            return try await transporte.enviar(pedido)
        } catch let erro as URLError {
            switch erro.code {
            case .appTransportSecurityRequiresSecureConnection:
                log.fault("ATS barrou a ponte em 127.0.0.1: falta a exceção no Info.plist")
                throw WAErroDoCliente.foraDoAr
            case .cannotConnectToHost, .timedOut, .networkConnectionLost, .cannotFindHost:
                log.debug("ponte fora do ar (URLError \(erro.code.rawValue))")
                throw WAErroDoCliente.foraDoAr
            default:
                throw erro
            }
        }
    }

    // MARK: - Ajudantes

    /// Só ASCII não reservado passa cru: `@`, `/`, `=`, `&` e `+` vão escapados.
    private static let permitidosNaQuery = CharacterSet(
        charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")

    private static func codificar(_ valor: String) -> String {
        valor.addingPercentEncoding(withAllowedCharacters: permitidosNaQuery) ?? valor
    }

    private static func decodificar<T: Decodable>(_ tipo: T.Type, _ dados: Data) throws -> T {
        do {
            return try WAJSON.decodificador.decode(tipo, from: dados)
        } catch {
            log.error("resposta da ponte não decodifica como \(String(describing: tipo), privacy: .public)")
            throw WAErroDoCliente.respostaInvalida
        }
    }

    /// Corpo de erro do contrato, ou `erro: "desconhecido"` se não for JSON.
    private static func erroDaPonte(status: Int, dados: Data) -> WAErroDoCliente {
        guard let e = try? WAJSON.decodificador.decode(WAErroDaPonte.self, from: dados) else {
            return .ponte(status: status, erro: "desconhecido", detalhe: nil)
        }
        return .ponte(status: status, erro: e.erro, detalhe: e.detalhe)
    }
}
