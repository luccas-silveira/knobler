//
//  Reminders.swift
//  Knobler
//
//  Lembretes programados: modelo + matemática de agenda + engine. Só Foundation
//  (compila isolado pro self-check, como o Pomodoro). Tempo por relógio de
//  parede; "nunca atrasado" — disparo perdido em sleep é pulado, nunca enfileirado.
//
//  Self-check:
//    swiftc -swift-version 5 -D REMINDERS_SELFCHECK Knobler/Reminders.swift -o /tmp/rmck && /tmp/rmck
//

import Foundation

// MARK: - Modelo

enum Schedule: Codable, Equatable, Hashable {
    case oneShot(Date)
    case calendar([DateComponents])   // diária/semanal/mensal/anual/n-ésimo (menor match)
    case interval(minutes: Int)
}

// MARK: - Matemática de agenda (pura)

enum ReminderClock {
    /// Injetável pro self-check com fuso fixo; no app é `.current`.
    static var calendar: Calendar = .current

    /// Próxima ocorrência estritamente > `after` (calendar/oneShot). Intervalo é
    /// tratado no scheduler (âncora), então retorna nil aqui.
    static func nextOccurrence(for schedule: Schedule, after: Date,
                               cal: Calendar = calendar) -> Date? {
        switch schedule {
        case .oneShot(let date):
            return date > after ? date : nil
        case .calendar(let comps):
            return comps.compactMap { nextCalendar($0, after: after, cal: cal) }.min()
        case .interval:
            return nil
        }
    }

    private static func nextCalendar(_ dc: DateComponents, after: Date,
                                     cal: Calendar) -> Date? {
        // "última <dia>" chega como weekdayOrdinal negativo — Calendar não casa isso.
        if let ord = dc.weekdayOrdinal, ord < 0, let weekday = dc.weekday {
            return nextLastWeekday(weekday, hour: dc.hour ?? 0,
                                   minute: dc.minute ?? 0, after: after, cal: cal)
        }
        // .strict: pula meses sem o dia (dia 31) preservando a hora. .nextTime corromperia.
        return cal.nextDate(after: after, matching: dc, matchingPolicy: .strict)
    }

    /// Última ocorrência de `weekday` (1=Dom..7=Sáb) no mês de `d`, no horário h:m.
    static func lastWeekdayOfMonth(_ weekday: Int, hour: Int, minute: Int,
                                   monthOf d: Date, cal: Calendar) -> Date? {
        guard let range = cal.range(of: .day, in: .month, for: d) else { return nil }
        var last = cal.dateComponents([.year, .month], from: d)
        last.day = range.upperBound - 1; last.hour = hour; last.minute = minute
        guard let lastDay = cal.date(from: last) else { return nil }
        let back = (cal.component(.weekday, from: lastDay) - weekday + 7) % 7
        return cal.date(byAdding: .day, value: -back, to: lastDay)
    }

    /// Próxima "última <weekday> do mês" estritamente > after (mês corrente ou o próximo).
    static func nextLastWeekday(_ weekday: Int, hour: Int, minute: Int,
                                after: Date, cal: Calendar) -> Date? {
        for offset in 0...1 {
            guard let m = cal.date(byAdding: .month, value: offset, to: after),
                  let cand = lastWeekdayOfMonth(weekday, hour: hour, minute: minute,
                                                monthOf: m, cal: cal),
                  cand > after else { continue }
            return cand
        }
        return nil
    }
}

// Entrada do self-check standalone (molde do Pomodoro). É @main, não expressão
// top-level, pra o arquivo entrar como biblioteca no build do app sem conflito.
#if REMINDERS_SELFCHECK
@main
enum RemindersSelfCheck {
    static func main() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "America/Sao_Paulo")!
        cal.locale = Locale(identifier: "pt_BR")
        ReminderClock.calendar = cal
        func d(_ s: String) -> Date {
            let f = DateFormatter(); f.calendar = cal; f.timeZone = cal.timeZone
            f.dateFormat = "yyyy-MM-dd HH:mm"; return f.date(from: s)!
        }
        func next(_ s: Schedule, _ after: String) -> Date? {
            ReminderClock.nextOccurrence(for: s, after: d(after))
        }
        let daily = Schedule.calendar([DateComponents(hour: 9, minute: 0)])
        assert(next(daily, "2026-07-18 08:00") == d("2026-07-18 09:00"))
        assert(next(daily, "2026-07-18 10:00") == d("2026-07-19 09:00"))
        // semanal {Seg=2, Qua=4} após sábado → segunda
        let weekly = Schedule.calendar([DateComponents(hour: 9, weekday: 2),
                                        DateComponents(hour: 9, weekday: 4)])
        assert(next(weekly, "2026-07-18 12:00") == d("2026-07-20 09:00"))
        // mensal dia 15
        assert(next(.calendar([DateComponents(day: 15, hour: 9)]), "2026-07-18 00:00")
               == d("2026-08-15 09:00"))
        // mensal dia 31 → pula fevereiro (via .strict), preserva hora
        assert(next(.calendar([DateComponents(day: 31, hour: 9)]), "2026-01-31 12:00")
               == d("2026-03-31 09:00"))
        // anual 15/jan
        assert(next(.calendar([DateComponents(month: 1, day: 15, hour: 9)]), "2026-07-18 00:00")
               == d("2027-01-15 09:00"))
        // 1ª segunda do mês
        assert(next(.calendar([DateComponents(hour: 9, weekday: 2, weekdayOrdinal: 1)]), "2026-07-18 00:00")
               == d("2026-08-03 09:00"))
        // última segunda: julho/2026 → 27; após 28/jul → 31/ago
        let lastMon = Schedule.calendar([DateComponents(hour: 9, weekday: 2, weekdayOrdinal: -1)])
        assert(next(lastMon, "2026-07-18 00:00") == d("2026-07-27 09:00"))
        assert(next(lastMon, "2026-07-28 00:00") == d("2026-08-31 09:00"))
        // oneShot
        assert(next(.oneShot(d("2026-07-20 14:00")), "2026-07-18 00:00") == d("2026-07-20 14:00"))
        assert(next(.oneShot(d("2026-07-10 14:00")), "2026-07-18 00:00") == nil)

        print("reminders self-check ok")
    }
}
#endif
