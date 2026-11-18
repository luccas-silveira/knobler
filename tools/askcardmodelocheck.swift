//
//  tools/askcardmodelocheck.swift — self-check do modelo puro do card de
//  pergunta. NÃO faz parte do alvo.
//
//  xcrun swiftc -parse-as-library -swift-version 5 \
//    Knobler/AskModels.swift Knobler/AskCard/AskCardModelo.swift \
//    tools/askcardmodelocheck.swift -o /tmp/askcardmodelocheck && /tmp/askcardmodelocheck
//
//  Prova o que o card decide sem desenhar nada: o sufixo de recomendada, o
//  resumo que a aba respondida mostra, a legenda de teclas do rodapé e o
//  tamanho do preview (ao lado ou embaixo, letra, largura do card, rolagem).
//  Os números esperados estão escritos por extenso de propósito: se uma
//  constante de AskPreviewLayout mudar, a conta daqui não muda junto.
//

import CoreGraphics
import Foundation

@main
enum AskCardModeloCheck {
    static func main() {
        testRotuloComSufixoViraRecomendada()
        testRotuloIgnoraMaiusculasEEspacoNoFim()
        testRotuloSemSufixoNoFimFicaInteiro()
        testRotuloVazio()

        testResumoSemResposta()
        testResumoDeTextoLivre()
        testResumoDeUmRotulo()
        testResumoDeVariosRotulos()

        testLegendaSemTecladoMostraOAtalho()
        testLegendaSemTecladoESemAtalhoFicaVazia()
        testLegendaDePerguntaSimples()
        testLegendaDePerguntaMultipla()
        testLegendaComAbas()
        testLegendaNoCampoDeTexto()

        testConstantesDoPreview()
        testPreviewSemPreviewsDevolveNil()
        testPreviewQueCabeFicaAoLado()
        testPreviewUsaOMaiorDosPreviews()
        testPreviewEstreitoNaoEncolheOCard()
        testPreviewLargoVaiEmbaixoComLetraCheia()
        testFronteiraEntreAoLadoEEmbaixo()
        testPreviewMuitoLargoEncolheALetraAteCaber()
        testPreviewLargoDemaisParaNoPisoERola()
        testPreviewAltoDemaisParaNoPisoERola()
        testPreviewAltoEncolheALetraAteCaberNaAltura()

        print("askcardmodelocheck: OK")
    }

    // MARK: - Helpers

    private static func check(_ condition: @autoclosure () -> Bool, _ message: String) {
        precondition(condition(), message)
    }

    private static func perto(_ a: CGFloat, _ b: CGFloat, _ tolerancia: CGFloat = 0.001) -> Bool {
        abs(a - b) < tolerancia
    }

    /// Bloco de `linhas` linhas em que só a do meio tem `colunas` caracteres e
    /// as outras têm a metade: quem medir a primeira linha, a última ou o texto
    /// inteiro em vez da linha mais larga erra a conta.
    private static func bloco(_ colunas: Int, _ linhas: Int) -> String {
        (0..<linhas).map { i in
            String(repeating: "x", count: i == linhas / 2 ? colunas : max(1, colunas / 2))
        }.joined(separator: "\n")
    }

    /// Medidas da fonte monoespaçada a 11 pt usadas em todos os casos: avanço
    /// 6,6 e linha 13.
    private static func layout(
        _ previews: [String],
        larguraMaxima: CGFloat = 836,
        alturaMaxima: CGFloat = 600
    ) -> AskPreviewLayout? {
        AskPreviewLayout.calcular(
            previews: previews,
            avanco: 6.6,
            linha: 13,
            larguraMaxima: larguraMaxima,
            alturaMaxima: alturaMaxima
        )
    }

    private static func legenda(
        teclado: Bool,
        campo: Bool = false,
        multipla: Bool = false,
        abas: Bool = false,
        atalho: String? = "⌃⌥K"
    ) -> [AskLegendaItem] {
        AskLegenda.itens(teclado: teclado, campo: campo, multipla: multipla, abas: abas, atalho: atalho)
    }

    private static let escolher = AskLegendaItem(teclas: ["↑", "↓"], texto: "escolher")
    private static let soltar = AskLegendaItem(teclas: ["esc"], texto: "soltar")
    private static let pergunta = AskLegendaItem(teclas: ["←", "→"], texto: "pergunta")

