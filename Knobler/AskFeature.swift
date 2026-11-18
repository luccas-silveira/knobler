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
    /// Opção sob o cursor do teclado na pergunta em tela; `nil` quando ninguém navegou.
    var highlight: Int?

    init(active: AskRequest? = nil) {
        self.active = active
    }
}

enum AskAction: Equatable {
    case enqueue(AskRequest)
    case toggle(label: String)
    case submit(labels: [String], text: String?)
    case setText(String)
    case appendText(id: String, text: String)
    case cancelActive
    case resolve(id: String, answers: [String: AskAnswer])
    case cancel(id: String)
    case clear(id: String)
    case externalDismiss(id: String)
    case goTo(page: Int)
    case moveHighlight(by: Int)
    case setHighlight(Int?)
    case choose(index: Int)
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
            toggle(label, in: &state)
            return []

        case .submit(let labels, let submittedText):
            return submit(labels: labels, text: submittedText, in: &state)

        case .appendText(let id, let appended):
            guard state.active?.id == id, !appended.isEmpty else { return [] }
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

        case .goTo(let page):
            guard let active = state.active,
                  active.questions.indices.contains(page) else {
                return []
            }
            entrar(pagina: page, in: &state, mantendoDestaque: state.highlight != nil)
            return []

        case .moveHighlight(let by):
            guard let question = currentQuestion(in: state),
                  !question.options.isEmpty else {
                return []
            }
            let last = question.options.count - 1
            if let current = state.highlight {
                state.highlight = min(max(current + by, 0), last)
            } else {
                state.highlight = by > 0 ? 0 : last
            }
            return []

        case .setHighlight(let index):
            guard let index else {
                state.highlight = nil
                return []
            }
            guard let question = currentQuestion(in: state),
                  question.options.indices.contains(index) else {
                return []
            }
            state.highlight = index
            return []

        case .choose(let index):
            guard let question = currentQuestion(in: state),
                  question.options.indices.contains(index) else {
                return []
            }
            let label = question.options[index].label
            guard question.multiSelect else {
                return submit(labels: [label], text: nil, in: &state)
            }
            toggle(label, in: &state)
            state.highlight = index
            return []
        }
    }

    private static func toggle(_ label: String, in state: inout AskState) {
        guard let question = currentQuestion(in: state),
              question.multiSelect,
              question.options.contains(where: { $0.label == label }),
              !label.isEmpty else {
            return
        }

        if state.selected.contains(label) {
            state.selected.remove(label)
        } else {
            state.selected.insert(label)
        }
    }

    private static func submit(labels: [String], text submittedText: String?, in state: inout AskState) -> [AskEffect] {
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
        // Lido antes de limpar: quem vinha pelo teclado segue com destaque na próxima.
        let tinhaDestaque = state.highlight != nil
        state.answers[question.question] = answer
        state.selected.removeAll()
        state.text = ""

        // Próxima pendente a partir da página atual, dando a volta. A conta é por
        // texto de pergunta: duas perguntas iguais dividem a mesma resposta.
        let count = active.questions.count
        for passo in 1...count {
            let p = (state.page + passo) % count
            if state.answers[active.questions[p].question] == nil {
                entrar(pagina: p, in: &state, mantendoDestaque: tinhaDestaque)
                return []
            }
        }

        let answers = state.answers
        let id = active.id
        finishActive(in: &state)
        return [.resolve(id: id, answers: answers)]
    }

    /// Troca a pergunta em tela. Rascunho não confirmado some; pergunta já
    /// respondida volta mostrando a resposta dada.
    private static func entrar(pagina: Int, in state: inout AskState, mantendoDestaque: Bool) {
        guard let active = state.active,
              active.questions.indices.contains(pagina) else {
            return
        }
        let pergunta = active.questions[pagina]
        state.page = pagina
        state.selected.removeAll()
        state.text = ""
        state.highlight = mantendoDestaque ? 0 : nil

        guard let resposta = state.answers[pergunta.question] else { return }
        state.text = resposta.text ?? ""
        if pergunta.multiSelect {
            state.selected = Set(resposta.labels)
        } else if resposta.labels.count == 1,
                  let indice = pergunta.options.firstIndex(where: { $0.label == resposta.labels[0] }) {
            state.highlight = indice
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
        state.highlight = nil
    }
}
