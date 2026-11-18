//
//  tools/askcheck.swift — self-check do domínio Ask. NÃO faz parte do alvo.
//
//  Rodar depois da Fase 2:
//  xcrun swiftc -parse-as-library -swift-version 5 \
//    Knobler/AskModels.swift Knobler/AskFeature.swift \
//    tools/askcheck.swift -o /tmp/askcheck && /tmp/askcheck
//
//  Este arquivo caracteriza as invariantes do comportamento atual. Ele não
//  contém placeholders: AskState, AskAction, AskEffect e AskReducer vêm de
//  Knobler/AskFeature.swift, e os modelos vêm de Knobler/AskModels.swift.
//

import Foundation

@main
struct AskCheck {
    static func main() {
        testEnqueueAndFIFO()
        testNewQuestionStartsAtZero()
        testMultiSelectTogglesLabels()
        testAppendText()
        testSetText()
        testTextWinsLabels()
        testInvalidSubmissionsAreNoOp()
        testPagedSubmissionPreservesPreviousAnswers()
        testLastPageResolvesAllAnswers()
        testCancellationIsIdempotent()
        testLegacyCompletionActions()
        testClearRemovesActiveOrQueuedRequest()
        testNextRequestIsPromoted()
        testExternalDismiss()

        testGoToReturnsWithoutEffectAndKeepsAnswers()
        testReturningToAnsweredSingleHighlightsTheAnswer()
        testReturningToAnsweredMultiRestoresSelection()
        testReturningToTextAnswerRestoresText()
        testAnsweringAgainReplacesTheAnswer()
        testNextPendingWrapsAround()
        testOutOfOrderLastPendingResolves()
        testSameQuestionTextCountsOnce()
        testGoToOutOfRangeOrWithoutActiveIsNoOp()
        testUnconfirmedInputVanishesOnTabSwitch()
        testMoveHighlight()
        testSetHighlight()
        testChooseOutOfRangeIsNoOp()
        testChooseOnSingleEqualsSubmit()
        testChooseOnMultiTogglesAndHighlights()
        testHighlightAcrossPageChange()
        testPromotedRequestStartsWithoutHighlight()

        print("askcheck: OK")
    }

    // MARK: - Helpers

    @discardableResult
    private static func send(_ action: AskAction, to state: inout AskState) -> [AskEffect] {
        AskReducer.reduce(state: &state, action: action)
    }

    private static func check(_ condition: @autoclosure () -> Bool, _ message: String) {
        precondition(condition(), message)
    }

    private static func option(_ label: String) -> AskOption {
        AskOption(label: label, description: "", preview: nil)
    }

    private static func request(
        id: String,
        questions: [AskQuestion] = [question("Pergunta")],
        source: String? = nil
    ) -> AskRequest {
        AskRequest(
            id: id,
            questions: questions,
            receivedAt: Date(timeIntervalSince1970: 1_000),
            source: source
        )
    }

    private static func question(
        _ title: String,
        multiSelect: Bool = false,
        options: [AskOption] = [option("A"), option("B")]
    ) -> AskQuestion {
        AskQuestion(
            question: title,
            header: "",
            multiSelect: multiSelect,
            options: options
        )
    }

    // MARK: - Invariantes da fila e da promoção

    private static func testEnqueueAndFIFO() {
        var state = AskState()
        let first = request(id: "first")
        let second = request(id: "second")
        let third = request(id: "third")

        send(.enqueue(first), to: &state)
        send(.enqueue(second), to: &state)
        send(.enqueue(third), to: &state)

        check(state.active?.id == "first", "a primeira pergunta recebida fica ativa")
        check(state.queue.map(\.id) == ["second", "third"], "as perguntas seguintes entram em FIFO")

        // A mesma ID não pode duplicar nem a pergunta ativa nem a fila.
        send(.enqueue(first), to: &state)
        send(.enqueue(second), to: &state)
        check(state.active?.id == "first", "ID ativa duplicada não troca a pergunta")
        check(state.queue.map(\.id) == ["second", "third"], "ID enfileirada duplicada não cria cópia")
    }

    private static func testNewQuestionStartsAtZero() {
        var state = AskState()
        state.page = 2
        state.selected = ["resíduo"]
        state.answers = ["antiga": AskAnswer(labels: ["A"], text: nil)]
        state.text = "texto residual"

        let incoming = request(id: "fresh", questions: [question("Nova")])
        send(.enqueue(incoming), to: &state)

        check(state.active == incoming, "a nova pergunta vira ativa")
        check(state.page == 0, "pergunta nova começa na página zero")
        check(state.selected.isEmpty, "promoção limpa a seleção anterior")
        check(state.answers.isEmpty, "promoção limpa as respostas anteriores")
        check(state.text.isEmpty, "promoção limpa o texto anterior")
    }

    // MARK: - Invariantes de seleção e submissão

