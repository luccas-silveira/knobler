//
//  Reminders.swift
//  Knobler
//
//  Lembretes programados: modelo + matemática de agenda + engine. Só Foundation
//  (compila isolado pro self-check, como o Pomodoro). Tempo por relógio de
//  parede; "nunca atrasado" — disparo perdido em sleep é pulado, nunca enfileirado.
//
//  Self-check:
//    swiftc -parse-as-library -swift-version 5 -D REMINDERS_SELFCHECK Knobler/Reminders.swift -o /tmp/rmck && /tmp/rmck
//

import Foundation

// MARK: - Modelo

enum Schedule: Codable, Equatable, Hashable {
    case oneShot(Date)
    case calendar([DateComponents])   // diária/semanal/mensal/anual/n-ésimo (menor match)
    case interval(minutes: Int)
}

struct Reminder: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var title: String
    var body: String = ""
    var schedule: Schedule
    var soundName: String?        // nome NSSound; nil = mudo
    var openURL: String?          // clique abre; nil = só dispensa
    var enabled: Bool = true      // pausar sem apagar

    func scheduleSummary(cal: Calendar = ReminderClock.calendar) -> String {
        switch schedule {
        case .oneShot(let date):
            let f = DateFormatter()
            f.calendar = cal; f.timeZone = cal.timeZone
            f.locale = Locale(identifier: "pt_BR")
            f.dateFormat = "d 'de' MMM, HH:mm"
            return "Uma vez · \(f.string(from: date))"
        case .interval(let min):
            return "A cada \(ReminderClock.humanInterval(min))"
        case .calendar(let comps):
            return ReminderClock.humanCalendar(comps)
        }
    }
}

/// Item agendável genérico — o `ScheduleEngine` só precisa disto pra tickar.
/// `Reminder` e `ScreenBreak` conformam.
protocol Scheduled: Identifiable where ID == UUID {
    var enabled: Bool { get }
    var schedule: Schedule { get }
}
extension Reminder: Scheduled {}

/// Sons do sistema (de /System/Library/Sounds) válidos pra NSSound(named:).
enum ReminderSounds {
    static let all = ["Basso", "Blow", "Bottle", "Frog", "Funk", "Glass", "Hero",
                      "Morse", "Ping", "Pop", "Purr", "Sosumi", "Submarine", "Tink"]
}

// MARK: - Matemática de agenda (pura)

enum ReminderClock {
    /// Injetável pro self-check com fuso fixo; no app é `.current`.
    static var calendar: Calendar = .current

    static let weekdayNames = ["Dom", "Seg", "Ter", "Qua", "Qui", "Sex", "Sáb"]
    static let weekdayNamesFull = ["Domingo", "Segunda", "Terça", "Quarta",
                                   "Quinta", "Sexta", "Sábado"]
    static let monthNames = ["jan", "fev", "mar", "abr", "mai", "jun",
                             "jul", "ago", "set", "out", "nov", "dez"]

    static func humanInterval(_ min: Int) -> String {
        if min % 60 == 0 { return "\(min / 60)h" }
        return "\(min)min"
    }

    private static func hm(_ dc: DateComponents) -> String {
        String(format: "%02d:%02d", dc.hour ?? 0, dc.minute ?? 0)
    }

    /// Rótulo humano de um `[DateComponents]` de calendário. Ordem importa:
    /// n-ésimo (ordinal+weekday) → semanal (weekday) → anual (mês+dia) → mensal (dia) → diária.
    static func humanCalendar(_ comps: [DateComponents]) -> String {
        guard let first = comps.first else { return "" }
        let time = hm(first)
        if let ord = first.weekdayOrdinal, let wd = first.weekday {
            let name = weekdayNames[(wd - 1 + 7) % 7]
            return "\(ord < 0 ? "Última" : "\(ord)ª") \(name) · \(time)"
        }
        if first.weekday != nil {
            let dias = comps.compactMap { $0.weekday }.sorted()
                .map { weekdayNames[($0 - 1 + 7) % 7] }.joined(separator: ", ")
            return "\(dias) · \(time)"
        }
        if let month = first.month, let day = first.day {
            return "\(day)/\(monthNames[(month - 1 + 12) % 12]) · \(time)"
        }
        if let day = first.day {
            return "Dia \(day) · \(time)"
        }
        return "Todo dia · \(time)"
    }

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

// MARK: - Engine

/// Tick de relógio de parede varrendo os lembretes. "Nunca atrasado": um disparo
/// só conta se caiu na janela de `tolerance` antes de agora; o que passou (sleep)
/// é pulado e a próxima ocorrência futura é reprogramada. O AppDelegate liga o
/// observer de wake (NSWorkspace) chamando `tick()` — mantido fora daqui pra o
/// arquivo seguir só-Foundation (self-check/snapshot).
final class ScheduleEngine<Item: Scheduled> {
    var itemsProvider: () -> [Item] = { [] }
    var onFire: ((Item) -> Void)?
    /// Folga além do tick pra ainda considerar "na hora".
    var tolerance: TimeInterval = 90

    private var timer: Timer?
    /// Próximo disparo por lembrete, chaveado pelo hash do schedule (invalida em edição).
    private var nextFire: [UUID: (hash: Int, date: Date)] = [:]

