import Foundation

// Tipos do contrato da ponte do WhatsApp (docs/whatsapp-ponte.md) e a
// decodificação dos eventos do WebSocket. Só leitura: o que o Knobler manda
// para a ponte é montado por quem chama, com `WAJSON.codificador`.

/// Decodificador e codificador do contrato. Os campos da ponte são snake_case
/// em pt-BR (`nao_lidas`, `de_mim`, `qr_expira_em`…); aqui viram camelCase.
enum WAJSON {
    static let decodificador: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }()

    static let codificador: JSONEncoder = {
        let e = JSONEncoder()
        e.keyEncodingStrategy = .convertToSnakeCase
        e.outputFormatting = .sortedKeys
        return e
    }()
}

// MARK: - Enums tolerantes a valor novo

/// Enum lido de uma `String` do contrato que cai em `.outro` com valor que
/// ainda não conhece, em vez de derrubar o objeto inteiro.
private protocol WABruto: Decodable {
    init(bruto: String)
}

extension WABruto {
    init(from decoder: Decoder) throws {
        self.init(bruto: try decoder.singleValueContainer().decode(String.self))
    }
}

enum WAEstadoConta: Equatable, WABruto {
    case conectando, conectada, desconectada, deslogada, substituida, suspensa
    case outro(String)

    init(bruto: String) {
        switch bruto {
        case "conectando": self = .conectando
        case "conectada": self = .conectada
        case "desconectada": self = .desconectada
        case "deslogada": self = .deslogada
        case "substituida": self = .substituida
        case "suspensa": self = .suspensa
        default: self = .outro(bruto)
        }
    }
}

enum WATipoConversa: Equatable, WABruto {
    case individual, grupo
    case outro(String)

    init(bruto: String) {
        switch bruto {
        case "individual": self = .individual
        case "grupo": self = .grupo
        default: self = .outro(bruto)
        }
    }
}

enum WATipoMensagem: Equatable, WABruto {
    case texto, imagem, video, audio, voz, documento, figurinha
    case outro(String)

    init(bruto: String) {
        switch bruto {
        case "texto": self = .texto
        case "imagem": self = .imagem
        case "video": self = .video
        case "audio": self = .audio
        case "voz": self = .voz
        case "documento": self = .documento
        case "figurinha": self = .figurinha
        default: self = .outro(bruto)
        }
    }
}

enum WAEstadoPareamento: Equatable, WABruto {
    case iniciando, qr, sucesso, expirado, cancelado, erro
    case outro(String)

    init(bruto: String) {
        switch bruto {
        case "iniciando": self = .iniciando
        case "qr": self = .qr
        case "sucesso": self = .sucesso
        case "expirado": self = .expirado
        case "cancelado": self = .cancelado
        case "erro": self = .erro
        default: self = .outro(bruto)
        }
    }
}

enum WARecibo: Equatable, WABruto {
    case entregue, lida, lidaPorMim
    case outro(String)

    init(bruto: String) {
        switch bruto {
        case "entregue": self = .entregue
        case "lida": self = .lida
        case "lida_por_mim": self = .lidaPorMim
        default: self = .outro(bruto)
        }
    }
}

/// Status de mensagem minha. Só anda para a frente: enviada → entregue → lida.
enum WAStatus: String, Decodable, Comparable {
    case enviada, entregue, lida

    private var ordem: Int {
        switch self {
        case .enviada: return 0
        case .entregue: return 1
        case .lida: return 2
        }
    }

    static func < (a: WAStatus, b: WAStatus) -> Bool { a.ordem < b.ordem }
}

// MARK: - Objetos do contrato

struct WAConta: Decodable, Equatable {
    let conta: String
    let jid: String?
    let nome: String?
    let padrao: Bool
    let estado: WAEstadoConta
    let motivo: String?
    let desde: Int
    let naoLidas: Int
    let conversasNaoLidas: Int
}

