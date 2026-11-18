//
//  tools/asktecladocheck.swift — self-check das teclas do card de pergunta.
//  NÃO faz parte do alvo.
//
//  xcrun swiftc -parse-as-library -swift-version 5 \
//    Knobler/AskModels.swift Knobler/AskFeature.swift Knobler/AskCard/AskTeclado.swift \
//    tools/asktecladocheck.swift -o /tmp/asktecladocheck && /tmp/asktecladocheck
//
//  Prova a função pura `AskTeclado.comando`: que tecla vira que comando, na
//  lista de opções e no campo de texto, sem janela e sem NSEvent. O estado é
//  sempre montado por ações reais do reducer, numa rodada de três perguntas
//  (simples de 3 opções, múltipla de 4, simples de 3).
//  Os códigos de tecla estão escritos por extenso de propósito: se uma
//  constante do AskTeclado.swift mudar, o esperado daqui não muda junto.
//

import Foundation

@main
enum AskTecladoCheck {
    static func main() {
        testSetasVerticaisMovemODestaque()
        testNumeroEscolheAOpcao()
        testNumeroSaiDoCaractereNuncaDoCodigo()
        testEnterEmPerguntaSimples()
        testEnterEmMultipla()
        testEspacoMarcaSoEmMultipla()
        testSetasHorizontaisTrocamDePergunta()
        testTabEscECancelarNaLista()
        testCampoDeTexto()
        testModificadoresNaoViramNada()
        testSemPerguntaAtivaNadaViraNada()
        testRodadaInteiraSoPeloTeclado()

        print("asktecladocheck: OK")
    }

    // MARK: - Teclas (códigos virtuais do macOS e o que o NSEvent entrega em
    // `charactersIgnoringModifiers`)

    private static func tecla(_ codigo: Int, _ caracteres: String, shift: Bool = false, command: Bool = false,
                              outros: Bool = false, repeticao: Bool = false) -> AskTecla {
        AskTecla(codigo: codigo, caracteres: caracteres, shift: shift, command: command,
                 outros: outros, repeticao: repeticao)
    }

    private static let esc = tecla(53, "\u{1B}")
    private static let retorno = tecla(36, "\r")
    private static let enterNumerico = tecla(76, "\u{03}")
    private static let tab = tecla(48, "\t")
    /// ⇧Tab: o mesmo código do Tab; o caractere vira o "backtab".
    private static let shiftTab = tecla(48, "\u{19}", shift: true)
    private static let esquerda = tecla(123, "\u{F702}")
    private static let direita = tecla(124, "\u{F703}")
    private static let baixo = tecla(125, "\u{F701}")
    private static let cima = tecla(126, "\u{F700}")
    private static let espaco = tecla(49, " ")
    private static let ponto = tecla(47, ".")
    private static let comandoPonto = tecla(47, ".", command: true)
    private static let letra = tecla(0, "a")

    /// Fileira de números do teclado ANSI: "1" é 18, "2" é 19, "3" é 20…
    private static let codigoDaFileira: [Int: Int] = [0: 29, 1: 18, 2: 19, 3: 20, 4: 21, 5: 23, 6: 22, 7: 26, 8: 28, 9: 25]
    /// Teclado numérico: o mesmo caractere, outro código ("2" é 84).
    private static let codigoDoNumerico: [Int: Int] = [0: 82, 1: 83, 2: 84, 3: 85, 4: 86, 5: 87, 6: 88, 7: 89, 8: 91, 9: 92]

    private static func numero(_ n: Int, repeticao: Bool = false) -> AskTecla {
        tecla(codigoDaFileira[n]!, String(n), repeticao: repeticao)
    }

    private static func numerico(_ n: Int, repeticao: Bool = false) -> AskTecla {
        tecla(codigoDoNumerico[n]!, String(n), repeticao: repeticao)
    }

    private static func com(_ t: AskTecla, shift: Bool? = nil, command: Bool? = nil, outros: Bool? = nil,
                            repeticao: Bool? = nil) -> AskTecla {
        var nova = t
        if let shift { nova.shift = shift }
        if let command { nova.command = command }
        if let outros { nova.outros = outros }
        if let repeticao { nova.repeticao = repeticao }
        return nova
    }

