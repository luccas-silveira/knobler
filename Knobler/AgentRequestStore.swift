//
//  AgentRequestStore.swift
//  Knobler
//

import Combine

@MainActor
final class AgentRequestStore: ObservableObject {
    @Published private(set) var state = AgentRequestState()

    let resolveRemote: @Sendable (String, AgentRequestAction) async -> Void
    let dismissRemote: @Sendable (String) async -> Void

    init(
        resolveRemote: @escaping @Sendable (String, AgentRequestAction) async -> Void = { _, _ in },
        dismissRemote: @escaping @Sendable (String) async -> Void = { _ in }
    ) {
        self.resolveRemote = resolveRemote
        self.dismissRemote = dismissRemote
    }

    func send(_ action: AgentRequestReducer.Action) {
        for effect in AgentRequestReducer.reduce(state: &state, action: action) {
            switch effect {
            case let .resolveRemote(id, response):
                let resolveRemote = resolveRemote
                Task { await resolveRemote(id, response) }
            case let .dismissRemote(id):
                let dismissRemote = dismissRemote
                Task { await dismissRemote(id) }
            }
        }
    }

    /// A API é a autoridade da corrida. O estado local só muda quando o
    /// callback `onAgentRequestResolved` devolve o vencedor.
    func resolve(id: String, action: AgentRequestAction) {
        let resolveRemote = resolveRemote
        Task { await resolveRemote(id, action) }
    }

    func dismiss(id: String) {
        let dismissRemote = dismissRemote
        Task { await dismissRemote(id) }
    }
}
