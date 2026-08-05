//
//  tools/sectionordercheck.swift — self-check da ordenação das seções do card.
//  NÃO faz parte do alvo do app.
//
//  Rodar:
//  xcrun swiftc -parse-as-library -swift-version 5 \
//    Knobler/NotchSectionOrder.swift tools/sectionordercheck.swift \
//    -o /tmp/sectionordercheck && /tmp/sectionordercheck
//

import Foundation

@main
struct SectionOrderCheck {
    static func main() {
        testOrdemBaseEmRepouso()
        testEventoRecenteSobe()
        testEventoAntigoNaoSobe()
        testSemConteudoSai()
        testFixadaVaziaApareceNaPosicaoDaBase()
        testNaoFixadaVaziaContinuaFora()
        testSanearFixadasDescartaDesconhecida()
        testMaisRecentePrimeiro()
        testNotaTravaTudo()
        testEstadoRepetidoNaoDerruba()
        testDesinstaladaSomeDoEditor()
        testFixadaDesinstaladaEIgnorada()
        testSanearDescartaDesconhecida()
        testSanearCompletaFaltantes()
        print("✅ sectionordercheck ok")
    }

    static let agora = Date(timeIntervalSince1970: 1_000_000)

    /// Atalho: seção com conteúdo cujo último evento foi há `haSegundos`.
    static func viva(_ s: NotchSection, haSegundos: TimeInterval?) -> NotchSectionState {
        NotchSectionState(section: s, hasContent: true,
                          lastEvent: haSegundos.map { agora.addingTimeInterval(-$0) })
    }

    /// Sem evento nenhum, manda a ordem que o usuário escolheu.
    static func testOrdemBaseEmRepouso() {
        let base: [NotchSection] = [.shelf, .musica, .atividade]
        let out = NotchSectionOrder.ordenar(
            base: base,
            estados: [viva(.musica, haSegundos: nil),
                      viva(.shelf, haSegundos: nil),
                      viva(.atividade, haSegundos: nil)],
            fixadas: [],
            agora: agora, travadaNaNota: false)
        assert(out == [.shelf, .musica, .atividade], "ordem-base não respeitada: \(out)")
    }

    /// Evento dentro da janela sobe pro topo, à frente da ordem-base.
    static func testEventoRecenteSobe() {
        let out = NotchSectionOrder.ordenar(
            base: [.shelf, .musica, .atividade],
            estados: [viva(.musica, haSegundos: nil),
                      viva(.shelf, haSegundos: nil),
                      viva(.atividade, haSegundos: 3)],
            fixadas: [],
            agora: agora, travadaNaNota: false)
        assert(out == [.atividade, .shelf, .musica], "evento de 3 s não promoveu: \(out)")
    }

    /// Fora da janela não promove — é o que impede o tique do Pomodoro e a
    /// posição da música de morarem no topo pra sempre.
    static func testEventoAntigoNaoSobe() {
        let out = NotchSectionOrder.ordenar(
            base: [.shelf, .musica, .atividade],
            estados: [viva(.musica, haSegundos: nil),
                      viva(.shelf, haSegundos: nil),
                      viva(.atividade, haSegundos: 30)],
            fixadas: [],
            agora: agora, travadaNaNota: false)
        assert(out == [.shelf, .musica, .atividade], "evento de 30 s promoveu: \(out)")
    }

    /// Seção sem conteúdo some da lista inteira — nem como ícone aparece.
    static func testSemConteudoSai() {
        let out = NotchSectionOrder.ordenar(
            base: [.shelf, .musica, .atividade],
            estados: [viva(.musica, haSegundos: nil),
                      NotchSectionState(section: .shelf, hasContent: false, lastEvent: nil),
                      viva(.atividade, haSegundos: nil)],
            fixadas: [],
            agora: agora, travadaNaNota: false)
        assert(out == [.musica, .atividade], "seção vazia sobreviveu: \(out)")
    }

    /// Seção fixada aparece mesmo vazia, na posição da ordem-base.
    static func testFixadaVaziaApareceNaPosicaoDaBase() {
        let out = NotchSectionOrder.ordenar(
            base: [.musica, .nota, .shelf],
            estados: [viva(.musica, haSegundos: nil),
                      NotchSectionState(section: .nota, hasContent: false, lastEvent: nil),
                      viva(.shelf, haSegundos: nil)],
            fixadas: [.nota],
            agora: agora, travadaNaNota: false)
        assert(out == [.musica, .nota, .shelf], "fixada vazia fora da posição-base: \(out)")
    }

    /// Não fixada e sem conteúdo continua fora — o padrão não muda.
    static func testNaoFixadaVaziaContinuaFora() {
        let out = NotchSectionOrder.ordenar(
            base: [.musica, .nota, .shelf],
            estados: [viva(.musica, haSegundos: nil),
                      NotchSectionState(section: .nota, hasContent: false, lastEvent: nil),
                      viva(.shelf, haSegundos: nil)],
            fixadas: [],
            agora: agora, travadaNaNota: false)
        assert(out == [.musica, .shelf], "vazia não fixada entrou: \(out)")
    }

