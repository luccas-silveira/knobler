//
//  AskStore.swift
//  Knobler
//
//  Runtime observável da feature AskUserQuestion.
//

import Foundation
import Observation

@MainActor
@Observable
final class AskStore {
    private(set) var state = AskState()

    struct Dependencies {
        var resolve: @Sendable (String, [String: AskAnswer]) async -> Void
        var cancel: @Sendable (String) async -> Void
    }

    let dependencies: Dependencies

    init(dependencies: Dependencies) {
        self.dependencies = dependencies
    }

    /// Aplica a ação imediatamente e agenda seus efeitos fora do caminho de UI.
    func send(_ action: AskAction) {
        let effects = AskReducer.reduce(state: &state, action: action)

        for effect in effects {
            switch effect {
            case let .resolve(id, answers):
                let resolve = dependencies.resolve
                Task {
                    await resolve(id, answers)
                }

            case let .cancel(id):
                let cancel = dependencies.cancel
                Task {
                    await cancel(id)
                }
            }
        }
    }
}