    // MARK: - Rótulo recomendado

    private static func testRotuloComSufixoViraRecomendada() {
        let pt = AskRotulo.separar("Atalho global (Recomendado)")
        check(pt.texto == "Atalho global", "o sufixo (Recomendado) sai do texto, sem espaço sobrando")
        check(pt.recomendada, "rótulo que termina em (Recomendado) é recomendada")

        let en = AskRotulo.separar("X (Recommended)")
        check(en.texto == "X", "o sufixo (Recommended) sai do texto")
        check(en.recomendada, "rótulo que termina em (Recommended) é recomendada")

        let acento = AskRotulo.separar("Opção própria (Recomendado)")
        check(acento.texto == "Opção própria", "o texto antes do sufixo sai inteiro, com acento")
        check(acento.recomendada, "acento no rótulo não atrapalha o sufixo")
    }

    private static func testRotuloIgnoraMaiusculasEEspacoNoFim() {
        let alto = AskRotulo.separar("Atalho Global (RECOMENDADO)")
        check(alto.texto == "Atalho Global", "o texto mantém as maiúsculas originais")
        check(alto.recomendada, "(RECOMENDADO) em maiúsculas conta")

        let baixo = AskRotulo.separar("x (recommended)")
        check(baixo.texto == "x", "(recommended) em minúsculas sai do texto")
        check(baixo.recomendada, "(recommended) em minúsculas conta")

        let sobra = AskRotulo.separar("Atalho global (Recomendado)  ")
        check(sobra.texto == "Atalho global", "espaço depois do sufixo não impede de tirá-lo")
        check(sobra.recomendada, "espaço depois do sufixo não impede a recomendada")

        let pontas = AskRotulo.separar("  Atalho global  ")
        check(pontas.texto == "Atalho global", "rótulo sem sufixo perde os espaços das pontas")
        check(!pontas.recomendada, "rótulo sem sufixo não é recomendada")
    }

    private static func testRotuloSemSufixoNoFimFicaInteiro() {
        let frase = AskRotulo.separar("Recomendado para todos")
        check(frase.texto == "Recomendado para todos", "a palavra sem parênteses fica no texto")
        check(!frase.recomendada, "a palavra sem parênteses não marca recomendada")

        let comeco = AskRotulo.separar("(Recomendado) X")
        check(comeco.texto == "(Recomendado) X", "sufixo fora do fim fica no texto")
        check(!comeco.recomendada, "sufixo fora do fim não marca recomendada")

        let meio = AskRotulo.separar("X (Recommended) de novo")
        check(meio.texto == "X (Recommended) de novo", "sufixo no meio fica no texto")
        check(!meio.recomendada, "sufixo no meio não marca recomendada")
    }

    private static func testRotuloVazio() {
        let vazio = AskRotulo.separar("")
        check(vazio.texto == "", "rótulo vazio devolve texto vazio")
        check(!vazio.recomendada, "rótulo vazio não é recomendada")

        let espacos = AskRotulo.separar("   ")
        check(espacos.texto == "", "rótulo só de espaços devolve texto vazio")
        check(!espacos.recomendada, "rótulo só de espaços não é recomendada")
    }

    // MARK: - Resumo da resposta

    private static func testResumoSemResposta() {
        check(AskResumo.texto(nil) == "", "pergunta sem resposta não tem resumo")
    }

    private static func testResumoDeTextoLivre() {
        let resposta = AskAnswer(labels: [], text: "  usar o terminal \n")
        check(AskResumo.texto(resposta) == "usar o terminal", "texto livre sai sem espaços nas pontas")
    }

    private static func testResumoDeUmRotulo() {
        check(AskResumo.texto(AskAnswer(labels: ["Só no card"], text: nil)) == "Só no card",
              "um rótulo é o próprio resumo")
        check(AskResumo.texto(AskAnswer(labels: ["Atalho global (Recomendado)"], text: nil)) == "Atalho global",
              "o resumo de um rótulo sai sem o sufixo (Recomendado)")
        check(AskResumo.texto(AskAnswer(labels: ["X (Recommended)"], text: nil)) == "X",
              "o resumo de um rótulo sai sem o sufixo (Recommended)")
    }