    private static func testMultiSelectTogglesLabels() {
        var state = AskState()
        let multi = request(
            id: "multi",
            questions: [question("Escolha várias", multiSelect: true)]
        )
        send(.enqueue(multi), to: &state)

        send(.toggle(label: "A"), to: &state)
        check(state.selected == ["A"], "multi-select adiciona o label")

        send(.toggle(label: "B"), to: &state)
        check(state.selected == ["A", "B"], "multi-select permite vários labels")

        send(.toggle(label: "A"), to: &state)
        check(state.selected == ["B"], "multi-select alterna o label selecionado")

        // Uma pergunta simples não aceita toggle como se fosse multi-select.
        var singleState = AskState()
        send(.enqueue(request(id: "single", questions: [question("Escolha uma")])), to: &singleState)
        send(.toggle(label: "A"), to: &singleState)
        check(singleState.selected.isEmpty, "toggle não seleciona uma pergunta simples")
    }

    private static func testAppendText() {
        var state = AskState()
        send(.enqueue(request(id: "req-1", questions: [question("Texto")])), to: &state)

        send(.appendText(id: "req-1", text: "primeiro"), to: &state)
        send(.appendText(id: "req-1", text: "segundo"), to: &state)
        assert(state.text == "primeiro segundo")
        send(.appendText(id: "outra", text: "não entra"), to: &state)
        assert(state.text == "primeiro segundo")

        var emptyState = AskState()
        send(.appendText(id: "req-1", text: "fora"), to: &emptyState)
        assert(emptyState.text.isEmpty)
    }

    private static func testSetText() {
        var state = AskState()
        send(.setText("edição corrente"), to: &state)
        check(state.text.isEmpty, "setText sem pergunta ativa é no-op")

        send(.enqueue(request(id: "set-text")), to: &state)
        send(.setText("primeira versão"), to: &state)
        check(state.text == "primeira versão", "setText substitui o texto do campo")
        send(.setText("segunda versão"), to: &state)
        check(state.text == "segunda versão", "setText atualiza o texto do campo")
    }

    private static func testTextWinsLabels() {
        var state = AskState()
        let title = "Resposta livre"
        send(.enqueue(request(id: "text", questions: [question(title, multiSelect: true)])), to: &state)

        let effects = send(.submit(labels: ["A"], text: "Resposta digitada"), to: &state)
        check(effects.count == 1, "submissão textual produz um resolve")
        guard case .resolve(_, let answers) = effects[0] else {
            preconditionFailure("submissão textual deve produzir AskEffect.resolve")
        }
        check(answers[title] == AskAnswer(labels: [], text: "Resposta digitada"),
              "texto livre vence labels quando o card envia texto")

        // Texto vazio não vence labels; nesse caso a resposta continua sendo
        // a seleção válida feita no card.
        var emptyTextState = AskState()
        send(.enqueue(request(id: "empty-text", questions: [question("Labels")])), to: &emptyTextState)
        let labelEffects = send(.submit(labels: ["A"], text: "   "), to: &emptyTextState)
        check(labelEffects == [.resolve(id: "empty-text", answers: [
            "Labels": AskAnswer(labels: ["A"], text: nil)
        ])], "texto vazio não substitui labels válidos")
    }

    private static func testInvalidSubmissionsAreNoOp() {
        let cases: [(String, [String], String?)] = [
            ("resposta sem labels nem texto", [], nil),
            ("texto vazio sem labels", [], ""),
            ("texto em branco sem labels", [], " \n\t"),
            ("label inexistente", ["desconhecida"], nil),
            ("mais de um label em pergunta simples", ["A", "B"], nil),
            ("mais de um label em pergunta simples com texto", ["A", "B"], "Resposta")
        ]

        for (description, labels, text) in cases {
            var state = AskState()
            send(.enqueue(request(id: "invalid", questions: [question("Inválida")])), to: &state)
            let before = state

            let effects = send(.submit(labels: labels, text: text), to: &state)
            check(effects.isEmpty, "\(description) não produz efeitos")
            check(state == before, "\(description) é no-op e preserva o estado")
        }

        // A mesma validação vale quando o texto está presente: labels
        // desconhecidos continuam inválidos, mesmo que texto vença labels
        // válidos.
        var invalidWithText = AskState()
        send(.enqueue(request(id: "invalid-text", questions: [question("Inválida com texto")])), to: &invalidWithText)
        let before = invalidWithText
        let effects = send(.submit(labels: ["desconhecida"], text: "Resposta"), to: &invalidWithText)
        check(effects.isEmpty && invalidWithText == before,
              "label inexistente mantém no-op mesmo com texto")

        var multiState = AskState()
        send(.enqueue(request(id: "multi-invalid", questions: [question("Multi inválida", multiSelect: true)])), to: &multiState)
        let multiBefore = multiState
        let multiEffects = send(.submit(labels: ["A", "desconhecida"], text: "Resposta"), to: &multiState)
        check(multiEffects.isEmpty && multiState == multiBefore,
              "label inexistente é no-op também em multi-select")
    }

    private static func testPagedSubmissionPreservesPreviousAnswers() {
        var state = AskState()
        let firstTitle = "Primeira página"
        let secondTitle = "Segunda página"
        let paged = request(id: "paged", questions: [
            question(firstTitle),
            question(secondTitle)
        ])
        send(.enqueue(paged), to: &state)

        let firstEffects = send(.submit(labels: ["A"], text: nil), to: &state)
        check(firstEffects.isEmpty, "página intermediária ainda não resolve o Ask")
        check(state.page == 1, "submissão intermediária avança uma página")
        check(state.answers[firstTitle] == AskAnswer(labels: ["A"], text: nil),
              "submissão intermediária preserva a resposta anterior")
        check(state.selected.isEmpty && state.text.isEmpty,
              "submissão intermediária limpa apenas o input corrente")
    }

