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
        testTextWinsLabels()
        testInvalidSubmissionsAreNoOp()
        testPagedSubmissionPreservesPreviousAnswers()
        testLastPageResolvesAllAnswers()
        testCancellationIsIdempotent()
        testLegacyCompletionActions()
        testClearRemovesActiveOrQueuedRequest()
        testNextRequestIsPromoted()
        testExternalDismiss()

        print("ask feature self-check ok")
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
        send(.enqueue(request(id: "append", questions: [question("Texto")])), to: &state)

        send(.appendText("primeiro"), to: &state)
        send(.appendText("segundo"), to: &state)
        check(state.text == "primeiro segundo", "appendText concatena trechos com espaço")

        var emptyState = AskState()
        send(.appendText("fora"), to: &emptyState)
        check(emptyState.text.isEmpty, "appendText sem pergunta ativa é no-op")
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
}
