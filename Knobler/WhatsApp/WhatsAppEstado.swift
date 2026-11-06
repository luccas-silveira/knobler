import Foundation

// Estado puro do WhatsApp: contas, conversas por conta, bolhas por conversa
// carregada, cursores, rascunhos e a deduplicação dos eventos. Sem rede, sem
// disco, sem UI: quem tem o canal chama `aplicar(_:conta:)` e lê o efeito.
// Efeito de cada evento em docs/whatsapp-ponte.md:840-939; ordem das conversas
// em :465 e das mensagens em :488-490.

/// Envio local ainda sem confirmação da ponte.
enum WAEnvio: Equatable {
    case enviando(ref: String)
    case falhou(ref: String)
}

/// Uma mensagem como desenhada: o contrato mais o que só o Knobler sabe.
struct WABolha: Equatable, Identifiable {
    var mensagem: WAMensagem
    var envio: WAEnvio? = nil
    var midiaIndisponivel = false
    var id: String { mensagem.id }
}

/// O que um evento aplicado pede de quem está em volta.
enum WAEfeito: Equatable {
    case nada
    case atualizou
    case mensagemNova(WAMensagem, WAConversa)
}

struct WAEstado: Equatable {
    /// Padrão primeiro, depois por número.
    var contas: [WAConta] = []
    /// Por conta, em `ts` decrescente com desempate por `jid`.
    private(set) var conversasPorConta: [String: [WAConversa]] = [:]
    /// Conversas com página lida ou com envio local, em `ts` crescente com
    /// desempate por `id`. A chave usa o jid canônico.
    private(set) var bolhasPorChave: [WAChave: [WABolha]] = [:]
    /// Conversas cuja página veio da ponte (`inserirMensagens` chamado). Ter
    /// bolha não basta: o envio pelo card cria a lista sem o histórico.
    private var paginasLidas: Set<WAChave> = []
    /// Cursor da página anterior; ausente = chegou ao começo.
    var antes: [WAChave: String] = [:]
    private(set) var rascunhos: [WAChave: String] = [:]
    var pareamento: WAPareamento?

    /// `"conta|canonico|id"` das mensagens já entregues pelo canal, FIFO.
    private var vistos: Set<String> = []
    private var filaDeVistos: [String] = []
    private static let limiteDeVistos = 1000

    /// Por conta: apelido (LID, telefone) → jid canônico.
    private var apelidos: [String: [String: String]] = [:]

    /// `ref` trocados por `retentar`: a confirmação atrasada deles é ignorada.
    private var refsAbandonados: Set<String> = []

    // MARK: - Contas

    mutating func substituirContas(_ novas: [WAConta]) {
        contas = Self.ordenadas(novas)
    }

    /// Evento `conta`: troca a conta pelo número (ou acrescenta se é nova).
    mutating func aplicar(conta nova: WAConta) {
        var lista = contas.filter { $0.conta != nova.conta }
        lista.append(nova)
        contas = Self.ordenadas(lista)
    }

    /// Soma do `conversas_nao_lidas` das contas. A lista de conversas é só uma
    /// página e não serve para somar (docs/whatsapp-ponte.md:941-945).
    var sinalDaFaixa: Int { contas.reduce(0) { $0 + $1.conversasNaoLidas } }

    private static func ordenadas(_ cs: [WAConta]) -> [WAConta] {
        cs.sorted { a, b in
            if a.padrao != b.padrao { return a.padrao }
            return a.conta < b.conta
        }
    }

    // MARK: - Conversas

    func conversas(da conta: String) -> [WAConversa] {
        conversasPorConta[conta] ?? []
    }

    mutating func substituirConversas(conta: String, _ novas: [WAConversa]) {
        conversasPorConta[conta] = Self.ordenadas(novas)
        refazerApelidos(conta: conta)
    }

    /// Troca a conversa (pelo `jid` ou por qualquer apelido dela) ou a acrescenta.
    mutating func atualizarConversa(conta: String, _ nova: WAConversa) {
        let nomes = Set(nova.jids + [nova.jid])
        var lista = conversas(da: conta).filter { !nomes.contains($0.jid) }
        lista.append(nova)
        conversasPorConta[conta] = Self.ordenadas(lista)
        refazerApelidos(conta: conta)
    }

