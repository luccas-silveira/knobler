// Self-check for the shared AgentRequest reducer. Not part of the app target.
//
// xcrun swiftc -parse-as-library -swift-version 5 \
//   Knobler/AgentRequestModels.swift Knobler/AgentRequestStore.swift \
//   tools/agentrequestcheck.swift -o /tmp/agentrequestcheck && /tmp/agentrequestcheck

import Foundation

@main
struct AgentRequestCheck {
    static func main() {
        testEnqueueAndFIFO()
        testResolvePromotesAndFirstResponseWins()
        testDismissAndExpire()
        testDuplicateIDsAreNoOps()
        print("agentrequestcheck: OK")
    }

    private static func request(_ id: String) -> AgentRequest {
        AgentRequest(
            id: id,
            agent: .claude,
            kind: .permission,
            title: "Permission",
            summary: "Read a file",
            details: nil,
            source: .terminal,
            actions: [.allow, .deny, .cancel]
        )
    }

    private static func send(_ action: AgentRequestReducer.Action, _ state: inout AgentRequestState) {
        AgentRequestReducer.reduce(state: &state, action: action)
    }

    private static func check(_ condition: @autoclosure () -> Bool, _ message: String) {
        precondition(condition(), message)
    }

    private static func testEnqueueAndFIFO() {
        var state = AgentRequestState()
        send(.enqueue(request("first")), &state)
        send(.enqueue(request("second")), &state)
        send(.enqueue(request("third")), &state)

        check(state.active?.id == "first", "first request becomes active")
        check(state.queue.map(\.id) == ["second", "third"], "remaining requests stay FIFO")
    }

    private static func testResolvePromotesAndFirstResponseWins() {
        var state = AgentRequestState()
        send(.enqueue(request("first")), &state)
        send(.enqueue(request("second")), &state)

        send(.resolve(id: "first", action: .allow, responder: .terminal), &state)
        check(state.active?.id == "second", "resolution promotes the next request synchronously")
        check(state.results["first"] == AgentRequestResult(action: .allow, responder: .terminal), "terminal response is recorded")

        let afterTerminal = state
        send(.resolve(id: "first", action: .deny, responder: .nob), &state)
        check(state == afterTerminal, "NOB loses when terminal answered first")
    }

    private static func testDismissAndExpire() {
        var state = AgentRequestState()
        send(.enqueue(request("first")), &state)
        send(.enqueue(request("second")), &state)
        send(.dismiss(id: "first"), &state)
        check(state.active?.id == "second", "dismissal promotes the next request")
        check(state.results["first"] == AgentRequestResult(action: .cancel, responder: .nob, state: .dismissed), "dismissal is a cancel result")

        send(.expire(id: "second"), &state)
        check(state.active == nil, "expiry clears the active request")
        check(state.results["second"] == AgentRequestResult(action: .cancel, responder: .system, state: .expired), "expiry is never an allow result")
    }

    private static func testDuplicateIDsAreNoOps() {
        var state = AgentRequestState()
        send(.enqueue(request("first")), &state)
        send(.enqueue(request("first")), &state)
        check(state.active?.id == "first" && state.queue.isEmpty, "active duplicate does not enqueue")

        send(.enqueue(request("second")), &state)
        send(.enqueue(request("second")), &state)
        check(state.queue.map(\.id) == ["second"], "queued duplicate does not enqueue")
    }
}
