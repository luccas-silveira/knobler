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
    var onAgendaChanged: (() -> Void)?
    /// true enquanto uma reunião com link de call está a ≤2min de começar —
    /// borda de subida abre o espelho, de descida fecha (reunião começou).
    var onMirrorMoment: ((Bool) -> Void)?
    /// true enquanto uma reunião com link de call está **acontecendo** (entre
    /// início e fim). Diferente do `onMirrorMoment`, que é o instante anterior.
    var onMeeting: ((Bool) -> Void)?

    private let store = EKEventStore()
    private var timer: Timer?
    private var observer: NSObjectProtocol?
    private var ultimoAcesso = false
    private var ultimaConsulta = Date.distantPast
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

    /// Não pede permissão no lançamento. O status é leve; eventos só são
    /// consultados a cada 30 s, numa mudança do store ou na navegação da agenda.
    func start() {
        guard timer == nil else { return }
        observer = NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged, object: store, queue: .main
        ) { [weak self] _ in self?.tick() }
        timer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            guard let self else { return }
            let acesso = EKEventStore.authorizationStatus(for: .event) == .fullAccess
            if acesso != self.ultimoAcesso || Date().timeIntervalSince(self.ultimaConsulta) >= 30 {
                self.tick()
            }
        }
        tick()
    }

    deinit {
        timer?.invalidate()
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }

    func agenda(no dia: Date, agora: Date = Date()) -> CalendarAgenda {
        let autorizado = EKEventStore.authorizationStatus(for: .event) == .fullAccess
        var resultado = CalendarAgenda(dia: Calendar.current.startOfDay(for: dia),
                                        atualizadoEm: agora, autorizado: autorizado)
        guard autorizado,
              let intervalo = Calendar.current.dateInterval(of: .day, for: dia) else { return resultado }
        let predicate = store.predicateForEvents(withStart: intervalo.start,
                                                 end: intervalo.end, calendars: nil)
        let eventos = store.events(matching: predicate).filter { $0.status != .canceled }.map {
            CalendarEvento(id: "\($0.calendarItemIdentifier)/\($0.startDate.timeIntervalSinceReferenceDate)",
                           titulo: $0.title?.isEmpty == false ? $0.title : "Evento",
                           calendario: $0.calendar.title, inicio: $0.startDate,
                           fim: $0.endDate, diaInteiro: $0.isAllDay)
        }
        resultado.eventos = CalendarAgenda.eventosDoDia(eventos, dia: dia)
        return resultado
    }

    func calendariosEditaveis() -> [CalendarDestino] {
        guard EKEventStore.authorizationStatus(for: .event) == .fullAccess else { return [] }
        let padrao = store.defaultCalendarForNewEvents?.calendarIdentifier
        return store.calendars(for: .event).filter(\.allowsContentModifications).map {
            CalendarDestino(id: $0.calendarIdentifier, nome: $0.title,
                            conta: $0.source.title, padrao: $0.calendarIdentifier == padrao)
        }.sorted { $0.rotulo.localizedStandardCompare($1.rotulo) == .orderedAscending }
    }

    /// A única escrita no calendário: chamada exclusivamente pelo botão Salvar.
    func criarEvento(_ rascunho: CalendarRascunho) throws -> Date {
        try rascunho.validar(
            autorizado: EKEventStore.authorizationStatus(for: .event) == .fullAccess,
            destinos: calendariosEditaveis())
        guard let destino = store.calendar(withIdentifier: rascunho.calendarioID),
              destino.allowsContentModifications else { throw CalendarErro.calendario }
        let intervalo = try rascunho.intervalo()
        let evento = EKEvent(eventStore: store)
        evento.calendar = destino
        evento.title = rascunho.titulo.trimmingCharacters(in: .whitespacesAndNewlines)
        evento.startDate = intervalo.start
        evento.endDate = intervalo.end
        evento.isAllDay = rascunho.diaInteiro
        evento.timeZone = rascunho.diaInteiro ? nil : TimeZone.current
        evento.location = rascunho.local.trimmingCharacters(in: .whitespacesAndNewlines)
        evento.url = rascunho.url
        evento.notes = rascunho.observacoes
        do {
            try store.save(evento, span: .thisEvent, commit: true)
        } catch {
            throw CalendarErro.gravacao
        }
        tick()
        return intervalo.start
    }

    private func tick() {
        ultimaConsulta = Date()
        ultimoAcesso = EKEventStore.authorizationStatus(for: .event) == .fullAccess
        // A consulta voluntária da agenda independe do alerta automático.
        onAgendaChanged?()
        guard ultimoAcesso && AppSettings.shared.calendarCountdown else {
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
