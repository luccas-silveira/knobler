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
        testTextWinsLabels()
        testPagedSubmissionPreservesPreviousAnswers()
        testLastPageResolvesAllAnswers()
        testCancellationIsIdempotent()
        testClearRemovesActiveOrQueuedRequest()
        testNextRequestIsPromoted()

        print("ask feature self-check ok")
    }

    // MARK: - Helpers

    private static func send(_ action: AskAction, to state: inout AskState) -> [AskEffect] {
        AskReducer.reduce(state: &state, action: action)
    }

    private static func option(_ label: String) -> AskOption {
        AskOption(label: label, description: "", preview: nil)
    }

    private static func request(
        id: String,
        questions: [AskQuestion] = [],
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

        assert(state.active?.id == "first", "a primeira pergunta recebida fica ativa")
        assert(state.queue.map(\.id) == ["second", "third"], "as perguntas seguintes entram em FIFO")

        // A mesma ID não pode duplicar nem a pergunta ativa nem a fila.
        send(.enqueue(first), to: &state)
        send(.enqueue(second), to: &state)
        assert(state.active?.id == "first", "ID ativa duplicada não troca a pergunta")
        assert(state.queue.map(\.id) == ["second", "third"], "ID enfileirada duplicada não cria cópia")
    }

    private static func testNewQuestionStartsAtZero() {
        var state = AskState()
        state.page = 2
        state.selected = ["resíduo"]
        state.answers = ["antiga": AskAnswer(labels: ["A"], text: nil)]
        state.text = "texto residual"

        let incoming = request(id: "fresh", questions: [question("Nova")])
        send(.enqueue(incoming), to: &state)

        assert(state.active == incoming, "a nova pergunta vira ativa")
        assert(state.page == 0, "pergunta nova começa na página zero")
        assert(state.selected.isEmpty, "promoção limpa a seleção anterior")
        assert(state.answers.isEmpty, "promoção limpa as respostas anteriores")
        assert(state.text.isEmpty, "promoção limpa o texto anterior")
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
        assert(state.selected == ["A"], "multi-select adiciona o label")

        send(.toggle(label: "B"), to: &state)
        assert(state.selected == ["A", "B"], "multi-select permite vários labels")

        send(.toggle(label: "A"), to: &state)
        assert(state.selected == ["B"], "multi-select alterna o label selecionado")

        // Uma pergunta simples não aceita toggle como se fosse multi-select.
        var singleState = AskState()
        send(.enqueue(request(id: "single", questions: [question("Escolha uma")])), to: &singleState)
        send(.toggle(label: "A"), to: &singleState)
        assert(singleState.selected.isEmpty, "toggle não seleciona uma pergunta simples")
    }

    private static func testTextWinsLabels() {
        var state = AskState()
        let title = "Resposta livre"
        send(.enqueue(request(id: "text", questions: [question(title, multiSelect: true)])), to: &state)

        let effects = send(.submit(labels: ["A"], text: "Resposta digitada"), to: &state)
        assert(effects.count == 1, "submissão textual produz um resolve")
        guard case .resolve(_, let answers) = effects[0] else {
            assertionFailure("submissão textual deve produzir AskEffect.resolve")
            return
        }
        assert(answers[title] == AskAnswer(labels: [], text: "Resposta digitada"),
               "texto livre vence labels quando o card envia texto")
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
        assert(firstEffects.isEmpty, "página intermediária ainda não resolve o Ask")
        assert(state.page == 1, "submissão intermediária avança uma página")
        assert(state.answers[firstTitle] == AskAnswer(labels: ["A"], text: nil),
               "submissão intermediária preserva a resposta anterior")
        assert(state.selected.isEmpty && state.text.isEmpty,
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
        assert(effects == [.resolve(id: "resolve-all", answers: expected)],
               "última página produz todas as respostas")
        assert(state.active == nil, "resolve limpa a pergunta ativa")

        let repeated = send(.submit(labels: ["B"], text: nil), to: &state)
        assert(repeated.isEmpty, "resposta repetida depois de resolve é no-op")
    }

    // MARK: - Invariantes de conclusão e limpeza

    private static func testCancellationIsIdempotent() {
        var state = AskState()
        send(.enqueue(request(id: "cancel", questions: [question("Cancelar")])), to: &state)

        let first = send(.cancelActive, to: &state)
        assert(first == [.cancel(id: "cancel")], "cancelamento emite um único efeito cancel")
        assert(state.active == nil, "cancelamento limpa a pergunta ativa")

        let second = send(.cancelActive, to: &state)
        assert(second.isEmpty, "cancelamento repetido é no-op")

        // Uma submissão depois de concluir também não pode emitir resposta de novo.
        let repeatedSubmit = send(.submit(labels: ["A"], text: nil), to: &state)
        assert(repeatedSubmit.isEmpty, "resposta repetida sem pergunta ativa é no-op")
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
        assert(queuedClearEffects.isEmpty, "clear de pergunta enfileirada não emite efeito")
        assert(state.queue.map(\.id) == ["remaining"], "clear remove uma pergunta enfileirada")

        let activeClearEffects = send(.clear(id: "active"), to: &state)
        assert(activeClearEffects.isEmpty, "clear da pergunta ativa não emite efeito")
        assert(state.active?.id == "remaining", "clear remove a ativa e promove a próxima")
        assert(state.queue.isEmpty, "a fila fica vazia após promover a única pendente")
    }

    private static func testNextRequestIsPromoted() {
        var state = AskState()
        let first = request(id: "one")
        let second = request(id: "two")
        send(.enqueue(first), to: &state)
        send(.enqueue(second), to: &state)

        let effects = send(.cancelActive, to: &state)
        assert(effects == [.cancel(id: "one")], "conclusão da ativa emite o efeito correto")
        assert(state.active?.id == "two", "a próxima pergunta é promovida após concluir a atual")
        assert(state.page == 0, "a pergunta promovida começa na página zero")
    }
}
