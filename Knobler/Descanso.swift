//
//  Descanso.swift
//  Knobler
//
//  Modelo do bloqueio forçado de tela ("Descanso"). Reusa o motor de agenda dos
//  Lembretes (`Schedule` + `ReminderClock`) e adiciona uma duração (quanto a tela
//  fica travada). Só Foundation — compila isolado pro self-check junto de
//  Reminders.swift (como Pomodoro/Reminders). Tempo por relógio de parede.
//
//  Self-check:
//    swiftc -parse-as-library -swift-version 5 -D DESCANSO_SELFCHECK \
//      Knobler/Reminders.swift Knobler/Descanso.swift -o /tmp/dck && /tmp/dck
//

import Foundation

// MARK: - Modelo

/// Um bloqueio agendado: quando dispara (`schedule`, reusado dos Lembretes) e por
/// quanto tempo a tela trava (`durationMinutes`). `label` é opcional (o overlay cai
/// no fallback "descanse um pouco").
struct ScreenBreak: Codable, Identifiable, Equatable, Scheduled {
    var id: UUID = UUID()
    var label: String = ""
    var schedule: Schedule
    var durationMinutes: Int = 5      // 1–120
    var enabled: Bool = true

    func scheduleSummary(cal: Calendar = ReminderClock.calendar) -> String {
        let base: String
        switch schedule {
        case .oneShot(let d):
            let f = DateFormatter()
            f.calendar = cal; f.timeZone = cal.timeZone
            f.locale = Locale(identifier: "pt_BR")
            f.dateFormat = "d 'de' MMM, HH:mm"
            base = "Uma vez · \(f.string(from: d))"
        case .interval(let m):
            base = "A cada \(ReminderClock.humanInterval(m))"
        case .calendar(let c):
            base = ReminderClock.humanCalendar(c)
        }
        return "\(base) · \(durationMinutes)min de bloqueio"
    }
}

// Entrada do self-check standalone. É @main (declaração, não top-level) pra o arquivo
// entrar como biblioteca no build do app e no harness de snapshot sem conflito.
#if DESCANSO_SELFCHECK
@main
enum DescansoSelfCheck {
    static func main() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "America/Sao_Paulo")!
        cal.locale = Locale(identifier: "pt_BR")
        ReminderClock.calendar = cal

        // Codable roundtrip (inclui a duração e o schedule reusado)
        let sample: [ScreenBreak] = [
            ScreenBreak(label: "Almoço",
                        schedule: .calendar([DateComponents(hour: 12, minute: 30)]),
                        durationMinutes: 15),
            ScreenBreak(schedule: .interval(minutes: 90)),
            ScreenBreak(label: "Foco",
                        schedule: .oneShot(Date(timeIntervalSince1970: 1_800_000_000)),
                        durationMinutes: 25, enabled: false),
        ]
        let data = try! JSONEncoder().encode(sample)
        assert(try! JSONDecoder().decode([ScreenBreak].self, from: data) == sample)

        // resumo humano: schedule (via ReminderClock) + duração
        func sum(_ b: ScreenBreak) -> String { b.scheduleSummary(cal: cal) }
        assert(sum(sample[0]) == "Todo dia · 12:30 · 15min de bloqueio")
        assert(sum(sample[1]) == "A cada 90min · 5min de bloqueio")
        assert(sum(ScreenBreak(schedule: .interval(minutes: 120), durationMinutes: 10))
               == "A cada 2h · 10min de bloqueio")

        // conforma Scheduled → o ScheduleEngine consegue tickar ScreenBreak
        let engine = ScheduleEngine<ScreenBreak>()
        var fired: [String] = []
        let daily = ScreenBreak(label: "D",
                                schedule: .calendar([DateComponents(hour: 9, minute: 0)]))
        engine.itemsProvider = { [daily] }
        engine.onFire = { fired.append($0.label) }
        func d(_ s: String) -> Date {
            let f = DateFormatter(); f.calendar = cal; f.timeZone = cal.timeZone
            f.dateFormat = "yyyy-MM-dd HH:mm"; return f.date(from: s)!
        }
        engine.tick(now: d("2026-07-18 08:59"))         // arma
        assert(fired.isEmpty)
        engine.tick(now: d("2026-07-18 09:00") + 10)    // na hora → dispara
        assert(fired == ["D"])
        engine.tick(now: d("2026-07-19 15:00"))         // perdeu 09:00 (sleep) → não dispara
        assert(fired == ["D"])

        // "Daqui a X" é açúcar de UI → oneShot no futuro; aqui só valida o shape do case
        let future = Date().addingTimeInterval(3000)
        guard case .oneShot(let dd) = Schedule.oneShot(future), dd == future
        else { fatalError("oneShot shape") }

        print("descanso self-check ok")
    }
}
#endif