    // MARK: - Helpers

    private static func check(_ condition: @autoclosure () -> Bool, _ message: String) {
        precondition(condition(), message)
    }

    /// Tecla com o teclado na lista de opções.
    private static func naLista(_ t: AskTecla, _ estado: AskState) -> AskComando? {
        AskTeclado.comando(t, campo: false, estado: estado)
    }

    /// Tecla com o cursor no campo de texto.
    private static func noCampo(_ t: AskTecla, _ estado: AskState) -> AskComando? {
        AskTeclado.comando(t, campo: true, estado: estado)
    }

    private static func opcoes(_ rotulos: String...) -> [AskOption] {
        rotulos.map { AskOption(label: $0, description: "", preview: nil) }
    }

    private static let simples1 = AskQuestion(question: "Primeira", header: "Um", multiSelect: false,
                                              options: opcoes("A", "B", "C"))
    private static let multipla = AskQuestion(question: "Segunda", header: "Dois", multiSelect: true,
                                              options: opcoes("A", "B", "C", "D"))
    private static let simples2 = AskQuestion(question: "Terceira", header: "Três", multiSelect: false,
                                              options: opcoes("X", "Y", "Z"))

    /// Estado depois de publicar `perguntas` e aplicar `acoes`, tudo pelo reducer.
    private static func estado(_ perguntas: [AskQuestion], _ acoes: [AskAction] = []) -> AskState {
        var state = AskState()
        let pedido = AskRequest(id: "rodada", questions: perguntas,
                                receivedAt: Date(timeIntervalSince1970: 1_000), source: nil)
        _ = AskReducer.reduce(state: &state, action: .enqueue(pedido))
        for acao in acoes { _ = AskReducer.reduce(state: &state, action: acao) }
        return state
    }

    /// Rodada de três perguntas, na página 0, sem destaque.
    private static func rodada(_ acoes: AskAction...) -> AskState {
        estado([simples1, multipla, simples2], acoes)
    }

    /// Uma pergunta simples só.
    private static func unica(_ acoes: AskAction...) -> AskState {
        estado([simples1], acoes)
    }

    /// Uma pergunta múltipla só.
    private static func unicaMultipla(_ acoes: AskAction...) -> AskState {
        estado([multipla], acoes)
    }

    // MARK: - ↑ ↓

    private static func testSetasVerticaisMovemODestaque() {
        let simples = rodada()
        check(naLista(baixo, simples) == .acao(.moveHighlight(by: 1)), "↓ desce o destaque")
        check(naLista(cima, simples) == .acao(.moveHighlight(by: -1)), "↑ sobe o destaque")
        check(naLista(com(baixo, repeticao: true), simples) == .acao(.moveHighlight(by: 1)),
              "↓ segurada continua descendo (repetição de tecla vale para as setas)")
        check(naLista(com(cima, repeticao: true), simples) == .acao(.moveHighlight(by: -1)),
              "↑ segurada continua subindo")

        // O comando é o passo; quem prende nas pontas é o reducer.
        let noFim = rodada(.setHighlight(2))
        check(noFim.highlight == 2, "preparo: destaque na última opção")
        check(naLista(baixo, noFim) == .acao(.moveHighlight(by: 1)), "↓ na última opção ainda é o passo +1")

        let emMultipla = rodada(.goTo(page: 1))
        check(emMultipla.page == 1, "preparo: pergunta múltipla em tela")
        check(naLista(baixo, emMultipla) == .acao(.moveHighlight(by: 1)), "↓ em múltipla desce o destaque")
        check(naLista(cima, emMultipla) == .acao(.moveHighlight(by: -1)), "↑ em múltipla sobe o destaque")
    }

    // MARK: - Números