/// Resumo da última mensagem de uma conversa. `segundos` e `apagada` são
/// opcionais também na ausência da chave: ponte mais velha não derruba a lista.
struct WAUltima: Decodable, Equatable {
    let id: String
    let deMim: Bool
    let remetente: String
    let remetenteNome: String?
    let tipo: WATipoMensagem
    let previa: String
    let ts: Int
    let apagada: Int?
    let segundos: Int?
}

struct WAConversa: Decodable, Equatable {
    let jid: String
    let jids: [String]
    let tipo: WATipoConversa
    let nome: String
    let naoLidas: Int
    let marcadaNaoLida: Bool
    let ts: Int
    let ultima: WAUltima?
}

struct WAMidia: Decodable, Equatable {
    let mimetype: String
    let nome: String
    let tamanho: Int
    let segundos: Int?
    let miniatura: Bool
    let baixada: Bool
}

struct WACitacao: Decodable, Equatable {
    let id: String
    let remetente: String
    let texto: String
}

struct WAReacao: Decodable, Equatable {
    let remetente: String
    let deMim: Bool
    let emoji: String
    let ts: Int
}

struct WAMensagem: Equatable {
    let id: String
    let conversa: String
    let remetente: String
    let remetenteNome: String?
    let deMim: Bool
    let ts: Int
    let tipo: WATipoMensagem
    var texto: String
    var midia: WAMidia?
    let citacao: WACitacao?
    var reacoes: [WAReacao]
    var editada: Int?
    var apagada: Int?
    var status: WAStatus?
}

// Em extensão para manter o init memberwise (o estado cria bolhas locais com ele).
extension WAMensagem: Decodable {
    private enum CodingKeys: String, CodingKey {
        case id, conversa, remetente, remetenteNome, deMim, ts, tipo, texto
        case midia, citacao, reacoes, editada, apagada, status
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        conversa = try c.decode(String.self, forKey: .conversa)
        remetente = try c.decode(String.self, forKey: .remetente)
        remetenteNome = try c.decodeIfPresent(String.self, forKey: .remetenteNome)
        deMim = try c.decode(Bool.self, forKey: .deMim)
        ts = try c.decode(Int.self, forKey: .ts)
        tipo = try c.decode(WATipoMensagem.self, forKey: .tipo)
        texto = try c.decode(String.self, forKey: .texto)
        midia = try c.decodeIfPresent(WAMidia.self, forKey: .midia)
        citacao = try c.decodeIfPresent(WACitacao.self, forKey: .citacao)
        reacoes = try c.decodeIfPresent([WAReacao].self, forKey: .reacoes) ?? []
        editada = try c.decodeIfPresent(Int.self, forKey: .editada)
        apagada = try c.decodeIfPresent(Int.self, forKey: .apagada)
        status = try c.decodeIfPresent(WAStatus.self, forKey: .status)
    }
}

struct WAPareamento: Decodable, Equatable {
    let id: String
    let estado: WAEstadoPareamento
    let qr: String?
    let qrExpiraEm: Int?
    let fim: Int?
    let conta: String?
    let motivo: String?
}

struct WAParticipante: Decodable, Equatable {
    let jid: String
    let telefone: String?
    let lid: String?
    let nome: String?
    let admin: Bool
    let superadmin: Bool
    let eu: Bool
}

struct WAGrupo: Decodable, Equatable {
    let jid: String
    let nome: String
    let descricao: String
    let criado: Int
    let dono: String?
    let soAdminsEnviam: Bool
    let participantes: [WAParticipante]
}

/// Resposta de `GET /` da ponte: diz que é ela e qual contrato fala.
struct WAIdentificacao: Decodable, Equatable {
    let servico: String
    let contrato: Int
    let versao: String
}

/// Corpo de erro da ponte (`{"ok": false, "erro": …, "detalhe": …}`).
struct WAErroDaPonte: Decodable, Equatable {
    let erro: String
    let detalhe: String?
}

// MARK: - Respostas das rotas

