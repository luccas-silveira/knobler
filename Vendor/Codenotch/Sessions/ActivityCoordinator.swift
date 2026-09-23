import Combine
import Foundation

/// Owns session-monitor lifetimes so disconnected providers neither scan for
/// sessions nor keep usage refreshes in the fast, busy cadence.
@MainActor
final class ActivityCoordinator {
    private let monitors: [String: any AgentActivityMonitor]
    private let onSessions: (String, [AgentSession]) -> Void
    private var subscriptions: [String: AnyCancellable] = [:]
    private(set) var activeIDs: Set<String> = []

    init(monitors: [String: any AgentActivityMonitor],
         onSessions: @escaping (String, [AgentSession]) -> Void) {
        self.monitors = monitors
        self.onSessions = onSessions
    }

    var isBusy: Bool {
        activeIDs.contains { id in
            monitors[id]?.sessions.contains { $0.state == .busy } == true
        }
    }

    func setEnabled(_ enabled: Set<String>) {
        let wanted = enabled.intersection(monitors.keys)
        for id in activeIDs.subtracting(wanted) {
            activeIDs.remove(id)
            subscriptions.removeValue(forKey: id)?.cancel()
            monitors[id]?.stop()
            onSessions(id, [])
        }
        for id in wanted.subtracting(activeIDs) {
            guard let monitor = monitors[id] else { continue }
            activeIDs.insert(id)
            subscriptions[id] = monitor.sessionsPublisher
                .receive(on: RunLoop.main)
                .sink { [weak self] sessions in
                    guard let self, self.activeIDs.contains(id) else { return }
                    self.onSessions(id, sessions)
                }
            monitor.start()
        }
    }

    func stop() { setEnabled([]) }
}
