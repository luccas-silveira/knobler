//
//  CalendarCountdown.swift
//  Knobler
//
//  Próximo evento do calendário vira live activity: entra 15min antes,
//  anel esvazia até a hora, "agora" no início e some 1min depois.
//  EventKit com acesso completo (prompt na 1ª execução); negado = fica quieto.
//

import EventKit
import Foundation

final class CalendarCountdown {
    var onActivity: ((NotchActivity?) -> Void)?
    /// true enquanto uma reunião com link de call está a ≤2min de começar —
    /// borda de subida abre o espelho, de descida fecha (reunião começou).
    var onMirrorMoment: ((Bool) -> Void)?

    private let store = EKEventStore()
    private var timer: Timer?
    private let leadTime: TimeInterval = 15 * 60
    private let mirrorLead: TimeInterval = 2 * 60
    private let lingerAfterStart: TimeInterval = 60

    // ponytail: lista fixa de domínios de call; adicionar quando aparecer outro
    private static let callHosts = [
        "zoom.us", "meet.google.com", "teams.microsoft.com",
        "webex.com", "whereby.com", "meet.jit.si",
    ]

    private static func hasCallLink(_ event: EKEvent) -> Bool {
        let haystack = [event.url?.absoluteString, event.location, event.notes]
            .compactMap { $0 }
            .joined(separator: " ")
            .lowercased()
        return callHosts.contains { haystack.contains($0) }
    }

    func start() {
        store.requestFullAccessToEvents { [weak self] granted, _ in
            DispatchQueue.main.async {
                guard granted else {
                    NSLog("knobler calendar: acesso negado — countdown desligado")
                    return
                }
                self?.beginPolling()
            }
        }
    }

    private func beginPolling() {
        NotificationCenter.default.addObserver(
            self, selector: #selector(tick),
            name: .EKEventStoreChanged, object: store
        )
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            self?.tick()
        }
        tick()
    }

    @objc private func tick() {
        guard AppSettings.shared.calendarCountdown else {
            onActivity?(nil)
            onMirrorMoment?(false)
            return
        }

        let now = Date()
        let predicate = store.predicateForEvents(
            withStart: now.addingTimeInterval(-lingerAfterStart),
            end: now.addingTimeInterval(leadTime),
            calendars: nil
        )
        let next = store.events(matching: predicate)
            .filter { !$0.isAllDay }
            // só eventos que ainda não começaram (ou começaram há < 1min)
            .filter { $0.startDate.timeIntervalSince(now) > -self.lingerAfterStart }
            .min { $0.startDate < $1.startDate }

        guard let event = next else {
            onActivity?(nil)
            onMirrorMoment?(false)
            return
        }

        let remaining = event.startDate.timeIntervalSince(now)
        onMirrorMoment?(remaining > 0 && remaining <= mirrorLead && Self.hasCallLink(event))
        let minutes = Int(ceil(remaining / 60))
        let detail: String
        switch minutes {
        case ..<1: detail = "agora"
        case 1: detail = "em 1 min"
        default: detail = "em \(minutes) min"
        }

        onActivity?(NotchActivity(
            id: "calendar",
            title: event.title ?? "Evento",
            detail: detail,
            // anel esvazia conforme chega a hora (cheio a 15min, vazio no início)
            progress: max(0, min(1, remaining / leadTime)),
            updatedAt: Date()
        ))
    }
}