    private static func testLastPageResolvesAllAnswers() {
        var state = AskState()
        let firstTitle = "Uma"
        let secondTitle = "Duas"
        let paged = request(id: "resolve-all", questions: [
            question(firstTitle),
            question(secondTitle)
        ])
        send(.enqueue(paged), to: &state)
        send(.submit(labels: ["A"], text: nil), to: &state)

        let effects = send(.submit(labels: ["B"], text: nil), to: &state)
        let expected: [String: AskAnswer] = [
            firstTitle: AskAnswer(labels: ["A"], text: nil),
            secondTitle: AskAnswer(labels: ["B"], text: nil)
        ]
        check(effects == [.resolve(id: "resolve-all", answers: expected)],
              "última página produz todas as respostas")
        check(state.active == nil, "resolve limpa a pergunta ativa")

        let repeated = send(.submit(labels: ["B"], text: nil), to: &state)
        check(repeated.isEmpty, "resposta repetida depois de resolve é no-op")
    }

    // MARK: - Invariantes de conclusão e limpeza

    private static func testCancellationIsIdempotent() {
        var state = AskState()
        send(.enqueue(request(id: "cancel", questions: [question("Cancelar")])), to: &state)

        let first = send(.cancelActive, to: &state)
        check(first == [.cancel(id: "cancel")], "cancelamento emite um único efeito cancel")
        check(state.active == nil, "cancelamento limpa a pergunta ativa")

        let second = send(.cancelActive, to: &state)
        check(second.isEmpty, "cancelamento repetido é no-op")

        // Uma submissão depois de concluir também não pode emitir resposta de novo.
        let repeatedSubmit = send(.submit(labels: ["A"], text: nil), to: &state)
        check(repeatedSubmit.isEmpty, "resposta repetida sem pergunta ativa é no-op")
    }

    private static func testLegacyCompletionActions() {
        let answer = AskAnswer(labels: ["A"], text: nil)
        var resolvedState = AskState()
        send(.enqueue(request(id: "legacy-resolve")), to: &resolvedState)

        let resolveEffects = send(.resolve(id: "legacy-resolve", answers: [
            "Pergunta": answer
        ]), to: &resolvedState)
        check(resolveEffects == [.resolve(id: "legacy-resolve", answers: [
            "Pergunta": answer
        ])], "resposta do card legado passa pelo efeito do store")
        check(resolvedState.active == nil, "resolve legado limpa a pergunta ativa")
        check(send(.resolve(id: "legacy-resolve", answers: ["Pergunta": answer]), to: &resolvedState).isEmpty,
              "resolve legado repetido é no-op")

        var cancelledState = AskState()
        send(.enqueue(request(id: "legacy-cancel")), to: &cancelledState)
        check(send(.cancel(id: "legacy-cancel"), to: &cancelledState) == [.cancel(id: "legacy-cancel")],
              "cancelamento do card legado passa pelo efeito do store")
        check(cancelledState.active == nil, "cancelamento legado limpa a pergunta ativa")
        check(send(.cancel(id: "legacy-cancel"), to: &cancelledState).isEmpty,
              "cancelamento legado repetido é no-op")

        var queuedState = AskState()
        send(.enqueue(request(id: "active")), to: &queuedState)
        send(.enqueue(request(id: "queued")), to: &queuedState)
        check(send(.cancel(id: "queued"), to: &queuedState).isEmpty,
              "cancelamento legado de ID enfileirada não afeta a ativa")
        check(queuedState.active?.id == "active" && queuedState.queue.count == 1,
              "cancelamento legado inválido preserva a fila")
    }

    private static func testClearRemovesActiveOrQueuedRequest() {
        var state = AskState()
        let active = request(id: "active")
        let queued = request(id: "queued")
        let remaining = request(id: "remaining")
        send(.enqueue(active), to: &state)
        send(.enqueue(queued), to: &state)
        send(.enqueue(remaining), to: &state)

        let queuedClearEffects = send(.clear(id: "queued"), to: &state)
        check(queuedClearEffects.isEmpty, "clear de pergunta enfileirada não emite efeito")
        check(state.queue.map(\.id) == ["remaining"], "clear remove uma pergunta enfileirada")

        let activeClearEffects = send(.clear(id: "active"), to: &state)
        check(activeClearEffects.isEmpty, "clear da pergunta ativa não emite efeito")
        check(state.active?.id == "remaining", "clear remove a ativa e promove a próxima")
        check(state.queue.isEmpty, "a fila fica vazia após promover a única pendente")
    }

