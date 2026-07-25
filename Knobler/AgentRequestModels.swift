//
//  AgentRequestModels.swift
//  Knobler
//
//  Shared domain for mirrored Claude and Codex requests.
//

import Foundation

enum AgentName: String, Codable, Equatable {
    case claude
    case codex
}

enum AgentRequestKind: String, Codable, Equatable {
    case question
    case permission
}

enum AgentRequestSource: String, Codable, Equatable {
    case terminal
    case cli
    case ide
}

enum AgentRequestStatus: String, Codable, Equatable {
    case pending
    case resolved
    case dismissed
    case expired
}

enum AgentRequestAction: Equatable, Codable {
    case allow
    case allowForSession
    case deny
    case cancel
    case option(String)
    case text(String)

    private enum CodingKeys: String, CodingKey { case action, value }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(String.self, forKey: .action) {
        case "allow": self = .allow
        case "allowForSession": self = .allowForSession
        case "deny": self = .deny
        case "cancel": self = .cancel
        case "option": self = .option(try container.decode(String.self, forKey: .value))
        case "text": self = .text(try container.decode(String.self, forKey: .value))
        default: throw DecodingError.dataCorruptedError(forKey: .action, in: container, debugDescription: "Unknown agent request action")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .allow: try container.encode("allow", forKey: .action)
        case .allowForSession: try container.encode("allowForSession", forKey: .action)
        case .deny: try container.encode("deny", forKey: .action)
        case .cancel: try container.encode("cancel", forKey: .action)
        case .option(let value):
            try container.encode("option", forKey: .action)
            try container.encode(value, forKey: .value)
        case .text(let value):
            try container.encode("text", forKey: .action)
            try container.encode(value, forKey: .value)
        }
    }
}

enum AgentRequestResponder: String, Codable, Equatable {
    case nob
    case terminal
    case system
}

struct AgentRequestResult: Codable, Equatable {
    var action: AgentRequestAction
    var responder: AgentRequestResponder
    var state: AgentRequestStatus

    init(action: AgentRequestAction, responder: AgentRequestResponder, state: AgentRequestStatus = .resolved) {
        self.action = action
        self.responder = responder
        self.state = state
    }
}

struct AgentRequest: Codable, Equatable {
    var id: String
    var agent: AgentName
    var kind: AgentRequestKind
    var title: String
    var summary: String
    var details: String?
    var source: AgentRequestSource
    var actions: [AgentRequestAction]
    var state: AgentRequestStatus

    init(
        id: String,
        agent: AgentName,
        kind: AgentRequestKind,
        title: String,
        summary: String,
        details: String? = nil,
        source: AgentRequestSource,
        actions: [AgentRequestAction],
        state: AgentRequestStatus = .pending
    ) {
        self.id = id
        self.agent = agent
        self.kind = kind
        self.title = title
        self.summary = summary
        self.details = details
        self.source = source
        self.actions = actions
        self.state = state
    }
}

struct AgentRequestState: Equatable {
    var active: AgentRequest?
    var queue: [AgentRequest]
    var results: [String: AgentRequestResult]

    init(active: AgentRequest? = nil, queue: [AgentRequest] = [], results: [String: AgentRequestResult] = [:]) {
        self.active = active
        self.queue = queue
        self.results = results
    }
}

enum AgentRequestReducer {
    enum Action: Equatable {
        case enqueue(AgentRequest)
        case resolve(id: String, action: AgentRequestAction, responder: AgentRequestResponder)
        case dismiss(id: String)
        case expire(id: String)
    }

    enum Effect: Equatable {
        case resolveRemote(id: String, action: AgentRequestAction)
        case dismissRemote(id: String)
    }

    @discardableResult
    static func reduce(state: inout AgentRequestState, action: Action) -> [Effect] {
        switch action {
        case .enqueue(let request):
            guard request.id.isEmpty == false,
                  request.state == .pending,
                  request.actions.isEmpty == false,
                  !contains(request.id, in: state) else { return [] }
            if state.active == nil {
                state.active = request
            } else {
                state.queue.append(request)
            }
            return []

        case let .resolve(id, action, responder):
            guard let active = state.active,
                  active.id == id,
                  active.actions.contains(action) else { return [] }
            state.results[id] = AgentRequestResult(action: action, responder: responder)
            finishActive(in: &state)
            return responder == .nob ? [.resolveRemote(id: id, action: action)] : []

        case .dismiss(let id):
            guard state.active?.id == id else { return [] }
            state.results[id] = AgentRequestResult(action: .cancel, responder: .nob, state: .dismissed)
            finishActive(in: &state)
            return [.dismissRemote(id: id)]

        case .expire(let id):
            if state.active?.id == id {
                state.results[id] = AgentRequestResult(action: .cancel, responder: .system, state: .expired)
                finishActive(in: &state)
                return []
            }
            guard let index = state.queue.firstIndex(where: { $0.id == id }) else { return [] }
            state.queue.remove(at: index)
            state.results[id] = AgentRequestResult(action: .cancel, responder: .system, state: .expired)
            return []
        }
    }

    private static func contains(_ id: String, in state: AgentRequestState) -> Bool {
        state.active?.id == id || state.queue.contains(where: { $0.id == id }) || state.results[id] != nil
    }

    private static func finishActive(in state: inout AgentRequestState) {
        state.active = state.queue.isEmpty ? nil : state.queue.removeFirst()
    }
}
