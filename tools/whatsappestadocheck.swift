// Gate da etapa 6 do WhatsApp: estado puro (Knobler/WhatsApp/WhatsAppEstado.swift).
// Contrato: docs/whatsapp-ponte.md (ordem das conversas em :465, das mensagens
// em :488-490, efeito de cada evento em :840-939, `status` só anda pra frente
// em :869, evento `conta` a cada mudança de `nao_lidas` agregado em :941-945).
//
//   xcrun swiftc -parse-as-library -swift-version 5 \
//     Knobler/WhatsApp/WhatsAppModelos.swift Knobler/WhatsApp/WhatsAppEstado.swift \
//     tools/whatsappestadocheck.swift \
//     -o /tmp/whatsappestadocheck && /tmp/whatsappestadocheck
//
// Tudo em memória: nenhuma rede, nenhum arquivo, nenhum UserDefaults.

import Foundation

private func exigir(_ cond: Bool, _ msg: String, linha: UInt = #line) {
    if !cond {
        print("FALHOU: \(msg) (tools/whatsappestadocheck.swift:\(linha))")
        exit(1)
    }
}

// MARK: - fábricas

private let C = "8292"
private let OUTRA = "4143"
private let X = "554799990001@s.whatsapp.net"
private let Y = "554799990002@s.whatsapp.net"
private let Z = "554799990003@s.whatsapp.net"
private let CANON = "554799990000@s.whatsapp.net"
private let LID = "157100000000@lid"

private func chave(_ jid: String, _ conta: String = C) -> WAChave { WAChave(conta: conta, jid: jid) }

private func mensagem(id: String, ts: Int, deMim: Bool = false, conversa: String = X,
                      texto: String = "oi", midia: WAMidia? = nil,
                      status: WAStatus? = nil) -> WAMensagem {
    WAMensagem(id: id, conversa: conversa,
               remetente: deMim ? "eu@s.whatsapp.net" : conversa,
               remetenteNome: nil, deMim: deMim, ts: ts, tipo: midia == nil ? .texto : .imagem,
               texto: texto, midia: midia, citacao: nil, reacoes: [],
               editada: nil, apagada: nil, status: status ?? (deMim ? .enviada : nil))
}

private func conversa(jid: String, ts: Int, jids: [String]? = nil,
                      naoLidas: Int = 0, marcada: Bool = false) -> WAConversa {
    WAConversa(jid: jid, jids: jids ?? [jid], tipo: .individual, nome: "Nome \(jid.prefix(12))",
               naoLidas: naoLidas, marcadaNaoLida: marcada, ts: ts, ultima: nil)
}

private func conta(_ numero: String, padrao: Bool = false, conversasNaoLidas: Int = 0,
                   nome: String? = nil) -> WAConta {
    WAConta(conta: numero, jid: "55479999\(numero)@s.whatsapp.net", nome: nome, padrao: padrao,
            estado: .conectada, motivo: nil, desde: 1_762_000_000,
            naoLidas: conversasNaoLidas * 2, conversasNaoLidas: conversasNaoLidas)
}

private let foto = WAMidia(mimetype: "image/jpeg", nome: "foto.jpg", tamanho: 1234,
                           segundos: nil, miniatura: true, baixada: false)

private func jids(_ cs: [WAConversa]) -> [String] { cs.map(\.jid) }
private func ids(_ bs: [WABolha]) -> [String] { bs.map(\.id) }
private func bolha(_ e: WAEstado, _ k: WAChave, _ id: String) -> WABolha? {
    e.bolhas(de: k).first { $0.id == id }
}

// MARK: - casos

/// Ordem das conversas: `ts` decrescente, desempate por `jid` crescente; contas não se misturam.
private func ordemDasConversas() {
    var e = WAEstado()
    // entrada fora de ordem, e o empate de ts chega com o jid maior primeiro
    e.substituirConversas(conta: C, [conversa(jid: Z, ts: 300), conversa(jid: X, ts: 100),
                                     conversa(jid: Y, ts: 300)])
    e.substituirConversas(conta: OUTRA, [conversa(jid: "outra@s.whatsapp.net", ts: 999)])

    exigir(jids(e.conversas(da: C)) == [Y, Z, X],
           "conversas por ts decrescente e jid crescente no empate; veio \(jids(e.conversas(da: C)))")
    exigir(jids(e.conversas(da: OUTRA)) == ["outra@s.whatsapp.net"],
           "a lista de outra conta não mistura com a da conta \(C)")
    exigir(e.conversas(da: "0000").isEmpty, "conta sem lista devolve vazio")

    // substituir de novo troca a lista inteira, não acumula
    e.substituirConversas(conta: C, [conversa(jid: X, ts: 50)])
    exigir(jids(e.conversas(da: C)) == [X], "substituirConversas troca a lista inteira")
}