    /// O jid canônico de um apelido; jid desconhecido volta como veio.
    func canonico(conta: String, jid: String) -> String {
        apelidos[conta]?[jid] ?? jid
    }

    private mutating func refazerApelidos(conta: String) {
        var indice: [String: String] = [:]
        for c in conversas(da: conta) {
            for j in c.jids { indice[j] = c.jid }
            indice[c.jid] = c.jid
        }
        apelidos[conta] = indice
    }

    private static func ordenadas(_ cs: [WAConversa]) -> [WAConversa] {
        cs.sorted { a, b in a.ts != b.ts ? a.ts > b.ts : a.jid < b.jid }
    }

    /// Troca uma conversa da lista; `false` se ela não está lá.
    private mutating func mudarConversa(conta: String, jid: String,
                                        _ muda: (WAConversa) -> WAConversa) -> Bool {
        guard var lista = conversasPorConta[conta],
              let i = lista.firstIndex(where: { $0.jid == jid }) else { return false }
        lista[i] = muda(lista[i])
        conversasPorConta[conta] = Self.ordenadas(lista)
        return true
    }

    // MARK: - Bolhas

    func bolhas(de chave: WAChave) -> [WABolha] {
        bolhasPorChave[chave] ?? []
    }

    func carregada(_ chave: WAChave) -> Bool {
        bolhasPorChave[chave] != nil
    }

    /// O histórico da conversa já foi lido da ponte (não só bolha local).
    func historicoLido(_ chave: WAChave) -> Bool {
        paginasLidas.contains(chave)
    }

    /// Página de `GET /v1/mensagens`. `maisVelhas: false` troca as bolhas pela
    /// página mais recente; `true` junta a página antiga sem repetir `id`. A
    /// primeira página de uma conversa junta-se às bolhas do envio feito antes
    /// dela (enviando ou já casadas pelo `ref`), sem repetir `id`.
    mutating func inserirMensagens(_ mensagens: [WAMensagem], em chave: WAChave,
                                   antes cursor: String?, maisVelhas: Bool) {
        var lista = maisVelhas || !historicoLido(chave) ? bolhas(de: chave) : []
        let conhecidos = Set(lista.map(\.id))
        var novos = Set<String>()
        for m in mensagens where !conhecidos.contains(m.id) && novos.insert(m.id).inserted {
            lista.append(WABolha(mensagem: m))
        }
        bolhasPorChave[chave] = Self.ordenadas(lista)
        antes[chave] = cursor
        paginasLidas.insert(chave)
    }

    private static func ordenadas(_ bs: [WABolha]) -> [WABolha] {
        bs.sorted { a, b in
            a.mensagem.ts != b.mensagem.ts ? a.mensagem.ts < b.mensagem.ts : a.id < b.id
        }
    }

    /// Muda uma bolha de conversa carregada; `false` se o alvo não está lá.
    private mutating func mudarBolha(_ chave: WAChave, id: String,
                                     _ muda: (inout WABolha) -> Void) -> Bool {
        guard var lista = bolhasPorChave[chave],
              let i = lista.firstIndex(where: { $0.id == id }) else { return false }
        let anterior = lista[i]
        muda(&lista[i])
        guard lista[i] != anterior else { return false }
        bolhasPorChave[chave] = lista
        return true
    }

    // MARK: - Eventos