struct WARespostaContas: Decodable, Equatable {
    let contas: [WAConta]
}

struct WARespostaConversas: Decodable, Equatable {
    let conversas: [WAConversa]
    let antes: String?
}

struct WARespostaConversa: Decodable, Equatable {
    let conversa: WAConversa
}

struct WARespostaMensagens: Decodable, Equatable {
    let conversa: String
    let mensagens: [WAMensagem]
    let antes: String?
}

struct WARespostaEnvio: Decodable, Equatable {
    let ref: String?
    let mensagem: WAMensagem
}

struct WARespostaLida: Decodable, Equatable {
    let marcadas: Int
}

struct WARespostaPareamento: Decodable, Equatable {
    let pareamento: WAPareamento
}

struct WARespostaGrupo: Decodable, Equatable {
    let grupo: WAGrupo
}

// MARK: - Eventos do WebSocket

/// `dados` de um evento numerado (gravado no diário da ponte, entra no `desde`).
enum WAEventoNumerado: Equatable {
    case mensagem(WAMensagem, WAConversa, ref: String?)
    case recibo(conversa: String, ids: [String], recibo: WARecibo, de: String, ts: Int)
    case reacao(conversa: String, alvo: String, remetente: String, deMim: Bool, emoji: String, ts: Int)
    case edicao(conversa: String, alvo: String, texto: String, ts: Int)
    case apagamento(conversa: String, alvo: String, por: String, ts: Int)
    case leitura(conversa: String, naoLidas: Int, marcadaNaoLida: Bool)
    case midia(conversa: String, alvo: String, ok: Bool)
    case sincronizacao(conversas: Int)
    /// Tipo que este Knobler ainda não conhece; o `seq` conta mesmo assim.
    case desconhecido(tipo: String)
}

enum WAEvento: Equatable {
    case ola(contrato: Int, jornal: String, seqAtual: Int, seqMinimo: Int)
    case ressincronize(jornal: String, seqAtual: Int)
    case numerado(seq: Int, conta: String, ts: Int, WAEventoNumerado)
    case conta(WAConta)
    case pareamento(WAPareamento)
    case desconhecido(tipo: String)

    /// Lê um quadro de texto do WebSocket. `nil` quando não é JSON, não tem
    /// `tipo` ou os dados não batem com o tipo.
    static func decodificar(_ texto: String) -> WAEvento? {
        let data = Data(texto.utf8)
        let d = WAJSON.decodificador
        guard let cab = try? d.decode(Cabecalho.self, from: data) else { return nil }

        switch cab.tipo {
        case "ola":
            guard let o = try? d.decode(Ola.self, from: data) else { return nil }
            return .ola(contrato: o.contrato, jornal: o.jornal, seqAtual: o.seqAtual, seqMinimo: o.seqMinimo)
        case "ressincronize":
            guard let r = try? d.decode(Ressincronize.self, from: data) else { return nil }
            return .ressincronize(jornal: r.jornal, seqAtual: r.seqAtual)
        default:
            break
        }

        guard let seq = cab.seq else {
            // eventos de estado: sem `seq`
            switch cab.tipo {
            case "conta":
                return (try? d.decode(Envelope<WAConta>.self, from: data)).map { .conta($0.dados) }
            case "pareamento":
                return (try? d.decode(Envelope<WAPareamento>.self, from: data)).map { .pareamento($0.dados) }
            default:
                return .desconhecido(tipo: cab.tipo)
            }
        }

        guard let conta = cab.conta, let ts = cab.ts,
              let dados = numerado(cab.tipo, data, d) else { return nil }
        return .numerado(seq: seq, conta: conta, ts: ts, dados)
    }