/// Evento `mensagem`: conversa sobe, `naoLidas` do evento, efeito, dedupe por id.
private func mensagemNova() {
    var e = WAEstado()
    e.substituirConversas(conta: C, [conversa(jid: Y, ts: 200), conversa(jid: X, ts: 100)])
    e.inserirMensagens([], em: chave(X), antes: nil, maisVelhas: false)

    let m = mensagem(id: "M1", ts: 300)
    let cv = conversa(jid: X, ts: 300, naoLidas: 4)
    let ev = WAEventoNumerado.mensagem(m, cv, ref: nil)

    let efeito = e.aplicar(ev, conta: C)
    exigir(efeito == .mensagemNova(m, cv), "mensagem recebida devolve .mensagemNova; veio \(efeito)")
    exigir(jids(e.conversas(da: C)) == [X, Y], "a conversa da mensagem sobe pro topo; veio \(jids(e.conversas(da: C)))")
    exigir(e.conversas(da: C).first?.naoLidas == 4, "a conversa fica com o naoLidas que veio no evento")
    exigir(ids(e.bolhas(de: chave(X))) == ["M1"], "a mensagem vira bolha na conversa carregada")

    // a mesma entrega de novo (reconexão com desde N)
    let repetido = e.aplicar(ev, conta: C)
    exigir(repetido == .nada, "mesmo id aplicado de novo devolve .nada; veio \(repetido)")
    exigir(ids(e.bolhas(de: chave(X))) == ["M1"], "mesmo id não duplica bolha")
    exigir(e.conversas(da: C).count == 2, "mesmo id não duplica conversa")

    // conversa que não estava na lista entra nela
    let mz = mensagem(id: "MZ", ts: 400, conversa: Z)
    let cz = conversa(jid: Z, ts: 400, naoLidas: 1)
    let efeitoZ = e.aplicar(.mensagem(mz, cz, ref: nil), conta: C)
    exigir(efeitoZ == .mensagemNova(mz, cz), "mensagem de conversa nova também é .mensagemNova")
    exigir(jids(e.conversas(da: C)) == [Z, X, Y], "conversa nova entra na lista, no topo; veio \(jids(e.conversas(da: C)))")
    exigir(e.conversas(da: C).first?.naoLidas == 1, "conversa nova entra com o naoLidas do evento")

    // o mesmo id em outra conta (grupo com as duas contas) não é repetição
    let outra = e.aplicar(.mensagem(m, cv, ref: nil), conta: OUTRA)
    exigir(outra == .mensagemNova(m, cv), "mesmo id em outra conta não é deduplicado; veio \(outra)")
    exigir(jids(e.conversas(da: OUTRA)) == [X], "a mensagem da outra conta vai pra lista dela")
    exigir(jids(e.conversas(da: C)) == [Z, X, Y], "a mensagem da outra conta não mexe na lista desta")
}

/// Bolhas só pra conversa carregada; dedupe vale mesmo sem bolhas.
private func soConversaCarregada() {
    var e = WAEstado()
    e.substituirConversas(conta: C, [conversa(jid: X, ts: 100)])
    exigir(!e.carregada(chave(X)), "conversa sem inserirMensagens não está carregada")

    let m = mensagem(id: "S1", ts: 200)
    let ev = WAEventoNumerado.mensagem(m, conversa(jid: X, ts: 200, naoLidas: 1), ref: nil)
    let primeiro = e.aplicar(ev, conta: C)
    exigir(primeiro == .mensagemNova(m, conversa(jid: X, ts: 200, naoLidas: 1)),
           "conversa não carregada também avisa mensagem nova")
    exigir(e.bolhas(de: chave(X)).isEmpty, "conversa não carregada não acumula bolhas")
    exigir(!e.carregada(chave(X)), "evento de mensagem não marca a conversa como carregada")
    exigir(e.aplicar(ev, conta: C) == .nada, "segunda entrega do mesmo id sem bolhas continua .nada")

    // ao carregar, só a página da ponte aparece (nada vazou antes)
    e.inserirMensagens([mensagem(id: "P1", ts: 150)], em: chave(X), antes: nil, maisVelhas: false)
    exigir(e.carregada(chave(X)), "inserirMensagens marca a conversa como carregada")
    exigir(ids(e.bolhas(de: chave(X))) == ["P1"], "a conversa carregada só tem a página; veio \(ids(e.bolhas(de: chave(X))))")
}

