//
//  CalendarCountdown.swift
//  Knobler
//
//  Próximo evento do calendário vira live activity: entra 15min antes,
//  anel esvazia até a hora, "agora" no início e some 1min depois.
//  EventKit com acesso completo. NÃO pede a permissão: espera a concessão que
//  vem do painel Permissões; sem ela, fica quieto.
//

import EventKit
import Foundation

final class CalendarCountdown {
    var onActivity: ((NotchActivity?) -> Void)?
    /// Mesmo evento do `onActivity`, cru — o card do Pomodoro suprime a seção de
    /// atividade e precisa da informação por fora dela.
    var onNextEvent: ((CalendarAviso?) -> Void)?
    /// true enquanto uma reunião com link de call está a ≤2min de começar —
    /// borda de subida abre o espelho, de descida fecha (reunião começou).
    var onMirrorMoment: ((Bool) -> Void)?
    /// true enquanto uma reunião com link de call está **acontecendo** (entre
    /// início e fim). Diferente do `onMirrorMoment`, que é o instante anterior.
    var onMeeting: ((Bool) -> Void)?

    private let store = EKEventStore()
    private var timer: Timer?
    /// Repolla o status enquanto a permissão não vem (ver `start()`).
    private var aguardando: Timer?
    private let leadTime: TimeInterval = 15 * 60
    private let mirrorLead: TimeInterval = 2 * 60
    private let lingerAfterStart: TimeInterval = 60

    // ponytail: lista fixa de domínios de call; adicionar quando aparecer outro
    private static let callHosts = [
        "zoom.us", "meet.google.com", "teams.microsoft.com",
        "webex.com", "whereby.com", "meet.jit.si",
    ]

    /// Reunião acontecendo agora — a regra em si vive em
    /// `NotificationRules.silenciaOChat`, que é testável.
    ///
    /// Recusado como sinal: microfone em uso. O ditado do próprio Knobler o
    /// acende, e o notch silenciaria toda vez que você falasse.
    private func emReuniao(at now: Date) -> Bool {
        let predicate = store.predicateForEvents(withStart: now, end: now, calendars: nil)
        return store.events(matching: predicate).contains { event in
            NotificationRules.silenciaOChat(
                isAllDay: event.isAllDay,
                start: event.startDate,
                end: event.endDate,
                temLinkDeCall: Self.hasCallLink(event),
                agora: now)
        }
    }

    private static func hasCallLink(_ event: EKEvent) -> Bool {
        let haystack = [event.url?.absoluteString, event.location, event.notes]
            .compactMap { $0 }
            .joined(separator: " ")
            .lowercased()
        return callHosts.contains { haystack.contains($0) }
    }

    /// **Não pede permissão.** Pedir aqui punha o balão do Calendário na tela no
    /// launch, por cima da janela de boas-vindas — e contra a regra do app, que
    /// é pedir no primeiro uso. Quem pede é o painel Permissões
    /// (`Permission.request`); aqui só esperamos a concessão chegar.
    func start() {
        guard EKEventStore.authorizationStatus(for: .event) != .fullAccess else {
            beginPolling()
            return
        }
        // Mesmo molde dos consumidores de Acessibilidade: repolla o status e se
        // liga sozinho quando o usuário concede, sem relaunch. Sem callback, que
        // o EventKit só dá a quem pede.
        aguardando = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] t in
            guard EKEventStore.authorizationStatus(for: .event) == .fullAccess else { return }
            t.invalidate()
            self?.aguardando = nil
            self?.beginPolling()
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
            onNextEvent?(nil)
            onMirrorMoment?(false)
            onMeeting?(false)
            return
        }

        let now = Date()
        onMeeting?(emReuniao(at: now))
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
            onNextEvent?(nil)
            onMirrorMoment?(false)
            return
        }
        // o onMeeting já foi publicado acima: ele não depende de haver evento
        // *próximo*, e sim de haver um em curso — sair aqui não pode calá-lo

        let remaining = event.startDate.timeIntervalSince(now)
        onMirrorMoment?(remaining > 0 && remaining <= mirrorLead && Self.hasCallLink(event))
        let aviso = CalendarAviso(titulo: event.title ?? "Evento", faltam: remaining)
        onNextEvent?(aviso)

        onActivity?(NotchActivity(
            id: "calendar",
            title: aviso.titulo,
            detail: aviso.quando,
            // anel esvazia conforme chega a hora (cheio a 15min, vazio no início)
            progress: max(0, min(1, remaining / leadTime)),
            updatedAt: Date()
        ))
    }
}
