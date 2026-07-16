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

    private let store = EKEventStore()
    private var timer: Timer?
    private let leadTime: TimeInterval = 15 * 60
    private let lingerAfterStart: TimeInterval = 60

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
            return
        }

        let remaining = event.startDate.timeIntervalSince(now)
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