    private static func testNextRequestIsPromoted() {
        var state = AskState()
        let first = request(id: "one")
        let second = request(id: "two")
        send(.enqueue(first), to: &state)
        send(.enqueue(second), to: &state)

        state.page = 3
        state.selected = ["resíduo"]
        state.answers = ["antiga": AskAnswer(labels: ["A"], text: nil)]
        state.text = "texto residual"

        let effects = send(.cancelActive, to: &state)
        check(effects == [.cancel(id: "one")], "conclusão da ativa emite o efeito correto")
        check(state.active?.id == "two", "a próxima pergunta é promovida após concluir a atual")
        check(state.page == 0, "a pergunta promovida começa na página zero")
        check(state.selected.isEmpty, "promoção limpa a seleção residual")
        check(state.answers.isEmpty, "promoção limpa as respostas residuais")
        check(state.text.isEmpty, "promoção limpa o texto residual")
    }

    private static func testExternalDismiss() {
        var state = AskState()
        send(.enqueue(request(id: "active")), to: &state)
        send(.enqueue(request(id: "queued")), to: &state)

        let activeEffects = send(.externalDismiss(id: "active"), to: &state)
        check(activeEffects.isEmpty, "dismiss externo não emite efeito")
        check(state.active?.id == "queued", "dismiss externo promove a próxima pergunta")

        send(.externalDismiss(id: "queued"), to: &state)
        check(state.active == nil && state.queue.isEmpty,
              "dismiss externo remove a pergunta ativa")
        check(send(.externalDismiss(id: "missing"), to: &state).isEmpty,
              "dismiss externo de ID inexistente é no-op")
    }

    // MARK: - Abas e próxima pendente

    private static func testGoToReturnsWithoutEffectAndKeepsAnswers() {
        var state = AskState()
        send(.enqueue(request(id: "abas", questions: [
            question("Q1"), question("Q2"), question("Q3")
        ])), to: &state)

        check(send(.submit(labels: ["A"], text: nil), to: &state).isEmpty,
              "responder a 1ª de três não resolve")
        check(state.page == 1, "responder a 1ª leva à página 1")
        let answered = ["Q1": AskAnswer(labels: ["A"], text: nil)]

        let back = send(.goTo(page: 0), to: &state)
        check(back.isEmpty, "goTo não emite efeito")
        check(state.page == 0, "goTo(0) volta à primeira pergunta")
        check(state.answers == answered, "goTo deixa as respostas intactas")
        check(state.active?.id == "abas", "goTo não conclui a rodada")

        // Pular para uma aba ainda sem resposta também é só navegação.
        let forward = send(.goTo(page: 2), to: &state)
        check(forward.isEmpty && state.page == 2, "goTo(2) vai direto à terceira pergunta")
        check(state.answers == answered, "pular uma aba não inventa resposta")
    }

    private static func testReturningToAnsweredSingleHighlightsTheAnswer() {
        let options = [option("A"), option("B"), option("C")]
        var state = AskState()
        send(.enqueue(request(id: "volta-simples", questions: [
            question("Q1", options: options), question("Q2")
        ])), to: &state)
        send(.submit(labels: ["C"], text: nil), to: &state)
        check(state.page == 1 && state.highlight == nil, "sem destaque antes de voltar")

        // Rascunho na página 1 não pode vazar para a pergunta respondida.
        send(.setText("rascunho"), to: &state)
        send(.goTo(page: 0), to: &state)
        check(state.highlight == 2, "voltar a uma simples respondida destaca a opção respondida")
        check(state.selected.isEmpty, "simples respondida não usa a seleção múltipla")
        check(state.text.isEmpty, "simples respondida por opção volta com o campo vazio")

        // Com destaque ativo na página de onde se sai, quem manda continua
        // sendo a opção respondida, não o índice anterior nem o zero.
        send(.goTo(page: 1), to: &state)
        send(.setHighlight(1), to: &state)
        send(.goTo(page: 0), to: &state)
        check(state.highlight == 2, "a opção respondida vence o destaque que vinha da outra aba")
    }

    private static func testReturningToAnsweredMultiRestoresSelection() {
        let title = "Várias"
        var state = AskState()
        send(.enqueue(request(id: "volta-multi", questions: [
            question(title, multiSelect: true, options: [option("A"), option("B"), option("C")]),
            question("Q2")
        ])), to: &state)
        send(.toggle(label: "A"), to: &state)
        send(.toggle(label: "B"), to: &state)
        send(.submit(labels: ["A", "B"], text: nil), to: &state)
        check(state.page == 1 && state.selected.isEmpty, "confirmar a múltipla limpa a seleção e avança")

        send(.goTo(page: 0), to: &state)
        check(state.selected == ["A", "B"], "voltar a uma múltipla respondida remarca as opções")
        check(state.text.isEmpty, "múltipla respondida por opções volta com o campo vazio")

        // Mexer sem confirmar não altera a resposta já dada.
        send(.toggle(label: "A"), to: &state)
        check(state.selected == ["B"], "a seleção restaurada continua editável")
        send(.goTo(page: 1), to: &state)
        check(state.selected.isEmpty, "a seleção da múltipla não vaza para a aba seguinte")
        check(state.answers[title] == AskAnswer(labels: ["A", "B"], text: nil),
              "mudança não confirmada não altera a resposta")
        send(.goTo(page: 0), to: &state)
        check(state.selected == ["A", "B"], "a volta seguinte mostra a resposta, não o rascunho")

        // Múltipla respondida com um rótulo só: quem mostra a resposta é a
        // marcação, o destaque segue a regra de qualquer troca de aba.
        var single = AskState()
        send(.enqueue(request(id: "volta-multi-um", questions: [
            question(title, multiSelect: true, options: [option("A"), option("B"), option("C")]),
            question("Q2")
        ])), to: &single)
        send(.submit(labels: ["C"], text: nil), to: &single)
        send(.goTo(page: 0), to: &single)
        check(single.selected == ["C"], "múltipla com um rótulo também volta marcada")
        check(single.highlight == nil, "sem destaque antes, a múltipla respondida volta sem destaque")
        send(.goTo(page: 1), to: &single)
        send(.setHighlight(1), to: &single)
        send(.goTo(page: 0), to: &single)
        check(single.highlight == 0, "com destaque antes, a múltipla respondida volta na primeira opção")
    }