    @discardableResult
    mutating func aplicar(_ e: WAEventoNumerado, conta: String) -> WAEfeito {
        switch e {
        case let .mensagem(m, cv, ref):
            return aplicarMensagem(m, cv, ref: ref, conta: conta)

        case let .recibo(conversa, ids, recibo, _, _):
            let alvo: WAStatus
            switch recibo {
            case .entregue: alvo = .entregue
            case .lida: alvo = .lida
            // `lida_por_mim` chega à conversa pelo `leitura` que a ponte publica
            case .lidaPorMim, .outro: return .nada
            }
            let k = WAChave(conta: conta, jid: canonico(conta: conta, jid: conversa))
            var mudou = false
            for id in ids {
                mudou = mudarBolha(k, id: id) { b in
                    guard b.mensagem.deMim else { return }
                    b.mensagem.status = max(b.mensagem.status ?? .enviada, alvo)
                } || mudou
            }
            return mudou ? .atualizou : .nada

        case let .reacao(conversa, alvo, remetente, deMim, emoji, ts):
            let k = WAChave(conta: conta, jid: canonico(conta: conta, jid: conversa))
            let mudou = mudarBolha(k, id: alvo) { b in
                let nova = WAReacao(remetente: remetente, deMim: deMim, emoji: emoji, ts: ts)
                if let i = b.mensagem.reacoes.firstIndex(where: { $0.remetente == remetente }) {
                    if emoji.isEmpty { b.mensagem.reacoes.remove(at: i) } else { b.mensagem.reacoes[i] = nova }
                } else if !emoji.isEmpty {
                    b.mensagem.reacoes.append(nova)
                }
            }
            return mudou ? .atualizou : .nada

        case let .edicao(conversa, alvo, texto, ts):
            let k = WAChave(conta: conta, jid: canonico(conta: conta, jid: conversa))
            let mudou = mudarBolha(k, id: alvo) { b in
                b.mensagem.texto = texto
                b.mensagem.editada = ts
            }
            return mudou ? .atualizou : .nada

        case let .apagamento(conversa, alvo, _, ts):
            let k = WAChave(conta: conta, jid: canonico(conta: conta, jid: conversa))
            let mudou = mudarBolha(k, id: alvo) { b in
                b.mensagem.texto = ""
                b.mensagem.midia = nil
                b.mensagem.apagada = ts
            }
            return mudou ? .atualizou : .nada

        case let .leitura(conversa, naoLidas, marcada):
            let jid = canonico(conta: conta, jid: conversa)
            let mudou = mudarConversa(conta: conta, jid: jid) { c in
                WAConversa(jid: c.jid, jids: c.jids, tipo: c.tipo, nome: c.nome,
                           naoLidas: naoLidas, marcadaNaoLida: marcada, ts: c.ts, ultima: c.ultima)
            }
            return mudou ? .atualizou : .nada

        case let .midia(conversa, alvo, ok):
            let k = WAChave(conta: conta, jid: canonico(conta: conta, jid: conversa))
            return mudarBolha(k, id: alvo) { $0.midiaIndisponivel = !ok } ? .atualizou : .nada

        case .sincronizacao:
            // quem chama relê /v1/conversas; o estado não muda aqui
            return .atualizou

        case .desconhecido:
            return .nada
        }
    }

    private mutating func aplicarMensagem(_ m: WAMensagem, _ cv: WAConversa, ref: String?,
                                          conta: String) -> WAEfeito {
        let marca = "\(conta)|\(cv.jid)|\(m.id)"
        guard !vistos.contains(marca) else { return .nada }
        vistos.insert(marca)
        filaDeVistos.append(marca)
        if filaDeVistos.count > Self.limiteDeVistos {
            vistos.remove(filaDeVistos.removeFirst())
        }

        atualizarConversa(conta: conta, cv)

        // bolha só em conversa com lista; a sem lista lê a página ao abrir
        let k = WAChave(conta: conta, jid: cv.jid)
        if var lista = bolhasPorChave[k] {
            if let i = lista.firstIndex(where: { $0.id == m.id }) {
                // o recibo pode ter chegado antes: o status não volta
                let status = Self.maiorStatus(lista[i].mensagem.status, m.status)
                lista[i].mensagem = m
                lista[i].mensagem.status = status
                lista[i].envio = nil
            } else if let ref, let i = lista.firstIndex(where: { $0.envio == .enviando(ref: ref) }) {
                // o evento chegou antes da resposta do envio: troca a bolha local
                lista[i] = WABolha(mensagem: m)
            } else {
                lista.append(WABolha(mensagem: m))
            }
            bolhasPorChave[k] = Self.ordenadas(lista)
        }
        return .mensagemNova(m, cv)
    }

    private static func maiorStatus(_ a: WAStatus?, _ b: WAStatus?) -> WAStatus? {
        guard let a, let b else { return a ?? b }
        return max(a, b)
    }

    // MARK: - Rascunho

    func rascunho(de chave: WAChave) -> String {
        rascunhos[chave] ?? ""
    }

    /// Texto vazio apaga o rascunho.
    mutating func definirRascunho(_ texto: String, para chave: WAChave) {
        rascunhos[chave] = texto.isEmpty ? nil : texto
    }

    // MARK: - Limpeza