/// Ordem das bolhas, página antiga, cursor.
private func ordemDasBolhas() {
    var e = WAEstado()
    let k = chave(X)
    e.substituirConversas(conta: C, [conversa(jid: X, ts: 100)])
    e.inserirMensagens([mensagem(id: "b", ts: 20), mensagem(id: "a", ts: 20), mensagem(id: "c", ts: 10)],
                       em: k, antes: "cur1", maisVelhas: false)
    exigir(ids(e.bolhas(de: k)) == ["c", "a", "b"],
           "bolhas por ts crescente e id no empate; veio \(ids(e.bolhas(de: k)))")
    exigir(e.antes[k] == "cur1", "o cursor antes da página é guardado")

    // página mais velha: vai antes, sem repetir o "c" que já estava
    e.inserirMensagens([mensagem(id: "c", ts: 10), mensagem(id: "z", ts: 5), mensagem(id: "y", ts: 5)],
                       em: k, antes: nil, maisVelhas: true)
    exigir(ids(e.bolhas(de: k)) == ["y", "z", "c", "a", "b"],
           "página antiga entra antes, ordenada e sem repetir id; veio \(ids(e.bolhas(de: k)))")
    exigir(e.antes[k] == nil, "cursor nil = chegou ao começo")

    // mensagem ao vivo com ts no meio cai no lugar dela, não no fim
    e.aplicar(.mensagem(mensagem(id: "m", ts: 15), conversa(jid: X, ts: 15), ref: nil), conta: C)
    exigir(ids(e.bolhas(de: k)) == ["y", "z", "c", "m", "a", "b"],
           "bolha ao vivo respeita a ordem por ts; veio \(ids(e.bolhas(de: k)))")
}

/// Estado com a conversa canônica que tem um LID como apelido, já carregada.
private func estadoComApelido() -> WAEstado {
    var e = WAEstado()
    e.substituirConversas(conta: C, [conversa(jid: CANON, ts: 100, jids: [CANON, LID], naoLidas: 3),
                                     conversa(jid: Y, ts: 50)])
    e.inserirMensagens([mensagem(id: "EU1", ts: 10, deMim: true, conversa: CANON),
                        mensagem(id: "EU2", ts: 11, deMim: true, conversa: CANON),
                        mensagem(id: "ELE", ts: 12, conversa: CANON, midia: foto)],
                       em: chave(CANON), antes: nil, maisVelhas: false)
    return e
}

/// Apelido: evento pelo LID cai na conversa canônica.
private func apelidos() {
    var e = estadoComApelido()
    exigir(e.canonico(conta: C, jid: LID) == CANON, "o LID resolve pro jid canônico")
    exigir(e.canonico(conta: C, jid: CANON) == CANON, "o canônico resolve pra ele mesmo")
    exigir(e.canonico(conta: C, jid: "999@lid") == "999@lid", "jid desconhecido volta como veio")
    exigir(e.canonico(conta: OUTRA, jid: LID) == LID, "o apelido de uma conta não vale na outra")

    e.aplicar(.recibo(conversa: LID, ids: ["EU1"], recibo: .entregue, de: LID, ts: 20), conta: C)
    exigir(bolha(e, chave(CANON), "EU1")?.mensagem.status == .entregue,
           "recibo pelo LID avança a bolha da conversa canônica")

    e.aplicar(.reacao(conversa: LID, alvo: "ELE", remetente: LID, deMim: false, emoji: "👍", ts: 21), conta: C)
    exigir(bolha(e, chave(CANON), "ELE")?.mensagem.reacoes.map(\.emoji) == ["👍"],
           "reação pelo LID cai na bolha da conversa canônica")

    e.aplicar(.leitura(conversa: LID, naoLidas: 0, marcadaNaoLida: false), conta: C)
    let canon = e.conversas(da: C).first { $0.jid == CANON }
    exigir(canon?.naoLidas == 0, "leitura pelo LID zera as não lidas da conversa canônica")

    exigir(jids(e.conversas(da: C)) == [CANON, Y], "evento pelo LID não cria conversa nova")
    exigir(e.bolhas(de: chave(LID)).isEmpty, "nenhuma bolha fica guardada sob o LID")

    // a conversa que chega por evento também refaz o índice de apelidos
    let LID2 = "157100000009@lid"
    e.atualizarConversa(conta: C, conversa(jid: Y, ts: 50, jids: [Y, LID2]))
    exigir(e.canonico(conta: C, jid: LID2) == Y, "atualizarConversa refaz o índice de apelidos")
}