    private static func testNumeroEscolheAOpcao() {
        let simples = rodada()
        check(naLista(numero(1), simples) == .acao(.choose(index: 0)), "\"1\" escolhe a primeira opção")
        check(naLista(numero(2), simples) == .acao(.choose(index: 1)), "\"2\" escolhe a segunda opção")
        check(naLista(numero(3), simples) == .acao(.choose(index: 2)), "\"3\" escolhe a terceira opção")
        check(naLista(numero(7), simples) == nil, "\"7\" com 3 opções não vira nada")
        check(naLista(numero(4), simples) == nil, "\"4\" com 3 opções não vira nada (uma além da última)")
        check(naLista(numero(0), simples) == nil, "\"0\" com 3 opções não vira nada")

        check(naLista(numero(2, repeticao: true), simples) == nil,
              "número com repetição de tecla não vira nada (segurar não responde a pergunta seguinte)")
        check(naLista(numero(1, repeticao: true), simples) == nil, "\"1\" segurado não vira nada")

        check(naLista(numerico(2), simples) == .acao(.choose(index: 1)),
              "\"2\" do teclado numérico (código 84) escolhe a segunda opção")
        check(naLista(numerico(7), simples) == nil, "\"7\" do teclado numérico com 3 opções não vira nada")
        check(naLista(numerico(2, repeticao: true), simples) == nil,
              "número do teclado numérico com repetição não vira nada")

        // O destaque não muda o que o número escolhe.
        check(naLista(numero(3), rodada(.setHighlight(0))) == .acao(.choose(index: 2)),
              "\"3\" escolhe a terceira mesmo com o destaque na primeira")

        // A contagem é a da pergunta em tela, não a da primeira da rodada.
        let emMultipla = rodada(.goTo(page: 1))
        check(naLista(numero(2), emMultipla) == .acao(.choose(index: 1)), "\"2\" em múltipla marca a segunda opção")
        check(naLista(numero(4), emMultipla) == .acao(.choose(index: 3)),
              "\"4\" na pergunta de 4 opções escolhe a quarta (conta as opções da página em tela)")
        check(naLista(numero(5), emMultipla) == nil, "\"5\" com 4 opções não vira nada")
    }

    private static func testNumeroSaiDoCaractereNuncaDoCodigo() {
        let simples = rodada()
        // AZERTY sem Shift: a tecla da posição do "2" (código 19) digita "é".
        check(naLista(tecla(19, "é"), simples) == nil,
              "código da tecla do \"2\" com o caractere \"é\" não vira nada (o número sai do caractere)")
        check(naLista(tecla(18, "&"), simples) == nil,
              "código da tecla do \"1\" com o caractere \"&\" não vira nada")
        // AZERTY com Shift: a mesma tecla digita "2", e o Shift vem ligado.
        check(naLista(tecla(19, "2", shift: true), simples) == .acao(.choose(index: 1)),
              "\"2\" digitado com Shift (AZERTY) escolhe a segunda opção")
        // ANSI com Shift: a tecla do "2" digita "@".
        check(naLista(tecla(19, "@", shift: true), simples) == nil, "Shift+2 no ANSI (\"@\") não vira nada")
        check(naLista(letra, simples) == nil, "letra solta na lista não vira nada")
        check(naLista(ponto, simples) == nil, "ponto sem ⌘ não vira nada")
    }

    // MARK: - Enter

    private static func testEnterEmPerguntaSimples() {
        let semDestaque = rodada()
        check(semDestaque.highlight == nil, "preparo: sem destaque")
        check(naLista(retorno, semDestaque) == .acao(.choose(index: 0)),
              "Enter em simples sem destaque escolhe a primeira")
        check(naLista(enterNumerico, semDestaque) == .acao(.choose(index: 0)),
              "Enter do teclado numérico em simples sem destaque escolhe a primeira")

        let naSegunda = rodada(.setHighlight(1))
        check(naSegunda.highlight == 1, "preparo: destaque na segunda opção")
        check(naLista(retorno, naSegunda) == .acao(.choose(index: 1)),
              "Enter em simples com destaque 1 escolhe a segunda")
        check(naLista(enterNumerico, naSegunda) == .acao(.choose(index: 1)),
              "Enter do teclado numérico com destaque 1 escolhe a segunda")
        check(naLista(retorno, rodada(.setHighlight(2))) == .acao(.choose(index: 2)),
              "Enter em simples com destaque 2 escolhe a terceira")

        check(naLista(com(retorno, repeticao: true), naSegunda) == nil,
              "Enter com repetição de tecla não vira nada (segurar não responde a pergunta seguinte)")
        check(naLista(com(enterNumerico, repeticao: true), naSegunda) == nil,
              "Enter do teclado numérico com repetição não vira nada")
        check(naLista(com(retorno, repeticao: true), semDestaque) == nil,
              "Enter com repetição e sem destaque não vira nada")

        // A terceira da rodada também é simples: o destaque lido é o do estado.
        let naTerceira = rodada(.goTo(page: 2), .setHighlight(2))
        check(naTerceira.page == 2 && naTerceira.highlight == 2, "preparo: terceira pergunta, destaque na última")
        check(naLista(retorno, naTerceira) == .acao(.choose(index: 2)),
              "Enter na terceira pergunta escolhe a opção em destaque")
    }