    private static func testResumoDeVariosRotulos() {
        check(AskResumo.texto(AskAnswer(labels: ["A", "B", "C"], text: nil)) == "3 marcadas",
              "três rótulos viram a contagem")
        // O quadro "De volta à primeira" do mockup mostra "2 marcadas" na aba.
        check(AskResumo.texto(AskAnswer(labels: ["A", "B (Recomendado)"], text: nil)) == "2 marcadas",
              "dois rótulos viram a contagem, não o primeiro rótulo")
    }

    // MARK: - Legenda de teclas

    private static func testLegendaSemTecladoMostraOAtalho() {
        let esperado = [AskLegendaItem(teclas: ["⌃⌥K"], texto: "responder pelo teclado")]
        check(legenda(teclado: false) == esperado, "sem teclado, a legenda é só o atalho que foca o card")
        check(legenda(teclado: false, multipla: true, abas: true) == esperado,
              "sem teclado, múltipla e abas não acrescentam tecla nenhuma")
        check(legenda(teclado: false, atalho: "⌘J") == [AskLegendaItem(teclas: ["⌘J"], texto: "responder pelo teclado")],
              "a tecla mostrada é o atalho recebido, não um texto fixo")
    }

    private static func testLegendaSemTecladoESemAtalhoFicaVazia() {
        check(legenda(teclado: false, atalho: nil).isEmpty, "sem teclado e sem atalho não há legenda")
        check(legenda(teclado: false, multipla: true, abas: true, atalho: nil).isEmpty,
              "sem teclado e sem atalho não há legenda, seja qual for a pergunta")
    }

    private static func testLegendaDePerguntaSimples() {
        let esperado = [escolher, AskLegendaItem(teclas: ["⏎"], texto: "responder"), soltar]
        check(legenda(teclado: true) == esperado, "simples, uma pergunta: ↑ ↓ escolher, ⏎ responder, esc soltar")
        check(legenda(teclado: true, atalho: nil) == esperado, "com o teclado no card, o atalho não entra na legenda")
    }

    private static func testLegendaDePerguntaMultipla() {
        let esperado = [
            escolher,
            AskLegendaItem(teclas: ["espaço"], texto: "marcar"),
            AskLegendaItem(teclas: ["⏎"], texto: "confirmar"),
            soltar,
        ]
        check(legenda(teclado: true, multipla: true) == esperado,
              "múltipla: ↑ ↓ escolher, espaço marcar, ⏎ confirmar, esc soltar")
    }

    private static func testLegendaComAbas() {
        check(legenda(teclado: true, abas: true)
                == [escolher, AskLegendaItem(teclas: ["⏎"], texto: "responder"), pergunta, soltar],
              "com mais de uma pergunta, ← → pergunta entra antes de esc soltar")
        check(legenda(teclado: true, multipla: true, abas: true)
                == [
                    escolher,
                    AskLegendaItem(teclas: ["espaço"], texto: "marcar"),
                    AskLegendaItem(teclas: ["⏎"], texto: "confirmar"),
                    pergunta,
                    soltar,
                ],
              "múltipla com abas: ← → pergunta entra antes de esc soltar")
    }

    private static func testLegendaNoCampoDeTexto() {
        let esperado = [
            AskLegendaItem(teclas: ["⏎"], texto: "enviar"),
            AskLegendaItem(teclas: ["esc"], texto: "voltar à lista"),
            AskLegendaItem(teclas: [], texto: "⌥ direita dita"),
        ]
        check(legenda(teclado: true, campo: true) == esperado,
              "no campo: ⏎ enviar, esc voltar à lista e a dica do ditado sem tecla")
        check(legenda(teclado: true, campo: true, multipla: true, abas: true) == esperado,
              "o campo vence múltipla e abas")
        // O card chama `itens(teclado: false, campo: textFocused, …)`: o campo
        // vence também a falta do teclado e a falta do atalho.
        check(legenda(teclado: false, campo: true) == esperado, "o campo vence a legenda do atalho")
        check(legenda(teclado: false, campo: true, atalho: nil) == esperado, "o campo vence a legenda vazia")
    }

    // MARK: - Tamanho do preview