    private static func numerado(_ tipo: String, _ data: Data, _ d: JSONDecoder) -> WAEventoNumerado? {
        func dados<T: Decodable>(_: T.Type) -> T? {
            (try? d.decode(Envelope<T>.self, from: data))?.dados
        }
        switch tipo {
        case "mensagem":
            return dados(DadosMensagem.self).map { .mensagem($0.mensagem, $0.conversa, ref: $0.ref) }
        case "recibo":
            return dados(DadosRecibo.self).map {
                .recibo(conversa: $0.conversa, ids: $0.ids, recibo: $0.recibo, de: $0.de, ts: $0.ts)
            }
        case "reacao":
            return dados(DadosReacao.self).map {
                .reacao(conversa: $0.conversa, alvo: $0.alvo, remetente: $0.remetente,
                        deMim: $0.deMim, emoji: $0.emoji, ts: $0.ts)
            }
        case "edicao":
            return dados(DadosEdicao.self).map {
                .edicao(conversa: $0.conversa, alvo: $0.alvo, texto: $0.texto, ts: $0.ts)
            }
        case "apagamento":
            return dados(DadosApagamento.self).map {
                .apagamento(conversa: $0.conversa, alvo: $0.alvo, por: $0.por, ts: $0.ts)
            }
        case "leitura":
            return dados(DadosLeitura.self).map {
                .leitura(conversa: $0.conversa, naoLidas: $0.naoLidas, marcadaNaoLida: $0.marcadaNaoLida)
            }
        case "midia":
            return dados(DadosMidia.self).map { .midia(conversa: $0.conversa, alvo: $0.alvo, ok: $0.ok) }
        case "sincronizacao":
            return dados(DadosSincronizacao.self).map { .sincronizacao(conversas: $0.conversas) }
        default:
            return .desconhecido(tipo: tipo)
        }
    }

    // Formato dos envelopes: docs/whatsapp-ponte.md, "Formato dos eventos".
    private struct Cabecalho: Decodable {
        let tipo: String
        let seq: Int?
        let conta: String?
        let ts: Int?
    }

    private struct Envelope<T: Decodable>: Decodable {
        let dados: T
    }

    private struct Ola: Decodable {
        let contrato: Int
        let jornal: String
        let seqAtual: Int
        let seqMinimo: Int
    }

    private struct Ressincronize: Decodable {
        let jornal: String
        let seqAtual: Int
    }

    private struct DadosMensagem: Decodable {
        let mensagem: WAMensagem
        let conversa: WAConversa
        let ref: String?
    }

    private struct DadosRecibo: Decodable {
        let conversa: String
        let ids: [String]
        let recibo: WARecibo
        let de: String
        let ts: Int
    }

    private struct DadosReacao: Decodable {
        let conversa: String
        let alvo: String
        let remetente: String
        let deMim: Bool
        let emoji: String
        let ts: Int
    }

    private struct DadosEdicao: Decodable {
        let conversa: String
        let alvo: String
        let texto: String
        let ts: Int
    }

    private struct DadosApagamento: Decodable {
        let conversa: String
        let alvo: String
        let por: String
        let ts: Int
    }

    private struct DadosLeitura: Decodable {
        let conversa: String
        let naoLidas: Int
        let marcadaNaoLida: Bool
    }

    private struct DadosMidia: Decodable {
        let conversa: String
        let alvo: String
        let ok: Bool
    }

    private struct DadosSincronizacao: Decodable {
        let conversas: Int
    }
}

// MARK: - Chave de conversa

/// Identifica uma conversa entre as contas: `"<conta>|<jid>"`.
struct WAChave: Hashable {
    let conta: String
    let jid: String

    var texto: String { "\(conta)|\(jid)" }

    init(conta: String, jid: String) {
        self.conta = conta
        self.jid = jid
    }

    /// Corta no primeiro `|`; `nil` sem `|` ou com uma das metades vazia.
    init?(texto: String) {
        guard let barra = texto.firstIndex(of: "|") else { return nil }
        let conta = String(texto[..<barra])
        let jid = String(texto[texto.index(after: barra)...])
        guard !conta.isEmpty, !jid.isEmpty else { return nil }
        self.init(conta: conta, jid: jid)
    }
}