    private static func testReturningToTextAnswerRestoresText() {
        var state = AskState()
        send(.enqueue(request(id: "volta-texto", questions: [
            question("Livre"), question("Q2")
        ])), to: &state)
        send(.submit(labels: [], text: "minha resposta"), to: &state)
        check(state.page == 1 && state.text.isEmpty, "enviar texto limpa o campo e avança")

        send(.goTo(page: 0), to: &state)
        check(state.text == "minha resposta", "voltar a uma respondida com texto traz o texto de volta")
        check(state.selected.isEmpty, "resposta de texto não marca opção")
        check(state.highlight == nil, "resposta de texto não destaca opção sozinha")

        send(.goTo(page: 1), to: &state)
        check(state.text.isEmpty, "o texto restaurado não vaza para a aba sem resposta")
    }

    private static func testAnsweringAgainReplacesTheAnswer() {
        var state = AskState()
        send(.enqueue(request(id: "de-novo", questions: [
            question("Q1"), question("Q2"), question("Q3")
        ])), to: &state)
        send(.submit(labels: ["A"], text: nil), to: &state)
        send(.submit(labels: ["A"], text: nil), to: &state)
        check(state.page == 2, "duas respostas em ordem param na terceira")

        send(.goTo(page: 0), to: &state)
        let again = send(.submit(labels: ["B"], text: nil), to: &state)
        check(again.isEmpty, "responder de novo com outra pendente não resolve")
        check(state.answers["Q1"] == AskAnswer(labels: ["B"], text: nil),
              "responder de novo substitui a resposta anterior")
        check(state.answers.count == 2, "responder de novo não cria resposta extra")
        check(state.page == 2, "depois de responder de novo, pula a já respondida e vai à pendente")

        // Texto por cima de opção também substitui, e a resposta final leva o novo valor.
        send(.goTo(page: 1), to: &state)
        send(.submit(labels: [], text: "outra coisa"), to: &state)
        check(state.page == 2, "a única pendente continua sendo a terceira")
        let effects = send(.submit(labels: ["A"], text: nil), to: &state)
        check(effects == [.resolve(id: "de-novo", answers: [
            "Q1": AskAnswer(labels: ["B"], text: nil),
            "Q2": AskAnswer(labels: [], text: "outra coisa"),
            "Q3": AskAnswer(labels: ["A"], text: nil)
        ])], "a rodada resolve com as respostas substituídas")
    }

    private static func testNextPendingWrapsAround() {
        var state = AskState()
        send(.enqueue(request(id: "volta-ao-inicio", questions: [
            question("Q1"), question("Q2"), question("Q3")
        ])), to: &state)
        send(.submit(labels: ["A"], text: nil), to: &state)
        send(.goTo(page: 2), to: &state)

        let third = send(.submit(labels: ["B"], text: nil), to: &state)
        check(third.isEmpty, "responder a última aba com uma pendente atrás não resolve")
        check(state.active?.id == "volta-ao-inicio", "a rodada segue ativa")
        check(state.page == 1, "depois da última aba, volta à única pendente")

        let second = send(.submit(labels: ["A"], text: nil), to: &state)
        check(second == [.resolve(id: "volta-ao-inicio", answers: [
            "Q1": AskAnswer(labels: ["A"], text: nil),
            "Q2": AskAnswer(labels: ["A"], text: nil),
            "Q3": AskAnswer(labels: ["B"], text: nil)
        ])], "responder a última pendente resolve com as três respostas")
        check(state.active == nil, "resolver limpa a pergunta ativa")
    }

    private static func testOutOfOrderLastPendingResolves() {
        var state = AskState()
        send(.enqueue(request(id: "fora-de-ordem", questions: [
            question("Q1"), question("Q2"), question("Q3")
        ])), to: &state)
        send(.goTo(page: 1), to: &state)
        check(send(.submit(labels: ["A"], text: nil), to: &state).isEmpty, "a 2ª não resolve")
        check(state.page == 2, "da 2ª vai à 3ª, a próxima pendente")
        check(send(.submit(labels: ["B"], text: nil), to: &state).isEmpty, "a 3ª não resolve")
        check(state.page == 0, "da 3ª volta à 1ª, a única pendente")

        let effects = send(.submit(labels: ["B"], text: nil), to: &state)
        check(effects == [.resolve(id: "fora-de-ordem", answers: [
            "Q1": AskAnswer(labels: ["B"], text: nil),
            "Q2": AskAnswer(labels: ["A"], text: nil),
            "Q3": AskAnswer(labels: ["B"], text: nil)
        ])], "responder a 1ª com as outras respondidas resolve na hora")
        check(state.active == nil, "resolver fora de ordem limpa a pergunta ativa")
    }