    func start() {
        stop()
        // Timer(...) + add em .common tica durante tracking de menu / interação no notch.
        let t = Timer(timeInterval: 15, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
        tick()
    }

    func stop() {
        timer?.invalidate(); timer = nil
    }

    /// `now` injetável pro self-check com relógio falso.
    func tick(now: Date = Date()) {
        let reminders = itemsProvider()
        let live = Set(reminders.map(\.id))
        nextFire = nextFire.filter { live.contains($0.key) }   // limpa apagados

        for r in reminders where r.enabled {
            let h = r.schedule.hashValue
            if nextFire[r.id]?.hash != h {                     // novo ou editado
                nextFire[r.id] = (h, computeNext(r.schedule, from: now))
            }
            guard let nf = nextFire[r.id]?.date, now >= nf else { continue }
            if now.timeIntervalSince(nf) <= tolerance {        // na hora → dispara
                onFire?(r)
            }                                                  // atrasado → só reprograma
            // avança pra próxima futura: pula backlog e evita refire no mesmo tick.
            nextFire[r.id] = (h, computeNext(r.schedule, from: now))
        }
    }

    private func computeNext(_ schedule: Schedule, from: Date) -> Date {
        switch schedule {
        case .interval(let min):
            // intervalo re-ancora em `from` (nunca atrasado: reinicia a contagem no wake)
            return from.addingTimeInterval(TimeInterval(max(1, min) * 60))
        default:
            return ReminderClock.nextOccurrence(for: schedule, after: from) ?? .distantFuture
        }
    }
}

/// Mantém o nome usado no resto do código (AppDelegate/self-check).
typealias ReminderScheduler = ScheduleEngine<Reminder>

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

        // Codable roundtrip
        let sample: [Reminder] = [
            Reminder(title: "💧 Água", schedule: .interval(minutes: 120), soundName: "Glass"),
            Reminder(title: "Standup", schedule: weekly, soundName: nil,
                     openURL: "https://meet.example"),
            Reminder(title: "Uma vez", schedule: .oneShot(d("2026-07-20 14:00")), enabled: false),
        ]
        let encoded = try! JSONEncoder().encode(sample)
        assert(try! JSONDecoder().decode([Reminder].self, from: encoded) == sample)

        // rótulos humanos
        func sum(_ s: Schedule) -> String { Reminder(title: "x", schedule: s).scheduleSummary() }
        assert(sum(daily) == "Todo dia · 09:00")
        assert(sum(weekly) == "Seg, Qua · 09:00")
        assert(sum(.interval(minutes: 120)) == "A cada 2h")
        assert(sum(.interval(minutes: 90)) == "A cada 90min")
        assert(sum(.calendar([DateComponents(day: 15, hour: 9)])) == "Dia 15 · 09:00")
        assert(sum(.calendar([DateComponents(month: 1, day: 15, hour: 9)])) == "15/jan · 09:00")
        assert(sum(lastMon) == "Última Seg · 09:00")
        assert(sum(.calendar([DateComponents(hour: 9, weekday: 2, weekdayOrdinal: 1)])) == "1ª Seg · 09:00")
        assert(sum(.oneShot(d("2026-07-20 14:00"))).hasPrefix("Uma vez ·"))

        // --- scheduler: diária 09:00, "nunca atrasado" ---
        do {
            let sched = ReminderScheduler()
            var fired: [String] = []
            let r = Reminder(title: "D", schedule: daily)
            sched.itemsProvider = { [r] }
            sched.onFire = { fired.append($0.title) }

            sched.tick(now: d("2026-07-18 08:59"))            // arma, não dispara
            assert(fired.isEmpty)
            sched.tick(now: d("2026-07-18 09:00") + 10)       // dentro da tolerância → dispara
            assert(fired == ["D"])
            sched.tick(now: d("2026-07-18 09:00") + 20)       // não redispara
            assert(fired == ["D"])
            sched.tick(now: d("2026-07-19 15:00"))            // perdeu 09:00 (wake tardio) → não dispara
            assert(fired == ["D"])
            sched.tick(now: d("2026-07-20 09:00") + 5)        // próximo dia, na hora → dispara
            assert(fired == ["D", "D"])
        }
        // --- scheduler: desligado não dispara ---
        do {
            let sched = ReminderScheduler()
            var fired = 0
            let r = Reminder(title: "off", schedule: daily, enabled: false)
            sched.itemsProvider = { [r] }
            sched.onFire = { _ in fired += 1 }
            sched.tick(now: d("2026-07-18 09:00") + 5)
            assert(fired == 0)
        }
        // --- scheduler: intervalo 60min re-ancora e nunca atrasa ---
        do {
            let sched = ReminderScheduler()
            var fired: [String] = []
            let r = Reminder(title: "I", schedule: .interval(minutes: 60))
            sched.itemsProvider = { [r] }
            sched.onFire = { fired.append($0.title) }
            let t0 = d("2026-07-18 08:00")
            sched.tick(now: t0)                               // arma t0+60, não dispara
            assert(fired.isEmpty)
            sched.tick(now: t0 + 3600 + 5)                    // na hora → dispara
            assert(fired == ["I"])
            sched.tick(now: t0 + 3600 + 3 * 3600)             // muito depois → não redispara
            assert(fired == ["I"])
        }

        print("reminders self-check ok")
    }
}
#endif