    private static func testEnterEmMultipla() {
        let vazia = rodada(.goTo(page: 1))
        check(vazia.page == 1 && vazia.selected.isEmpty, "preparo: múltipla em tela, nada marcado")
        check(naLista(retorno, vazia) == nil, "Enter em múltipla sem marcadas não vira nada")
        check(naLista(enterNumerico, vazia) == nil,
              "Enter do teclado numérico em múltipla sem marcadas não vira nada")
        // Enter confirma; quem marca é o espaço ou o número.
        check(naLista(retorno, rodada(.goTo(page: 1), .setHighlight(2))) == nil,
              "Enter em múltipla sem marcadas não marca a opção em destaque")

        // "C" e depois "A": a resposta sai na ordem das opções, não na dos cliques.
        let duas = rodada(.goTo(page: 1), .choose(index: 2), .choose(index: 0))
        check(duas.selected == ["A", "C"], "preparo: \"C\" e \"A\" marcadas")
        check(naLista(retorno, duas) == .acao(.submit(labels: ["A", "C"], text: nil)),
              "Enter em múltipla com \"C\" e \"A\" marcadas confirma [\"A\", \"C\"], na ordem das opções")
        check(naLista(enterNumerico, duas) == .acao(.submit(labels: ["A", "C"], text: nil)),
              "Enter do teclado numérico confirma as marcadas do mesmo jeito")
        check(naLista(com(retorno, repeticao: true), duas) == nil,
              "Enter com repetição em múltipla não confirma")

        let todas = rodada(.goTo(page: 1), .choose(index: 3), .choose(index: 1), .choose(index: 0), .choose(index: 2))
        check(todas.selected.count == 4, "preparo: as quatro marcadas")
        check(naLista(retorno, todas) == .acao(.submit(labels: ["A", "B", "C", "D"], text: nil)),
              "Enter com as quatro marcadas fora de ordem confirma na ordem das opções")

        let desmarcada = rodada(.goTo(page: 1), .choose(index: 2), .choose(index: 0), .choose(index: 2))
        check(desmarcada.selected == ["A"], "preparo: \"C\" marcada e desmarcada, sobra \"A\"")
        check(naLista(retorno, desmarcada) == .acao(.submit(labels: ["A"], text: nil)),
              "Enter confirma só o que continua marcado")
    }

    // MARK: - Espaço

    private static func testEspacoMarcaSoEmMultipla() {
        let semDestaque = rodada(.goTo(page: 1))
        check(semDestaque.highlight == nil, "preparo: múltipla sem destaque")
        check(naLista(espaco, semDestaque) == .acao(.choose(index: 0)),
              "espaço em múltipla sem destaque marca a primeira")
        let naTerceira = rodada(.goTo(page: 1), .setHighlight(2))
        check(naLista(espaco, naTerceira) == .acao(.choose(index: 2)),
              "espaço em múltipla marca a opção em destaque")
        // Marcar deixa o destaque onde estava: o segundo espaço desmarca a mesma.
        let jaMarcada = rodada(.goTo(page: 1), .choose(index: 3))
        check(jaMarcada.highlight == 3, "preparo: marcar pelo número leva o destaque junto")
        check(naLista(espaco, jaMarcada) == .acao(.choose(index: 3)),
              "espaço sobre uma opção marcada é o mesmo choose (o reducer desmarca)")

        check(naLista(espaco, rodada()) == nil, "espaço em simples sem destaque não vira nada")
        check(naLista(espaco, rodada(.setHighlight(1))) == nil, "espaço em simples com destaque não vira nada")
        check(naLista(espaco, unicaMultipla()) == .acao(.choose(index: 0)),
              "espaço numa múltipla sozinha marca a primeira")
    }