    private static func testSameQuestionTextCountsOnce() {
        let title = "Mesma pergunta"
        var state = AskState()
        send(.enqueue(request(id: "gemeas", questions: [
            question(title), question(title)
        ])), to: &state)

        let effects = send(.submit(labels: ["A"], text: nil), to: &state)
        check(effects == [.resolve(id: "gemeas", answers: [
            title: AskAnswer(labels: ["A"], text: nil)
        ])], "duas perguntas com o mesmo texto resolvem com uma resposta")
        check(state.active == nil, "a rodada das gêmeas termina")

        // A gêmea no fim também conta como respondida depois da do começo.
        var mixed = AskState()
        send(.enqueue(request(id: "gemeas-3", questions: [
            question(title), question("Outra"), question(title)
        ])), to: &mixed)
        check(send(.submit(labels: ["A"], text: nil), to: &mixed).isEmpty,
              "com uma pergunta diferente pendente a rodada não resolve")
        check(mixed.page == 1, "a pendente é a de texto diferente")
        let mixedEffects = send(.submit(labels: ["B"], text: nil), to: &mixed)
        check(mixedEffects == [.resolve(id: "gemeas-3", answers: [
            title: AskAnswer(labels: ["A"], text: nil),
            "Outra": AskAnswer(labels: ["B"], text: nil)
        ])], "a conta é por texto de pergunta, não por número de abas")
    }

    private static func testGoToOutOfRangeOrWithoutActiveIsNoOp() {
        var state = AskState()
        send(.enqueue(request(id: "limites", questions: [
            question("Q1"), question("Q2", multiSelect: true), question("Q3")
        ])), to: &state)
        send(.submit(labels: ["A"], text: nil), to: &state)
        send(.toggle(label: "A"), to: &state)
        send(.setText("rascunho"), to: &state)
        send(.setHighlight(1), to: &state)
        let before = state

        for page in [-1, 3, 99] {
            let effects = send(.goTo(page: page), to: &state)
            check(effects.isEmpty, "goTo(\(page)) fora do intervalo não emite efeito")
            check(state == before, "goTo(\(page)) fora do intervalo preserva o estado")
        }

        for page in [0, 1] {
            var empty = AskState()
            let effects = send(.goTo(page: page), to: &empty)
            check(effects.isEmpty && empty == AskState(),
                  "goTo(\(page)) sem pergunta ativa é no-op")
        }
    }

    private static func testUnconfirmedInputVanishesOnTabSwitch() {
        var state = AskState()
        send(.enqueue(request(id: "rascunho", questions: [
            question("Q1", multiSelect: true), question("Q2"), question("Q3")
        ])), to: &state)
        send(.toggle(label: "A"), to: &state)
        send(.setText("rascunho"), to: &state)
        check(state.selected == ["A"] && state.text == "rascunho", "há rascunho antes da troca")

        let effects = send(.goTo(page: 1), to: &state)
        check(effects.isEmpty, "trocar de aba com rascunho não emite efeito")
        check(state.page == 1, "a troca de aba acontece mesmo com rascunho")
        check(state.selected.isEmpty, "seleção não confirmada some na troca de aba")
        check(state.text.isEmpty, "texto não enviado some na troca de aba")
        check(state.answers.isEmpty, "rascunho não vira resposta")

        send(.goTo(page: 0), to: &state)
        check(state.selected.isEmpty && state.text.isEmpty,
              "o rascunho não reaparece ao voltar à pergunta sem resposta")
    }

    // MARK: - Destaque e escolha por número

    private static func testMoveHighlight() {
        let three = [option("A"), option("B"), option("C")]
        var state = AskState()
        send(.enqueue(request(id: "destaque", questions: [question("Q", options: three)])), to: &state)
        check(state.highlight == nil, "pergunta nova nasce sem destaque")
        var expected = state

        // Cada passo só pode mexer no destaque: nada de efeito, página ou resposta.
        func step(_ by: Int, _ index: Int, _ message: String) {
            let effects = send(.moveHighlight(by: by), to: &state)
            expected.highlight = index
            check(effects.isEmpty, "\(message) (sem efeito)")
            check(state == expected, message)
        }

        step(1, 0, "descer a partir de nenhum destaque vai para a primeira opção")
        step(-1, 0, "subir na primeira opção fica na primeira")
        step(1, 1, "descer anda uma opção")
        step(1, 2, "descer de novo chega à última")
        step(1, 2, "descer na última opção fica na última")
        step(-1, 1, "subir anda uma opção")

        var fromBottom = AskState()
        send(.enqueue(request(id: "de-baixo", questions: [question("Q", options: three)])), to: &fromBottom)
        send(.moveHighlight(by: -1), to: &fromBottom)
        check(fromBottom.highlight == 2, "subir a partir de nenhum destaque vai para a última opção")

        // A última é a da pergunta da aba atual, não a da primeira pergunta.
        var paged = AskState()
        send(.enqueue(request(id: "outra-aba", questions: [
            question("Q1"),
            question("Q2", options: [option("A"), option("B"), option("C"), option("D")])
        ])), to: &paged)
        send(.goTo(page: 1), to: &paged)
        send(.moveHighlight(by: -1), to: &paged)
        check(paged.highlight == 3, "a última opção é a da pergunta em tela")

        var empty = AskState()
        let effects = send(.moveHighlight(by: 1), to: &empty)
        check(effects.isEmpty && empty == AskState(), "mover destaque sem pergunta ativa é no-op")
    }