/// Recibos: status só anda pra frente; lidaPorMim não mexe em bolha.
private func recibos() {
    var e = estadoComApelido()
    let k = chave(CANON)

    e.aplicar(.recibo(conversa: CANON, ids: ["EU1", "EU2"], recibo: .entregue, de: CANON, ts: 20), conta: C)
    exigir(bolha(e, k, "EU1")?.mensagem.status == .entregue, "entregue: enviada → entregue")
    exigir(bolha(e, k, "EU2")?.mensagem.status == .entregue, "o recibo vale pra todos os ids dele")

    e.aplicar(.recibo(conversa: CANON, ids: ["EU1"], recibo: .lida, de: CANON, ts: 21), conta: C)
    exigir(bolha(e, k, "EU1")?.mensagem.status == .lida, "lida: entregue → lida")

    e.aplicar(.recibo(conversa: CANON, ids: ["EU1"], recibo: .entregue, de: CANON, ts: 22), conta: C)
    exigir(bolha(e, k, "EU1")?.mensagem.status == .lida, "entregue depois de lida não volta")

    var f = estadoComApelido()
    let antes = f.bolhas(de: k)
    f.aplicar(.recibo(conversa: CANON, ids: ["EU1", "ELE"], recibo: .lidaPorMim, de: "eu@s.whatsapp.net", ts: 23), conta: C)
    exigir(f.bolhas(de: k) == antes, "lidaPorMim não mexe em bolha")

    f.aplicar(.recibo(conversa: CANON, ids: ["NAOEXISTE"], recibo: .lida, de: CANON, ts: 24), conta: C)
    exigir(f.bolhas(de: k) == antes, "recibo de id desconhecido é ignorado")
    exigir(ids(f.bolhas(de: k)) == ["EU1", "EU2", "ELE"], "recibo de id desconhecido não cria bolha")
}

/// Reações: acrescenta, troca, remove, ignora alvo desconhecido.
private func reacoes() {
    var e = estadoComApelido()
    let k = chave(CANON)
    func emojis() -> [String: String] {
        var r: [String: String] = [:]
        for x in bolha(e, k, "ELE")?.mensagem.reacoes ?? [] { r[x.remetente] = x.emoji }
        return r
    }
    func total() -> Int { bolha(e, k, "ELE")?.mensagem.reacoes.count ?? -1 }

    e.aplicar(.reacao(conversa: CANON, alvo: "ELE", remetente: "A", deMim: false, emoji: "👍", ts: 30), conta: C)
    exigir(emojis() == ["A": "👍"] && total() == 1, "reação nova é acrescentada")

    e.aplicar(.reacao(conversa: CANON, alvo: "ELE", remetente: "B", deMim: true, emoji: "❤️", ts: 31), conta: C)
    exigir(emojis() == ["A": "👍", "B": "❤️"] && total() == 2, "reação de outra pessoa soma")

    e.aplicar(.reacao(conversa: CANON, alvo: "ELE", remetente: "A", deMim: false, emoji: "😂", ts: 32), conta: C)
    exigir(emojis() == ["A": "😂", "B": "❤️"] && total() == 2,
           "a mesma pessoa com outro emoji troca, não soma; veio \(emojis()) (\(total()))")

    e.aplicar(.reacao(conversa: CANON, alvo: "ELE", remetente: "A", deMim: false, emoji: "", ts: 33), conta: C)
    exigir(emojis() == ["B": "❤️"] && total() == 1, "emoji vazio remove a reação da pessoa")

    let antes = e.bolhas(de: k)
    e.aplicar(.reacao(conversa: CANON, alvo: "NAOEXISTE", remetente: "A", deMim: false, emoji: "👍", ts: 34), conta: C)
    exigir(e.bolhas(de: k) == antes, "reação com alvo desconhecido é ignorada")
}