    // MARK: - ← →

    private static func testSetasHorizontaisTrocamDePergunta() {
        let primeira = rodada()
        check(naLista(direita, primeira) == .acao(.goTo(page: 1)), "→ na página 0 vai para a página 1")
        check(naLista(esquerda, primeira) == nil, "← na primeira pergunta não vira nada")

        let meio = rodada(.goTo(page: 1))
        check(naLista(direita, meio) == .acao(.goTo(page: 2)), "→ na página 1 vai para a página 2")
        check(naLista(esquerda, meio) == .acao(.goTo(page: 0)), "← na página 1 volta para a página 0")

        let ultima = rodada(.goTo(page: 2))
        check(ultima.page == 2, "preparo: última pergunta em tela")
        check(naLista(direita, ultima) == nil, "→ na última pergunta não vira nada")
        check(naLista(esquerda, ultima) == .acao(.goTo(page: 1)), "← na última volta para a página 1")

        // Chegar à página por resposta (e não por goTo) dá no mesmo.
        let respondida = rodada(.choose(index: 0))
        check(respondida.page == 1, "preparo: responder a primeira abre a segunda")
        check(naLista(esquerda, respondida) == .acao(.goTo(page: 0)), "← depois de responder volta à respondida")

        check(naLista(direita, unica()) == nil, "→ com uma pergunta só não vira nada")
        check(naLista(esquerda, unica()) == nil, "← com uma pergunta só não vira nada")
        check(naLista(direita, unicaMultipla()) == nil, "→ com uma múltipla só não vira nada")
        check(naLista(esquerda, unicaMultipla()) == nil, "← com uma múltipla só não vira nada")
    }

    // MARK: - Tab, Esc, ⌘.

    private static func testTabEscECancelarNaLista() {
        for (nome, state) in [("simples", rodada()), ("múltipla", rodada(.goTo(page: 1))),
                              ("uma pergunta só", unica()), ("com destaque", rodada(.setHighlight(1)))] {
            check(naLista(tab, state) == .focarCampo, "Tab na lista foca o campo (\(nome))")
            check(naLista(esc, state) == .soltarTeclado,
                  "Esc na lista solta o teclado, sem cancelar a pergunta (\(nome))")
            check(naLista(comandoPonto, state) == .cancelar, "⌘. na lista cancela a pergunta (\(nome))")
        }
        // Esc não é mais o ✕: nunca manda a pergunta para o terminal.
        check(naLista(esc, rodada()) != .cancelar, "Esc na lista não é cancelar")
        check(naLista(esc, rodada()) != .acao(.cancelActive), "Esc na lista não envia cancelActive")
        // Só o ponto com ⌘ cancela.
        check(naLista(tecla(43, ",", command: true), rodada()) == nil, "⌘, não vira nada")
        check(naLista(tecla(0, "a", command: true), rodada()) == nil, "⌘A não vira nada")
    }

    // MARK: - Campo de texto