    /// Some com conversas, bolhas, cursores e a deduplicação (ex.: `ressincronize`);
    /// contas, rascunhos e pareamento ficam.
    mutating func esvaziarConversas() {
        conversasPorConta = [:]
        bolhasPorChave = [:]
        paginasLidas = []
        antes = [:]
        vistos = []
        filaDeVistos = []
        apelidos = [:]
        refsAbandonados = []
    }
}

// MARK: - Envio

/// Como a bolha se desenha: o envio local manda; depois, o status do contrato.
enum WAEstadoDaBolha: Equatable {
    case enviando, enviada, entregue, lida, falhou, recebida
}

// Bolha local "enviando" casada com a mensagem real pelo `ref` que a ponte
// devolve na resposta e no evento `mensagem` (docs/whatsapp-ponte.md:272-275),
// chegue um ou outro primeiro. Falha não reenvia sozinha: só `retentar`.
extension WAEstado {
    /// Põe a bolha local no fim da conversa (carregando-a se preciso) e devolve
    /// o `id` dela, `"local-<ref>"`.
    @discardableResult
    mutating func comecarEnvio(chave: WAChave, texto: String, tipo: WATipoMensagem = .texto,
                               citacao: WACitacao?, ref: String, agora: Int,
                               remetente: String) -> String {
        let id = "local-\(ref)"
        let m = WAMensagem(id: id, conversa: chave.jid, remetente: remetente,
                           remetenteNome: nil, deMim: true, ts: agora, tipo: tipo,
                           texto: texto, midia: nil, citacao: citacao, reacoes: [],
                           editada: nil, apagada: nil, status: nil)
        var lista = bolhas(de: chave).filter { $0.id != id }
        lista.append(WABolha(mensagem: m, envio: .enviando(ref: ref)))
        bolhasPorChave[chave] = Self.ordenadas(lista)
        return id
    }

    /// Resposta do envio. Troca a bolha local pela real; se o evento já trouxe a
    /// real, só tira o pendente sem voltar o status; sem nenhuma das duas
    /// (evento perdido), insere a real.
    mutating func confirmarEnvio(ref: String, mensagem m: WAMensagem, chave: WAChave) {
        guard !refsAbandonados.contains(ref), var lista = bolhasPorChave[chave] else { return }
        if let i = lista.firstIndex(where: { $0.id == m.id }) {
            lista[i].mensagem.status = Self.maiorStatus(lista[i].mensagem.status, m.status)
            lista[i].envio = nil
            lista.removeAll { $0.envio == .enviando(ref: ref) }
        } else if let i = lista.firstIndex(where: { $0.envio == .enviando(ref: ref) }) {
            lista[i] = WABolha(mensagem: m)
        } else if lista.contains(where: { $0.envio == .falhou(ref: ref) }) {
            // ponytail: a falha já foi mostrada; só `retentar` mexe nessa bolha
            return
        } else {
            lista.append(WABolha(mensagem: m))
        }
        bolhasPorChave[chave] = Self.ordenadas(lista)
    }

    /// Envio recusado: a bolha local fica no lugar, sem status, até `retentar`.
    mutating func falharEnvio(ref: String, chave: WAChave) {
        guard var lista = bolhasPorChave[chave],
              let i = lista.firstIndex(where: { $0.envio == .enviando(ref: ref) }) else { return }
        lista[i].envio = .falhou(ref: ref)
        lista[i].mensagem.status = nil
        bolhasPorChave[chave] = lista
    }

    /// Volta a bolha que falhou a `.enviando` com um `ref` novo, no mesmo lugar.
    mutating func retentar(idLocal: String, novoRef: String, chave: WAChave) {
        guard var lista = bolhasPorChave[chave],
              let i = lista.firstIndex(where: { $0.id == idLocal }),
              case let .falhou(velho)? = lista[i].envio else { return }
        refsAbandonados.insert(velho)
        lista[i].envio = .enviando(ref: novoRef)
        bolhasPorChave[chave] = lista
    }

    func estadoDaBolha(_ b: WABolha) -> WAEstadoDaBolha {
        switch b.envio {
        case .enviando?: return .enviando
        case .falhou?: return .falhou
        case nil: break
        }
        guard b.mensagem.deMim else { return .recebida }
        switch b.mensagem.status ?? .enviada {
        case .enviada: return .enviada
        case .entregue: return .entregue
        case .lida: return .lida
        }
    }
}
