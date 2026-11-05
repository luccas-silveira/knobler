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
    /// Só conversas carregadas (`inserirMensagens` chamado), em `ts` crescente
    /// com desempate por `id`. A chave usa o jid canônico.
    private(set) var bolhasPorChave: [WAChave: [WABolha]] = [:]
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

    /// Página de `GET /v1/mensagens`. `maisVelhas: false` troca as bolhas pela
    /// página mais recente; `true` junta a página antiga sem repetir `id`.
    mutating func inserirMensagens(_ mensagens: [WAMensagem], em chave: WAChave,
                                   antes cursor: String?, maisVelhas: Bool) {
        var lista = maisVelhas ? bolhas(de: chave) : []
        let conhecidos = Set(lista.map(\.id))
        var novos = Set<String>()
        for m in mensagens where !conhecidos.contains(m.id) && novos.insert(m.id).inserted {
            lista.append(WABolha(mensagem: m))
        }
        bolhasPorChave[chave] = Self.ordenadas(lista)
        antes[chave] = cursor
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
        case let .mensagem(m, cv, _):
            return aplicarMensagem(m, cv, conta: conta)

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

    private mutating func aplicarMensagem(_ m: WAMensagem, _ cv: WAConversa, conta: String) -> WAEfeito {
        let marca = "\(conta)|\(cv.jid)|\(m.id)"
        guard !vistos.contains(marca) else { return .nada }
        vistos.insert(marca)
        filaDeVistos.append(marca)
        if filaDeVistos.count > Self.limiteDeVistos {
            vistos.remove(filaDeVistos.removeFirst())
        }

        atualizarConversa(conta: conta, cv)

        // bolha só em conversa carregada; a não carregada lê a página ao abrir
        let k = WAChave(conta: conta, jid: cv.jid)
        if var lista = bolhasPorChave[k] {
            if let i = lista.firstIndex(where: { $0.id == m.id }) {
                lista[i].mensagem = m
                lista[i].envio = nil
            } else {
                lista.append(WABolha(mensagem: m))
            }
            bolhasPorChave[k] = Self.ordenadas(lista)
        }
        return .mensagemNova(m, cv)
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
        antes = [:]
        vistos = []
        filaDeVistos = []
        apelidos = [:]
    }
}