    private static func testSetHighlight() {
        var state = AskState()
        send(.enqueue(request(id: "apontar", questions: [question("Q")])), to: &state)

        send(.setHighlight(0), to: &state)
        check(state.highlight == 0, "setHighlight aponta a opção pedida")
        let before = state

        for index in [5, 2, -1] {
            let effects = send(.setHighlight(index), to: &state)
            check(effects.isEmpty, "setHighlight(\(index)) com 2 opções não emite efeito")
            check(state == before, "setHighlight(\(index)) com 2 opções é no-op")
        }

        send(.setHighlight(1), to: &state)
        check(state.highlight == 1, "setHighlight troca de opção")

        let cleared = send(.setHighlight(nil), to: &state)
        check(cleared.isEmpty && state.highlight == nil, "setHighlight(nil) limpa o destaque")
        check(state.active?.id == "apontar" && state.page == 0, "limpar o destaque não mexe no resto")

        var empty = AskState()
        send(.setHighlight(0), to: &empty)
        check(empty == AskState(), "setHighlight sem pergunta ativa é no-op")
    }

    private static func testChooseOutOfRangeIsNoOp() {
        for multiSelect in [false, true] {
            var state = AskState()
            send(.enqueue(request(id: "fora", questions: [
                question("Q1", multiSelect: multiSelect), question("Q2")
            ])), to: &state)
            send(.setHighlight(0), to: &state)
            let before = state

            for index in [-1, 2, 9] {
                let effects = send(.choose(index: index), to: &state)
                check(effects.isEmpty, "choose(\(index)) fora do intervalo não emite efeito")
                check(state == before, "choose(\(index)) fora do intervalo preserva o estado")
            }
        }

        var empty = AskState()
        let effects = send(.choose(index: 0), to: &empty)
        check(effects.isEmpty && empty == AskState(), "choose sem pergunta ativa é no-op")
    }

    private static func testChooseOnSingleEqualsSubmit() {
        let three = [option("A"), option("B"), option("C")]

        // Pergunta única: o número já resolve a rodada, com o rótulo daquele índice.
        for (index, label) in [(0, "A"), (1, "B"), (2, "C")] {
            var chosen = AskState()
            send(.enqueue(request(id: "numero", questions: [question("Q", options: three)])), to: &chosen)
            var submitted = chosen

            let chooseEffects = send(.choose(index: index), to: &chosen)
            let submitEffects = send(.submit(labels: [label], text: nil), to: &submitted)
            check(chooseEffects == [.resolve(id: "numero", answers: [
                "Q": AskAnswer(labels: [label], text: nil)
            ])], "choose(\(index)) em pergunta simples responde \(label)")
            check(chooseEffects == submitEffects && chosen == submitted,
                  "choose(\(index)) equivale a submit([\(label)])")
        }

        // Com mais perguntas e sem destaque: avança igual ao submit, sem criar destaque.
        var chosen = AskState()
        send(.enqueue(request(id: "numero-abas", questions: [
            question("Q1", options: three), question("Q2")
        ])), to: &chosen)
        var submitted = chosen
        let chooseEffects = send(.choose(index: 2), to: &chosen)
        let submitEffects = send(.submit(labels: ["C"], text: nil), to: &submitted)
        check(chooseEffects.isEmpty && chosen.page == 1, "choose em página intermediária avança")
        check(chosen.answers == ["Q1": AskAnswer(labels: ["C"], text: nil)],
              "choose em página intermediária grava a resposta")
        check(chosen.selected.isEmpty, "choose em pergunta simples não usa a seleção múltipla")
        check(chosen.highlight == nil, "escolher por número sem destaque não cria destaque na página seguinte")
        check(chooseEffects == submitEffects && chosen == submitted,
              "choose em página intermediária equivale ao submit")

        // Com destaque ativo a equivalência continua valendo.
        var chosenLit = AskState()
        send(.enqueue(request(id: "numero-destaque", questions: [
            question("Q1", options: three), question("Q2")
        ])), to: &chosenLit)
        send(.setHighlight(2), to: &chosenLit)
        var submittedLit = chosenLit
        send(.choose(index: 1), to: &chosenLit)
        send(.submit(labels: ["B"], text: nil), to: &submittedLit)
        check(chosenLit.answers == ["Q1": AskAnswer(labels: ["B"], text: nil)],
              "choose responde o índice pedido, não a opção destacada")
        check(chosenLit == submittedLit, "choose com destaque ativo equivale ao submit")
    }