/// Edição, apagamento, leitura, mídia e sincronização.
private func outrosEventos() {
    var e = estadoComApelido()
    let k = chave(CANON)

    e.aplicar(.edicao(conversa: CANON, alvo: "EU2", texto: "texto novo", ts: 40), conta: C)
    exigir(bolha(e, k, "EU2")?.mensagem.texto == "texto novo", "edição troca o texto")
    exigir(bolha(e, k, "EU2")?.mensagem.editada != nil, "edição preenche editada")
    var antes = e.bolhas(de: k)
    e.aplicar(.edicao(conversa: CANON, alvo: "NAOEXISTE", texto: "x", ts: 41), conta: C)
    exigir(e.bolhas(de: k) == antes, "edição com alvo desconhecido é ignorada")

    e.aplicar(.apagamento(conversa: CANON, alvo: "ELE", por: CANON, ts: 42), conta: C)
    let apagada = bolha(e, k, "ELE")?.mensagem
    exigir(apagada?.texto == "", "apagamento zera o texto")
    exigir(apagada?.midia == nil, "apagamento tira a mídia")
    exigir(apagada?.apagada != nil, "apagamento preenche apagada")
    exigir(ids(e.bolhas(de: k)) == ["EU1", "EU2", "ELE"], "a bolha apagada continua no lugar")

    e.aplicar(.leitura(conversa: CANON, naoLidas: 7, marcadaNaoLida: true), conta: C)
    var cv = e.conversas(da: C).first { $0.jid == CANON }
    exigir(cv?.naoLidas == 7 && cv?.marcadaNaoLida == true, "leitura muda naoLidas e marcadaNaoLida")
    e.aplicar(.leitura(conversa: CANON, naoLidas: 0, marcadaNaoLida: false), conta: C)
    cv = e.conversas(da: C).first { $0.jid == CANON }
    exigir(cv?.naoLidas == 0 && cv?.marcadaNaoLida == false, "leitura desmarca também")

    var g = estadoComApelido()
    exigir(bolha(g, k, "ELE")?.midiaIndisponivel == false, "bolha nasce com a mídia disponível")
    g.aplicar(.midia(conversa: CANON, alvo: "ELE", ok: false), conta: C)
    exigir(bolha(g, k, "ELE")?.midiaIndisponivel == true, "midia ok:false marca midiaIndisponivel")
    g.aplicar(.midia(conversa: CANON, alvo: "ELE", ok: true), conta: C)
    exigir(bolha(g, k, "ELE")?.midiaIndisponivel == false, "midia ok:true desmarca midiaIndisponivel")

    antes = g.bolhas(de: k)
    let estadoAntes = g
    let efeito = g.aplicar(.sincronizacao(conversas: 37), conta: C)
    exigir(efeito == .atualizou, "sincronizacao devolve .atualizou; veio \(efeito)")
    exigir(g == estadoAntes, "sincronizacao não muda nada no estado")
}

/// Contas: ordem, troca pelo número e o sinal da faixa.
private func contasESinal() {
    var e = WAEstado()
    e.substituirContas([conta("5555", conversasNaoLidas: 1), conta(OUTRA, conversasNaoLidas: 2),
                        conta(C, padrao: true, conversasNaoLidas: 7)])
    exigir(e.contas.map(\.conta) == [C, OUTRA, "5555"],
           "padrão primeiro, depois por número; veio \(e.contas.map(\.conta))")
    exigir(e.sinalDaFaixa == 10, "sinalDaFaixa soma conversasNaoLidas das contas; veio \(e.sinalDaFaixa)")

    // a lista carregada é só uma página: não serve pra somar
    e.substituirConversas(conta: C, [conversa(jid: X, ts: 100, naoLidas: 3)])
    exigir(e.sinalDaFaixa == 10, "sinalDaFaixa não sai das conversas carregadas; veio \(e.sinalDaFaixa)")
    e.aplicar(.leitura(conversa: X, naoLidas: 0, marcadaNaoLida: false), conta: C)
    exigir(e.conversas(da: C).first?.naoLidas == 0, "leitura muda a conversa")
    exigir(e.sinalDaFaixa == 10, "leitura sozinha não muda o sinalDaFaixa; veio \(e.sinalDaFaixa)")

    e.aplicar(conta: conta(C, padrao: true, conversasNaoLidas: 6, nome: "Zoi"))
    exigir(e.contas.count == 3, "aplicar(conta:) troca, não acrescenta")
    exigir(e.contas.map(\.conta) == [C, OUTRA, "5555"], "aplicar(conta:) mantém a ordem")
    exigir(e.contas.first?.nome == "Zoi", "aplicar(conta:) troca a conta pelo número")
    exigir(e.sinalDaFaixa == 9, "o evento conta com conversasNaoLidas novo muda o sinal; veio \(e.sinalDaFaixa)")

    e.aplicar(conta: conta(OUTRA, conversasNaoLidas: 0))
    exigir(e.contas.map(\.conta) == [C, OUTRA, "5555"], "aplicar(conta:) de outra conta mantém a ordem")
    exigir(e.sinalDaFaixa == 7, "sinalDaFaixa acompanha cada conta; veio \(e.sinalDaFaixa)")

    var vazio = WAEstado()
    exigir(vazio.sinalDaFaixa == 0, "sem contas o sinal é 0")
    vazio.substituirContas([])
    exigir(vazio.contas.isEmpty, "substituirContas([]) esvazia")
}