    private static func testCampoDeTexto() {
        let estados: [(String, AskState)] = [
            ("simples", rodada()),
            ("simples com destaque", rodada(.setHighlight(1))),
            ("múltipla com marcadas", rodada(.goTo(page: 1), .choose(index: 2), .choose(index: 0))),
            ("uma pergunta só", unica()),
            ("com texto digitado", rodada(.setText("resposta"))),
        ]
        for (nome, state) in estados {
            check(noCampo(esc, state) == .voltarALista, "Esc no campo volta à lista (\(nome))")
            check(noCampo(shiftTab, state) == .voltarALista, "⇧Tab no campo volta à lista (\(nome))")
            check(noCampo(comandoPonto, state) == .cancelar, "⌘. no campo cancela a pergunta (\(nome))")

            // O resto é do campo: a tecla segue para o TextField.
            let doCampo: [(String, AskTecla)] = [
                ("letra", letra), ("\"2\"", numero(2)), ("\"2\" do teclado numérico", numerico(2)),
                ("\"7\"", numero(7)), ("Enter", retorno), ("Enter do teclado numérico", enterNumerico),
                ("↑", cima), ("↓", baixo), ("←", esquerda), ("→", direita),
                ("Tab", tab), ("espaço", espaco), ("ponto", ponto),
                ("letra com repetição", com(letra, repeticao: true)),
                ("Enter com repetição", com(retorno, repeticao: true)),
                ("letra maiúscula", tecla(0, "A", shift: true)),
            ]
            for (qual, t) in doCampo {
                check(noCampo(t, state) == nil, "\(qual) no campo não vira nada: o campo trata (\(nome))")
            }
        }
        // Esc no campo não solta o teclado nem cancela: só devolve o cursor à lista.
        check(noCampo(esc, rodada()) != .soltarTeclado, "Esc no campo não solta o teclado")
        check(noCampo(esc, rodada()) != .cancelar, "Esc no campo não cancela")
    }

    // MARK: - ⌘ ⌃ ⌥

    private static func testModificadoresNaoViramNada() {
        let simples = rodada(.setHighlight(1))
        let emMultipla = rodada(.goTo(page: 1), .choose(index: 0))
        check(emMultipla.page == 1 && emMultipla.selected == ["A"], "preparo: múltipla com \"A\" marcada")

        // Sem modificador, cada uma destas vira um comando (provado acima).
        let naSimples: [(String, AskTecla)] = [
            ("↓", baixo), ("↑", cima), ("→", direita), ("\"2\"", numero(2)),
            ("\"2\" do teclado numérico", numerico(2)), ("Enter", retorno),
            ("Enter do teclado numérico", enterNumerico), ("Tab", tab), ("Esc", esc),
        ]
        let naMultipla: [(String, AskTecla)] = [
            ("espaço", espaco), ("Enter", retorno), ("←", esquerda), ("→", direita), ("\"3\"", numero(3)),
        ]
        for (lista, state) in [(naSimples, simples), (naMultipla, emMultipla)] {
            for (qual, t) in lista {
                check(naLista(t, state) != nil, "preparo: \(qual) sem modificador vira comando")
                check(naLista(com(t, command: true), state) == nil, "⌘ + \(qual) não vira nada")
                check(naLista(com(t, outros: true), state) == nil, "⌃ ou ⌥ + \(qual) não vira nada")
                check(naLista(com(t, command: true, outros: true), state) == nil,
                      "⌘ com ⌃ ou ⌥ + \(qual) não vira nada")
            }
        }

        // No campo, as duas teclas que voltam à lista também perdem o efeito.
        check(noCampo(com(esc, command: true), simples) == nil, "⌘ + Esc no campo não vira nada")
        check(noCampo(com(esc, outros: true), simples) == nil, "⌃ ou ⌥ + Esc no campo não vira nada")
        check(noCampo(com(shiftTab, command: true), simples) == nil, "⌘ + ⇧Tab no campo não vira nada")
        check(noCampo(com(shiftTab, outros: true), simples) == nil, "⌃ ou ⌥ + ⇧Tab no campo não vira nada")
        check(noCampo(tecla(0, "a", outros: true), simples) == nil, "⌥ + letra no campo não vira nada")

        // A única exceção é o ⌘. — e é o ponto que conta, não qualquer ⌘.
        check(naLista(comandoPonto, simples) == .cancelar, "⌘. continua cancelando na lista")
        check(noCampo(comandoPonto, simples) == .cancelar, "⌘. continua cancelando no campo")
        check(naLista(tecla(47, ".", outros: true), simples) == nil, "⌃. ou ⌥. (sem ⌘) não vira nada")
    }

    // MARK: - Sem pergunta

