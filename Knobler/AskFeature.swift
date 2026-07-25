//
//  AskFeature.swift
//  Knobler
//
//  Estado e transições puras da feature AskUserQuestion.
//

struct AskState: Equatable {
    var active: AskRequest?
    var queue: [AskRequest] = []
    var page = 0
    var selected: Set<String> = []
    var answers: [String: AskAnswer] = [:]
    var text = ""

    init(active: AskRequest? = nil) {
        self.active = active
    }
}

enum AskAction: Equatable {
    case enqueue(AskRequest)
    case toggle(label: String)
    case submit(labels: [String], text: String?)
    case setText(String)
    case appendText(String)
    case cancelActive
    case resolve(id: String, answers: [String: AskAnswer])
    case cancel(id: String)
    case clear(id: String)
    case externalDismiss(id: String)
}

enum AskEffect: Equatable {
    case resolve(id: String, answers: [String: AskAnswer])
    case cancel(id: String)
}

enum AskReducer {
    /// Aplica uma ação de domínio e devolve efeitos para a camada de runtime.
    /// Não conhece UI, transporte HTTP ou o ciclo de vida do notch.
    static func reduce(state: inout AskState, action: AskAction) -> [AskEffect] {
        switch action {
        case .enqueue(let request):
            guard !request.id.isEmpty, !request.questions.isEmpty else { return [] }
            guard state.active?.id != request.id,
                  !state.queue.contains(where: { $0.id == request.id }) else {
                return []
            }

            if state.active == nil {
                promote(request, in: &state)
            } else {
                state.queue.append(request)
            }
            return []

        case .toggle(let label):
            guard let question = currentQuestion(in: state),
                  question.multiSelect,
                  question.options.contains(where: { $0.label == label }),
                  !label.isEmpty else {
                return []
            }

            if state.selected.contains(label) {
                state.selected.remove(label)
            } else {
                state.selected.insert(label)
            }
            return []

        case .submit(let labels, let submittedText):
            guard let active = state.active,
                  let question = currentQuestion(in: state) else {
                return []
            }

            let hasText = submittedText?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            guard !labels.isEmpty || hasText else {
                return []
            }
            guard labels.allSatisfy({ label in
                question.options.contains { $0.label == label }
            }) else {
                return []
            }
            guard question.multiSelect || labels.count <= 1 else {
                return []
            }

            let answer: AskAnswer
            if hasText, let submittedText {
                // Texto livre é a resposta explícita do campo e vence os chips.
                answer = AskAnswer(labels: [], text: submittedText)
            } else {
                answer = AskAnswer(labels: labels, text: nil)
            }
            state.answers[question.question] = answer
            state.selected.removeAll()
            state.text = ""

            if state.page + 1 < active.questions.count {
                state.page += 1
                return []
            }

            let answers = state.answers
            let id = active.id
            finishActive(in: &state)
            return [.resolve(id: id, answers: answers)]

        case .appendText(let appended):
            guard state.active != nil, !appended.isEmpty else { return [] }
            state.text = state.text.isEmpty ? appended : state.text + " " + appended
            return []

        case .setText(let text):
            guard state.active != nil else { return [] }
            state.text = text
            return []

        case .cancelActive:
            guard let active = state.active else { return [] }
            let id = active.id
            finishActive(in: &state)
            return [.cancel(id: id)]

        case .resolve(let id, let answers):
            guard state.active?.id == id, !answers.isEmpty else { return [] }
            finishActive(in: &state)
            return [.resolve(id: id, answers: answers)]

        case .cancel(let id):
            guard state.active?.id == id else { return [] }
            finishActive(in: &state)
            return [.cancel(id: id)]

        case .clear(let id), .externalDismiss(let id):
            guard !id.isEmpty else { return [] }
            state.queue.removeAll { $0.id == id }
            guard state.active?.id == id else { return [] }
            finishActive(in: &state)
            return []
        }
    }

    private static func currentQuestion(in state: AskState) -> AskQuestion? {
        guard let active = state.active,
              active.questions.indices.contains(state.page) else {
            return nil
        }
        return active.questions[state.page]
    }

    /// Promoção é imediata no domínio; qualquer respiro de animação pertence à UI.
    private static func promote(_ request: AskRequest, in state: inout AskState) {
        state.active = request
        resetInputs(in: &state)
    }

    private static func finishActive(in state: inout AskState) {
        state.active = nil
        resetInputs(in: &state)
        guard !state.queue.isEmpty else { return }
        promote(state.queue.removeFirst(), in: &state)
    }

    private static func resetInputs(in state: inout AskState) {
        state.page = 0
        state.selected.removeAll()
        state.answers.removeAll()
        state.text = ""
    }
}