    private static func testConstantesDoPreview() {
        check(AskPreviewLayout.larguraMinima == 460, "larguraMinima é 460")
        check(AskPreviewLayout.margem == 40, "margem é 40 (20 de cada lado)")
        check(AskPreviewLayout.lista == 236, "lista é 236")
        check(AskPreviewLayout.vao == 10, "vao é 10")
        check(AskPreviewLayout.dentro == 20, "dentro é 20")
        check(AskPreviewLayout.vertical == 16, "vertical é 16")
        check(AskPreviewLayout.entreLinhas == 2, "entreLinhas é 2")
        check(AskPreviewLayout.base == 11, "base é 11")
        check(AskPreviewLayout.piso == 8, "piso é 8")
    }

    private static func testPreviewSemPreviewsDevolveNil() {
        check(layout([]) == nil, "sem preview não há layout")
    }

    private static func testPreviewQueCabeFicaAoLado() {
        guard let l = layout([bloco(44, 9)]) else { return check(false, "44 × 9 tem layout") }
        check(l.lado, "44 colunas cabem ao lado da lista")
        check(perto(l.fonte, 11), "ao lado a letra é 11")
        // 236 + 10 + 290,4 + 20 + 40 = 596,4 → 597
        check(perto(l.larguraDoCard, ceil(236 + 10 + 44 * 6.6 + 20 + 40)),
              "card ao lado = lista + vão + texto + padding + margem, arredondado para cima")
        check(perto(l.larguraDoCard, 597), "card de 44 colunas ao lado tem 597")
        check(perto(l.quadro.width, 44 * 6.6 + 20), "quadro = texto + padding horizontal, sem arredondar")
        check(perto(l.quadro.height, 9 * (13 + 2) + 16), "altura do quadro = linhas × (linha + 2) + 16")
        check(!l.rola, "preview que cabe não rola")
    }

    private static func testPreviewUsaOMaiorDosPreviews() {
        let so = layout([bloco(44, 9)])
        check(so != nil, "44 × 9 tem layout")
        check(layout([bloco(44, 9), bloco(20, 3)]) == so, "o preview menor depois não muda o quadro")
        check(layout([bloco(20, 3), bloco(44, 9)]) == so, "o preview menor antes não muda o quadro")
        // colunas e linhas são máximos independentes: o mais largo e o mais
        // alto podem ser previews diferentes.
        check(layout([bloco(44, 3), bloco(20, 9)]) == so, "largura de um preview e altura de outro")
        check(layout([bloco(20, 9), bloco(44, 3)]) == so, "altura de um preview e largura de outro")
    }

    private static func testPreviewEstreitoNaoEncolheOCard() {
        guard let l = layout([bloco(10, 3)]) else { return check(false, "10 × 3 tem layout") }
        check(l.lado, "10 colunas cabem ao lado")
        check(perto(l.fonte, 11), "ao lado a letra é 11")
        check(perto(l.larguraDoCard, 460), "o card não fica abaixo de 460")
        check(perto(l.quadro.width, 10 * 6.6 + 20), "o quadro segue do tamanho do texto, não do card")
        check(!l.rola, "preview estreito não rola")
    }

    private static func testPreviewLargoVaiEmbaixoComLetraCheia() {
        guard let l = layout([bloco(102, 4)]) else { return check(false, "102 × 4 tem layout") }
        check(!l.lado, "102 colunas não cabem ao lado: vai embaixo")
        check(perto(l.fonte, 11), "embaixo, cabendo na largura, a letra não passa de 11 nem encolhe")
        // 673,2 + 20 + 40 = 733,2 → 734
        check(perto(l.larguraDoCard, ceil(102 * 6.6 + 20 + 40)),
              "card embaixo = texto + padding + margem, arredondado para cima")
        check(perto(l.larguraDoCard, 734), "card de 102 colunas embaixo tem 734")
        check(perto(l.quadro.width, 102 * 6.6 + 20), "quadro = texto + padding horizontal")
        check(perto(l.quadro.height, 4 * (13 + 2) + 16), "altura do quadro = linhas × (linha + 2) + 16")
        check(!l.rola, "preview que cabe embaixo não rola")
    }