    private static func testSemPerguntaAtivaNadaViraNada() {
        var cancelada = rodada(.setHighlight(1))
        _ = AskReducer.reduce(state: &cancelada, action: .cancelActive)
        check(cancelada.active == nil, "preparo: pergunta cancelada, nada ativo")

        let teclas: [(String, AskTecla)] = [
            ("↓", baixo), ("↑", cima), ("←", esquerda), ("→", direita),
            ("\"1\"", numero(1)), ("\"2\" do teclado numérico", numerico(2)),
            ("Enter", retorno), ("Enter do teclado numérico", enterNumerico), ("espaço", espaco),
            ("Tab", tab), ("⇧Tab", shiftTab), ("Esc", esc), ("⌘.", comandoPonto), ("letra", letra),
        ]
        for (nome, state) in [("estado vazio", AskState()), ("depois de cancelar", cancelada)] {
            for (qual, t) in teclas {
                check(naLista(t, state) == nil, "sem pergunta ativa, \(qual) na lista não vira nada (\(nome))")
                check(noCampo(t, state) == nil, "sem pergunta ativa, \(qual) no campo não vira nada (\(nome))")
            }
        }
    }

    // MARK: - Tecla → comando → reducer

    /// Aperta a tecla na lista e aplica a ação que saiu. Trava se não sair ação.
    @discardableResult
    private static func apertar(_ t: AskTecla, _ state: inout AskState, _ passo: String) -> [AskEffect] {
        guard case .acao(let acao)? = naLista(t, state) else {
            preconditionFailure("rodada pelo teclado: \(passo) deveria virar uma ação do reducer")
        }
        return AskReducer.reduce(state: &state, action: acao)
    }

    /// O roteiro do teste ao vivo da etapa, sem janela: três perguntas
    /// respondidas só por teclas, com volta para trocar a primeira resposta.
    private static func testRodadaInteiraSoPeloTeclado() {
        // Ao ganhar o teclado, o app põe o destaque na primeira opção.
        var state = rodada(.setHighlight(0))

        check(apertar(numero(1), &state, "\"1\" na primeira").isEmpty, "\"1\" responde a primeira sem resolver a rodada")
        check(state.page == 1 && state.answers["Primeira"]?.labels == ["A"],
              "\"1\" responde a primeira com \"A\" e abre a segunda")

        apertar(numero(1), &state, "\"1\" na múltipla")
        apertar(numero(3), &state, "\"3\" na múltipla")
        check(state.page == 1 && state.selected == ["A", "C"], "\"1\" e \"3\" marcam \"A\" e \"C\" sem sair da pergunta")
        check(apertar(retorno, &state, "Enter na múltipla").isEmpty, "Enter confirma a múltipla sem resolver a rodada")
        check(state.page == 2 && state.answers["Segunda"]?.labels == ["A", "C"],
              "Enter confirma [\"A\", \"C\"] e abre a terceira")

        apertar(esquerda, &state, "← na terceira")
        check(state.page == 1 && state.selected == ["A", "C"], "← volta à segunda com as marcadas de volta")
        apertar(esquerda, &state, "← na segunda")
        check(state.page == 0 && state.highlight == 0, "← de novo volta à primeira, com o destaque na resposta dada")
        check(naLista(esquerda, state) == nil, "na primeira, ← não vira nada")

        apertar(numero(2), &state, "\"2\" na primeira revisitada")
        check(state.answers["Primeira"]?.labels == ["B"], "\"2\" troca a resposta da primeira para \"B\"")
        check(state.page == 2, "trocada a resposta, a rodada segue para a pendente (a terceira)")

        let efeitos = apertar(retorno, &state, "Enter na terceira")
        let esperado: [String: AskAnswer] = [
            "Primeira": AskAnswer(labels: ["B"], text: nil),
            "Segunda": AskAnswer(labels: ["A", "C"], text: nil),
            "Terceira": AskAnswer(labels: ["X"], text: nil),
        ]
        check(efeitos == [.resolve(id: "rodada", answers: esperado)],
              "Enter na terceira resolve a rodada com as três respostas, a primeira já trocada")
        check(state.active == nil, "respondida a rodada, não sobra pergunta ativa")
        check(naLista(retorno, state) == nil, "depois da rodada, Enter não vira nada")
    }
}