    private static func testChooseOnMultiTogglesAndHighlights() {
        var state = AskState()
        send(.enqueue(request(id: "numero-multi", questions: [
            question("Várias", multiSelect: true, options: [option("A"), option("B"), option("C")]),
            question("Q2")
        ])), to: &state)

        let first = send(.choose(index: 1), to: &state)
        check(first.isEmpty, "choose em múltipla não emite efeito")
        check(state.selected == ["B"], "choose em múltipla marca a opção do índice")
        check(state.highlight == 1, "choose em múltipla deixa o destaque no índice")
        check(state.page == 0 && state.answers.isEmpty, "choose em múltipla não confirma a pergunta")

        send(.choose(index: 2), to: &state)
        check(state.selected == ["B", "C"], "choose em múltipla acumula opções")
        check(state.highlight == 2, "o destaque acompanha o último índice escolhido")

        let again = send(.choose(index: 1), to: &state)
        check(again.isEmpty, "desmarcar por número não emite efeito")
        check(state.selected == ["C"], "choose no mesmo índice desmarca a opção")
        check(state.highlight == 1, "desmarcar também deixa o destaque no índice")
        check(state.page == 0 && state.answers.isEmpty, "desmarcar não confirma a pergunta")
    }

    private static func testHighlightAcrossPageChange() {
        let three = [option("A"), option("B"), option("C")]
        let questions = [question("Q1", options: three), question("Q2"), question("Q3")]

        // Quem vinha navegando pelo teclado segue com destaque na página seguinte.
        var lit = AskState()
        send(.enqueue(request(id: "com-destaque", questions: questions)), to: &lit)
        send(.moveHighlight(by: -1), to: &lit)
        check(lit.highlight == 2, "destaque na última opção antes de responder")
        send(.submit(labels: ["C"], text: nil), to: &lit)
        check(lit.page == 1, "responder com destaque avança")
        check(lit.highlight == 0, "com destaque antes de responder, a página seguinte nasce na primeira opção")

        // Quem respondeu pelo mouse não ganha destaque do nada.
        var dark = AskState()
        send(.enqueue(request(id: "sem-destaque", questions: questions)), to: &dark)
        send(.submit(labels: ["C"], text: nil), to: &dark)
        check(dark.page == 1, "responder sem destaque avança")
        check(dark.highlight == nil, "sem destaque antes de responder, a página seguinte nasce sem destaque")

        // A mesma regra vale ao trocar de aba para uma pergunta sem resposta.
        send(.goTo(page: 2), to: &dark)
        check(dark.highlight == nil, "trocar de aba sem destaque continua sem destaque")
        send(.setHighlight(1), to: &dark)
        send(.goTo(page: 1), to: &dark)
        check(dark.highlight == 0, "trocar de aba com destaque cai na primeira opção da pergunta sem resposta")
    }

    private static func testPromotedRequestStartsWithoutHighlight() {
        // Resolver a ativa no meio de uma navegação por teclado.
        var state = AskState()
        send(.enqueue(request(id: "primeira", questions: [
            question("Q1"), question("Q2", multiSelect: true)
        ])), to: &state)
        send(.enqueue(request(id: "segunda", questions: [question("N1"), question("N2")])), to: &state)
        send(.setHighlight(1), to: &state)
        send(.submit(labels: ["B"], text: nil), to: &state)
        send(.choose(index: 1), to: &state)
        send(.setText("rascunho"), to: &state)
        check(state.page == 1 && state.highlight == 1 && state.selected == ["B"],
              "a primeira rodada está no meio, com destaque e seleção")

        let effects = send(.submit(labels: ["B"], text: nil), to: &state)
        check(effects == [.resolve(id: "primeira", answers: [
            "Q1": AskAnswer(labels: ["B"], text: nil),
            "Q2": AskAnswer(labels: ["B"], text: nil)
        ])], "a primeira rodada resolve")
        check(state.active?.id == "segunda", "a próxima da fila é promovida")
        check(state.page == 0, "a promovida nasce na página zero")
        check(state.highlight == nil, "a promovida nasce sem destaque")
        check(state.selected.isEmpty && state.text.isEmpty, "a promovida nasce sem seleção e sem texto")
        check(state.answers.isEmpty, "a promovida nasce sem respostas")

        // Cancelar a ativa com destaque.
        var cancelled = AskState()
        send(.enqueue(request(id: "um")), to: &cancelled)
        send(.enqueue(request(id: "dois")), to: &cancelled)
        send(.setHighlight(1), to: &cancelled)
        send(.cancelActive, to: &cancelled)
        check(cancelled.active?.id == "dois" && cancelled.highlight == nil,
              "a promovida depois de um cancelamento nasce sem destaque")

        // Destaque residual sem pergunta ativa não sobrevive à chegada de uma nova.
        var residual = AskState()
        residual.highlight = 1
        send(.enqueue(request(id: "nova")), to: &residual)
        check(residual.active?.id == "nova" && residual.highlight == nil,
              "pergunta nova limpa o destaque residual")
    }
}