    private static func testFronteiraEntreAoLadoEEmbaixo() {
        // 236 + 10 + c × 6,6 + 20 + 40 ≤ 836 vale até 80 colunas (834) e
        // deixa de valer em 81 (840,6).
        guard let cabe = layout([bloco(80, 2)]), let passa = layout([bloco(81, 2)]) else {
            return check(false, "80 e 81 colunas têm layout")
        }
        check(cabe.lado, "80 colunas ainda cabem ao lado")
        check(!cabe.rola, "80 colunas ao lado não rolam")
        check(!passa.lado, "81 colunas já vão embaixo: padding e margem entram na conta")
        check(perto(passa.fonte, 11), "81 colunas embaixo ficam com a letra cheia")
        check(perto(passa.larguraDoCard, ceil(81 * 6.6 + 20 + 40)),
              "81 colunas embaixo: o card não leva a largura da lista")
    }

    private static func testPreviewMuitoLargoEncolheALetraAteCaber() {
        guard let l = layout([bloco(150, 2)]) else { return check(false, "150 × 2 tem layout") }
        let fonte: CGFloat = 11 * (836 - 40 - 20) / (150 * 6.6)   // ≈ 8,62
        check(!l.lado, "150 colunas vão embaixo")
        check(l.fonte < 11, "150 colunas encolhem a letra")
        check(l.fonte >= 8, "a letra não desce do piso")
        check(perto(l.fonte, fonte), "letra = 11 × (largura máxima − margem − padding) / texto")
        check(perto(l.larguraDoCard, 836), "o card ocupa a largura máxima")
        check(perto(l.quadro.width, 836 - 40), "o texto cabe exato: quadro = largura máxima − margem")
        check(perto(l.quadro.height, 2 * (13 * fonte / 11 + 2) + 16), "a altura da linha escala com a letra")
        check(!l.rola, "com a letra encolhida o preview cabe e não rola")
    }

    private static func testPreviewLargoDemaisParaNoPisoERola() {
        guard let l = layout([bloco(300, 2)]) else { return check(false, "300 × 2 tem layout") }
        check(!l.lado, "300 colunas vão embaixo")
        check(perto(l.fonte, 8), "300 colunas param no piso de 8")
        check(l.rola, "no piso e ainda sem caber na largura, o preview rola")
        check(perto(l.larguraDoCard, 836), "o card não passa da largura máxima")
    }

    private static func testPreviewAltoDemaisParaNoPisoERola() {
        guard let l = layout([bloco(10, 80)], alturaMaxima: 300) else { return check(false, "10 × 80 tem layout") }
        check(l.lado, "10 colunas ficam ao lado, mesmo altas")
        check(perto(l.fonte, 8), "80 linhas em 300 de altura param no piso de 8")
        check(l.rola, "no piso e ainda sem caber na altura, o preview rola")
        check(perto(l.larguraDoCard, 460), "o card segue na largura mínima")

        // A mesma pilha com altura de sobra não encolhe nem rola.
        guard let folgado = layout([bloco(10, 80)], alturaMaxima: 2000) else {
            return check(false, "10 × 80 tem layout com altura de sobra")
        }
        check(perto(folgado.fonte, 11), "cabendo na altura, a letra fica em 11")
        check(perto(folgado.quadro.height, 80 * (13 + 2) + 16), "80 linhas a 11 pt têm 1216 de altura")
        check(!folgado.rola, "cabendo na altura, não rola")
    }

    private static func testPreviewAltoEncolheALetraAteCaberNaAltura() {
        // 30 linhas a 11 pt: 30 × 15 + 16 = 466 > 400. A letra que faz caber
        // resolve 30 × (13 × f / 11 + 2) + 16 = 400 → f ≈ 9,14.
        guard let l = layout([bloco(10, 30)], alturaMaxima: 400) else { return check(false, "10 × 30 tem layout") }
        let fonte: CGFloat = 11 * ((400 - 16) / 30 - 2) / 13
        check(l.lado, "10 colunas ficam ao lado")
        check(l.fonte < 11, "30 linhas em 400 de altura encolhem a letra")
        check(l.fonte > 8, "a letra só vai ao piso quando precisa")
        check(l.quadro.height <= 400 + 0.001, "a altura recalculada cabe na altura máxima")
        check(!l.rola, "encolhendo até caber, o preview não rola")
        check(perto(l.fonte, fonte, 0.01), "a letra é a maior que cabe na altura")
        check(perto(l.quadro.height, 400, 0.01), "a altura recalculada encosta na altura máxima")
        check(perto(l.quadro.width, 10 * 6.6 * fonte / 11 + 20, 0.01), "a largura do quadro acompanha a letra final")
    }
}