    /// `rawValue` desconhecido (versão futura, disco corrompido) é descartado;
    /// duplicata some no Set.
    static func testSanearFixadasDescartaDesconhecida() {
        let out = NotchSectionOrder.sanearFixadas(salvas: ["nota", "chapeu", "nota"])
        assert(out == [.nota], "sanearFixadas não filtrou: \(out)")
    }

    /// Duas promovidas: a mais recente vem primeiro.
    static func testMaisRecentePrimeiro() {
        let out = NotchSectionOrder.ordenar(
            base: [.musica, .atividade, .shelf],
            estados: [viva(.musica, haSegundos: nil),
                      viva(.atividade, haSegundos: 8),
                      viva(.shelf, haSegundos: 2)],
            fixadas: [],
            agora: agora, travadaNaNota: false)
        assert(out == [.shelf, .atividade, .musica], "recência entre promovidas errada: \(out)")
    }

    /// Digitando na nota, ela vence qualquer promoção. Sem isso o foco sai do
    /// campo, o `.onDisappear` zera o foco de teclado e as teclas seguintes
    /// vazam pro app da frente sem sinal nenhum.
    static func testNotaTravaTudo() {
        let out = NotchSectionOrder.ordenar(
            base: [.musica, .atividade, .nota],
            estados: [viva(.musica, haSegundos: nil),
                      viva(.atividade, haSegundos: 1),
                      viva(.nota, haSegundos: 600)],
            fixadas: [],
            agora: agora, travadaNaNota: true)
        assert(out.first == .nota, "nota não travou o foco: \(out)")
    }

    /// Estado repetido não pode derrubar o app: o VM da Task 2 monta esse array
    /// e uma seção duplicada ali seria uma trap em runtime, não um erro
    /// recuperável. A última entrada vence — a mais nova é a que o VM acabou de
    /// escrever.
    static func testEstadoRepetidoNaoDerruba() {
        let out = NotchSectionOrder.ordenar(
            base: [.shelf, .musica, .atividade],
            estados: [viva(.musica, haSegundos: nil),
                      viva(.shelf, haSegundos: nil),
                      // primeiro sem conteúdo, depois viva e recém-promovida:
                      // se a última não vencesse, `atividade` sumiria da lista
                      NotchSectionState(section: .atividade, hasContent: false, lastEvent: nil),
                      viva(.atividade, haSegundos: 3)],
            fixadas: [],
            agora: agora, travadaNaNota: false)
        assert(out == [.atividade, .shelf, .musica], "duplicata: última entrada não venceu: \(out)")
    }

    // MARK: - Fase 3: a peça desinstalada leva a seção junto

    /// O editor de ordem esconde a seção de peça desinstalada — some da lista,
    /// sem aviso. A ordem salva não é tocada: `base` continua com ela.
    static func testDesinstaladaSomeDoEditor() {
        let base: [NotchSection] = [.musica, .pomodoro, .shelf]
        let out = NotchSectionOrder.visiveis(base: base, desinstaladas: [.pomodoro])
        assert(out == [.musica, .shelf], "seção desinstalada sobrou no editor: \(out)")
        assert(base.contains(.pomodoro), "a lista salva foi mexida")
    }

    /// Fixar passa por cima de `hasContent` — sem este filtro a faixa mostraria
    /// o ícone de uma peça que não existe mais. Fixação é **ignorada**, não
    /// apagada: `fixadas` continua com ela.
    static func testFixadaDesinstaladaEIgnorada() {
        let fixadas: Set<NotchSection> = [.pomodoro]
        let out = NotchSectionOrder.ordenar(
            base: [.musica, .pomodoro, .shelf],
            estados: [viva(.musica, haSegundos: nil),
                      NotchSectionState(section: .pomodoro, hasContent: false, lastEvent: nil),
                      viva(.shelf, haSegundos: nil)],
            fixadas: fixadas,
            agora: agora, travadaNaNota: false,
            desinstaladas: [.pomodoro])
        assert(out == [.musica, .shelf], "fixada desinstalada apareceu: \(out)")
        assert(fixadas.contains(.pomodoro), "a fixação foi apagada")
    }

    /// Chave do UserDefaults com lixo (versão antiga, seção removida) não
    /// pode derrubar a lista.
    static func testSanearDescartaDesconhecida() {
        let out = NotchSectionOrder.sanear(salva: ["musica", "fantasma", "shelf"])
        assert(!out.contains(where: { $0.rawValue == "fantasma" }), "seção desconhecida passou")
        assert(out.count == NotchSection.allCases.count, "sanear perdeu seções: \(out)")
    }

    /// Ordem salva de uma versão antiga (sem as seções novas) ganha o resto no
    /// fim, na ordem padrão.
    static func testSanearCompletaFaltantes() {
        let out = NotchSectionOrder.sanear(salva: ["shelf", "musica"])
        assert(Array(out.prefix(2)) == [.shelf, .musica], "prefixo salvo não preservado: \(out)")
        assert(Set(out) == Set(NotchSection.allCases), "sanear não completou: \(out)")
    }
}