/// Rascunho por conversa e por conta.
private func rascunhos() {
    var e = WAEstado()
    let k = chave(X)
    e.definirRascunho("oi", para: k)
    exigir(e.rascunho(de: k) == "oi", "o rascunho volta como foi escrito")
    exigir(e.rascunho(de: chave(Y)) == "", "rascunho de outra conversa não se mistura")
    exigir(e.rascunho(de: chave(X, OUTRA)) == "", "mesmo jid em outra conta não se mistura")

    e.definirRascunho("tchau", para: chave(X, OUTRA))
    exigir(e.rascunho(de: k) == "oi" && e.rascunho(de: chave(X, OUTRA)) == "tchau",
           "cada conta guarda o próprio rascunho do mesmo jid")

    e.definirRascunho("", para: k)
    exigir(e.rascunho(de: k) == "", "rascunho vazio apaga")
    exigir(e.rascunhos[k] == nil, "rascunho vazio não fica guardado")
    exigir(e.rascunho(de: chave(X, OUTRA)) == "tchau", "apagar um rascunho não mexe no outro")
}

/// esvaziarConversas: some com conversas, bolhas, cursores e dedupe; fica contas e rascunhos.
private func esvaziar() {
    var e = WAEstado()
    let k = chave(X)
    let contas = [conta(C, padrao: true, conversasNaoLidas: 2), conta(OUTRA)]
    e.substituirContas(contas)
    e.substituirConversas(conta: C, [conversa(jid: X, ts: 100)])
    e.inserirMensagens([mensagem(id: "V1", ts: 10)], em: k, antes: "cur", maisVelhas: false)
    let m = mensagem(id: "V2", ts: 200)
    let ev = WAEventoNumerado.mensagem(m, conversa(jid: X, ts: 200, naoLidas: 1), ref: nil)
    exigir(e.aplicar(ev, conta: C) != .nada, "preparo: a primeira entrega é nova")
    e.definirRascunho("guardado", para: k)

    e.esvaziarConversas()
    exigir(e.conversas(da: C).isEmpty, "esvaziar apaga as conversas")
    exigir(e.bolhas(de: k).isEmpty, "esvaziar apaga as bolhas")
    exigir(!e.carregada(k), "esvaziar desmarca a conversa carregada")
    exigir(e.antes.isEmpty, "esvaziar apaga os cursores")
    exigir(e.contas.map(\.conta) == [C, OUTRA] && e.sinalDaFaixa == 2, "esvaziar mantém as contas")
    exigir(e.rascunho(de: k) == "guardado", "esvaziar mantém os rascunhos")

    let deNovo = e.aplicar(ev, conta: C)
    exigir(deNovo == .mensagemNova(m, conversa(jid: X, ts: 200, naoLidas: 1)),
           "esvaziar zera o conjunto de deduplicação; veio \(deNovo)")
}

@main
enum Gate {
    static func main() {
        ordemDasConversas()
        mensagemNova()
        soConversaCarregada()
        ordemDasBolhas()
        apelidos()
        recibos()
        reacoes()
        outrosEventos()
        contasESinal()
        rascunhos()
        esvaziar()
        print("ok")
    }
}
