# Lembretes Programados — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Adicionar notificações personalizadas agendadas pelo usuário (disparo único + recorrência de calendário + intervalo relativo) que aparecem no notch.

**Architecture:** Um modelo `Reminder` (Codable, persistido em UserDefaults) descreve título/corpo/agenda/som/URL. Um `ReminderScheduler` (só-Foundation, molde do `Pomodoro`) faz tick de relógio de parede e chama `onFire` no `AppDelegate`, que enfileira um `NotchNotification` e toca o som. A UI é uma aba "Lembretes" na janela de Ajustes (CRUD). Nada disso toca a `NotchView`, então o harness de snapshot fica intacto.

**Tech Stack:** Swift 5 (compilador 6.3), Foundation, AppKit, SwiftUI, XcodeGen. Zero dependências novas.

**Spec:** `SPEC-reminders.md` (raiz do repo). Achados de pesquisa já verificados com `swift` real estão consolidados lá e replicados aqui onde importam.

## Global Constraints

- **Deployment target:** macOS 14.2. **Language mode:** Swift 5 (`SWIFT_VERSION: "5.0"`).
- **Zero dependências novas** — só Foundation/AppKit/SwiftUI.
- **Comentários e strings de UI em pt-BR.**
- **Simplificações deliberadas** marcadas com `// ponytail:`.
- **XcodeGen:** nunca editar `Knobler.xcodeproj` à mão. Rodar `xcodegen generate` **após adicionar/remover arquivos** ou mudar `project.yml`.
- **Build do app:** `xcodebuild -project Knobler.xcodeproj -scheme Knobler -configuration Debug build`.
- **Testes:** o projeto **não tem target XCTest**. O mecanismo de teste é um self-check assert-based em `#if REMINDERS_SELFCHECK`, compilado isolado com `swiftc` (idêntico ao `Pomodoro.selfCheck()`).
- **`matchingPolicy: .strict` em TODA correspondência de calendário.** `.nextTime` é proibido (corrompe dia+hora no "dia 31").
- **Weekday:** `1=Dom, 2=Seg, …, 7=Sáb` (Gregoriano).
- **Sons válidos de `NSSound(named:)`** (de `/System/Library/Sounds`, verificado): `Basso, Blow, Bottle, Frog, Funk, Glass, Hero, Morse, Ping, Pop, Purr, Sosumi, Submarine, Tink`.
- **`weekdayOrdinal: -1` NÃO casa em `Calendar.nextDate`** — "última <dia>" usa helper próprio.
- **`tools/snapshot.sh` não muda** — `Reminders.swift`/`RemindersView.swift` não são usados pela `NotchView`.

---

## File Structure

| Arquivo | Responsabilidade |
|---|---|
| `Knobler/Reminders.swift` | **novo** — `Schedule`, `Reminder`, `ReminderClock` (matemática pura de agenda + rótulos), `ReminderScheduler` (engine), `ReminderSounds`, self-check. Só `import Foundation`. |
| `Knobler/RemindersView.swift` | **novo** — aba "Lembretes": lista (`RemindersView`) + formulário criar/editar (`ReminderFormView`). SwiftUI/AppKit. |
| `Knobler/AppSettings.swift` | **modificar** — `@Published var reminders`; `SettingsView` vira `TabView`. |
| `Knobler/NotificationInterceptor.swift` | **modificar** — `NotchNotification` ganha `var openURL: String?`. |
| `Knobler/NotchView.swift` | **modificar** — `openSourceApp` abre `openURL` quando presente. |
| `Knobler/KnoblerApp.swift` | **modificar** — instanciar/fiar/start `ReminderScheduler` + observer de wake. |

---

## Task 1: Modelo `Schedule` + matemática do próximo disparo (puro)

**Files:**
- Create: `Knobler/Reminders.swift`
- Test: self-check embutido (`#if REMINDERS_SELFCHECK`)

**Interfaces:**
- Produces:
  - `enum Schedule: Codable, Equatable, Hashable { case oneShot(Date); case calendar([DateComponents]); case interval(minutes: Int) }`
  - `enum ReminderClock` com `static var calendar: Calendar` e `static func nextOccurrence(for: Schedule, after: Date, cal: Calendar = calendar) -> Date?`
  - `ReminderClock.nextLastWeekday(_:hour:minute:after:cal:) -> Date?` e `lastWeekdayOfMonth(_:hour:minute:monthOf:cal:) -> Date?`

- [ ] **Step 1: Criar o arquivo com o modelo, a matemática pura e um self-check que FALHA**

Create `Knobler/Reminders.swift`:

```swift
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
```

- [ ] **Step 2: Rodar o self-check e confirmar que PASSA**

Run:
```bash
swiftc -parse-as-library -swift-version 5 -D REMINDERS_SELFCHECK Knobler/Reminders.swift -o /tmp/rmck && /tmp/rmck
```
Expected: `reminders self-check ok` (sem crash de assert).

- [ ] **Step 3: Commit**

```bash
git add Knobler/Reminders.swift
git commit -m "feat(reminders): modelo Schedule + matemática de próximo disparo"
```

---

## Task 2: `Reminder` + rótulos humanos + Codable

**Files:**
- Modify: `Knobler/Reminders.swift`
- Test: self-check embutido

**Interfaces:**
- Consumes: `Schedule`, `ReminderClock` (Task 1)
- Produces:
  - `struct Reminder: Codable, Identifiable, Equatable { var id: UUID; var title: String; var body: String; var schedule: Schedule; var soundName: String?; var openURL: String?; var enabled: Bool }`
  - `func Reminder.scheduleSummary(cal:) -> String`
  - `ReminderClock.weekdayNames`, `.weekdayNamesFull`, `.monthNames`, `.humanInterval(_:)`, `.humanCalendar(_:)`
  - `enum ReminderSounds { static let all: [String] }`

- [ ] **Step 1: Adicionar `Reminder`, os rótulos e a lista de sons**

In `Knobler/Reminders.swift`, insert after the `Schedule` enum (before `// MARK: - Matemática`):

```swift
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

/// Sons do sistema (de /System/Library/Sounds) válidos pra NSSound(named:).
enum ReminderSounds {
    static let all = ["Basso", "Blow", "Bottle", "Frog", "Funk", "Glass", "Hero",
                      "Morse", "Ping", "Pop", "Purr", "Sosumi", "Submarine", "Tink"]
}
```

- [ ] **Step 2: Adicionar os rótulos em `ReminderClock`**

In `Knobler/Reminders.swift`, inside `enum ReminderClock`, add after the `calendar` property:

```swift
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
```

- [ ] **Step 3: Estender o self-check com Codable + rótulos**

In `Knobler/Reminders.swift`, inside `RemindersSelfCheck.main()`, insert before `print("reminders self-check ok")`:

```swift
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
```

- [ ] **Step 4: Rodar o self-check e confirmar que PASSA**

Run:
```bash
swiftc -parse-as-library -swift-version 5 -D REMINDERS_SELFCHECK Knobler/Reminders.swift -o /tmp/rmck && /tmp/rmck
```
Expected: `reminders self-check ok`

- [ ] **Step 5: Commit**

```bash
git add Knobler/Reminders.swift
git commit -m "feat(reminders): struct Reminder, rótulos humanos, Codable"
```

---

## Task 3: `ReminderScheduler` (engine "nunca atrasado")

**Files:**
- Modify: `Knobler/Reminders.swift`
- Test: self-check embutido (relógio falso)

**Interfaces:**
- Consumes: `Reminder`, `Schedule`, `ReminderClock` (Tasks 1–2)
- Produces:
  - `final class ReminderScheduler` com `var remindersProvider: () -> [Reminder]`, `var onFire: ((Reminder) -> Void)?`, `var tolerance: TimeInterval`, `func start()`, `func stop()`, `func tick(now: Date = Date())`

- [ ] **Step 1: Adicionar a classe do scheduler**

In `Knobler/Reminders.swift`, insert after `enum ReminderClock { … }` (before the `#if REMINDERS_SELFCHECK` block):

```swift
// MARK: - Engine

/// Tick de relógio de parede varrendo os lembretes. "Nunca atrasado": um disparo
/// só conta se caiu na janela de `tolerance` antes de agora; o que passou (sleep)
/// é pulado e a próxima ocorrência futura é reprogramada. O AppDelegate liga o
/// observer de wake (NSWorkspace) chamando `tick()` — mantido fora daqui pra o
/// arquivo seguir só-Foundation (self-check/snapshot).
final class ReminderScheduler {
    var remindersProvider: () -> [Reminder] = { [] }
    var onFire: ((Reminder) -> Void)?
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
        let reminders = remindersProvider()
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
```

- [ ] **Step 2: Estender o self-check com cenários de disparo (relógio falso)**

In `Knobler/Reminders.swift`, inside `RemindersSelfCheck.main()`, insert before `print("reminders self-check ok")`:

```swift
        // --- scheduler: diária 09:00, "nunca atrasado" ---
        do {
            let sched = ReminderScheduler()
            var fired: [String] = []
            let r = Reminder(title: "D", schedule: daily)
            sched.remindersProvider = { [r] }
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
            sched.remindersProvider = { [r] }
            sched.onFire = { _ in fired += 1 }
            sched.tick(now: d("2026-07-18 09:00") + 5)
            assert(fired == 0)
        }
        // --- scheduler: intervalo 60min re-ancora e nunca atrasa ---
        do {
            let sched = ReminderScheduler()
            var fired: [String] = []
            let r = Reminder(title: "I", schedule: .interval(minutes: 60))
            sched.remindersProvider = { [r] }
            sched.onFire = { fired.append($0.title) }
            let t0 = d("2026-07-18 08:00")
            sched.tick(now: t0)                               // arma t0+60, não dispara
            assert(fired.isEmpty)
            sched.tick(now: t0 + 3600 + 5)                    // na hora → dispara
            assert(fired == ["I"])
            sched.tick(now: t0 + 3600 + 3 * 3600)             // muito depois → não redispara
            assert(fired == ["I"])
        }
```

- [ ] **Step 3: Rodar o self-check e confirmar que PASSA**

Run:
```bash
swiftc -parse-as-library -swift-version 5 -D REMINDERS_SELFCHECK Knobler/Reminders.swift -o /tmp/rmck && /tmp/rmck
```
Expected: `reminders self-check ok`

- [ ] **Step 4: Commit**

```bash
git add Knobler/Reminders.swift
git commit -m "feat(reminders): ReminderScheduler com engine nunca-atrasado + self-check"
```

---

## Task 4: `NotchNotification.openURL` + abrir ao clicar

**Files:**
- Modify: `Knobler/NotificationInterceptor.swift:15-26` (struct `NotchNotification`)
- Modify: `Knobler/NotchView.swift:800-813` (`openSourceApp`)

**Interfaces:**
- Produces: `NotchNotification.openURL: String?` (default nil), consumido pelo `onFire` na Task 7 e por `openSourceApp`.

- [ ] **Step 1: Adicionar o campo `openURL` ao `NotchNotification`**

In `Knobler/NotificationInterceptor.swift`, modify the struct (add one line before `let date = Date()`):

```swift
struct NotchNotification: Identifiable, Equatable {
    let id = UUID()
    let appName: String?
    let title: String
    let body: String
    /// Bundle ID do app de origem (banners interceptados) — ícone/abrir exatos.
    var bundleID: String? = nil
    /// Alvo de sessão do Supacode: clique na notificação foca worktree/tab.
    var supacodeWorktree: String? = nil  // ID do worktree (path percent-encoded)
    var supacodeTab: String? = nil  // UUID da tab
    /// Lembrete do usuário: clique abre esta URL (http/https/file/app).
    var openURL: String? = nil
    let date = Date()
}
```

- [ ] **Step 2: Abrir a `openURL` no clique**

In `Knobler/NotchView.swift`, modify `openSourceApp` — insert the `openURL` branch first (before the supacode branch):

```swift
    private func openSourceApp(_ notification: NotchNotification) {
        if let raw = notification.openURL, let url = URL(string: raw) {
            NSWorkspace.shared.open(url)
            return
        }
        if notification.supacodeWorktree != nil || notification.supacodeTab != nil {
            Self.focusSupacode(
                worktree: notification.supacodeWorktree, tab: notification.supacodeTab)
            return
        }
        if let bundleID = notification.bundleID,
           let app = NSRunningApplication.runningApplications(
               withBundleIdentifier: bundleID).first {
            app.activate()
            return
        }
        Self.runningApp(named: notification.appName)?.activate()
    }
```

- [ ] **Step 3: Build (arquivos existentes, sem xcodegen)**

Run:
```bash
xcodebuild -project Knobler.xcodeproj -scheme Knobler -configuration Debug build 2>&1 | tail -3
```
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4: Commit**

```bash
git add Knobler/NotificationInterceptor.swift Knobler/NotchView.swift
git commit -m "feat(reminders): NotchNotification.openURL abre no clique"
```

---

## Task 5: `AppSettings.reminders` + `TabView` na janela de Ajustes

**Files:**
- Modify: `Knobler/AppSettings.swift`

**Interfaces:**
- Consumes: `Reminder` (Task 2)
- Produces: `AppSettings.shared.reminders: [Reminder]` (persistido, `@Published`); `SettingsView` como `TabView` com aba "Lembretes" (placeholder temporário nesta task).

- [ ] **Step 1: Adicionar a propriedade persistida `reminders`**

In `Knobler/AppSettings.swift`, add the property after `hideScreenshotPreview` (before `// MARK: Pomodoro`):

```swift
    /// Lembretes programados do usuário (JSON em UserDefaults).
    @Published var reminders: [Reminder] {
        didSet {
            if let data = try? JSONEncoder().encode(reminders) {
                UserDefaults.standard.set(data, forKey: "reminders")
            }
        }
    }
```

In `init()`, add before the `func intOr` block (didSet não dispara em init):

```swift
        if let data = defaults.data(forKey: "reminders"),
           let decoded = try? JSONDecoder().decode([Reminder].self, from: data) {
            reminders = decoded
        } else {
            reminders = []
        }
```

- [ ] **Step 2: Envolver `SettingsView` num `TabView`**

In `Knobler/AppSettings.swift`, replace the whole `SettingsView` `body` (currently `Form { … }.formStyle(.grouped).frame(width: 340).fixedSize()`) so the Form becomes a computed `generalTab` and `body` is a `TabView`:

```swift
    var body: some View {
        TabView {
            generalTab
                .tabItem { Label("Geral", systemImage: "gearshape") }
            // ponytail: placeholder; vira RemindersView() na Task 6.
            Text("Lembretes em breve")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .tabItem { Label("Lembretes", systemImage: "bell.badge") }
        }
        .frame(width: 380, height: 560)
    }

    private var generalTab: some View {
        Form {
```

Then, at the end of the original Form, replace the closing:

```swift
        }
        .formStyle(.grouped)
    }
```

(ou seja: manter todas as `Section { … }` idênticas; só trocar a abertura `var body: some View { Form {` por `private var generalTab: some View { Form {`, e a cauda `.formStyle(.grouped).frame(width: 340).fixedSize()` por `.formStyle(.grouped) }`, adicionando o novo `var body` com o `TabView` acima.)

- [ ] **Step 3: Regenerar o projeto (novo arquivo `Reminders.swift` entra no target) e buildar**

Run:
```bash
xcodegen generate && xcodebuild -project Knobler.xcodeproj -scheme Knobler -configuration Debug build 2>&1 | tail -3
```
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4: Smoke test manual**

```bash
xcodebuild -project Knobler.xcodeproj -scheme Knobler -configuration Debug build 2>&1 | grep -m1 "BUILD SUCCEEDED"
open ~/Library/Developer/Xcode/DerivedData/Knobler-*/Build/Products/Debug/Knobler.app
```
Abrir o menu ◐ → "Ajustes…". Confirmar: duas abas ("Geral" com todo o conteúdo antigo, "Lembretes" com o placeholder). Fechar o app depois (`osascript -e 'quit app "Knobler"'` ou pelo menu).

- [ ] **Step 5: Commit**

```bash
git add Knobler/AppSettings.swift
git commit -m "feat(reminders): AppSettings.reminders persistido + TabView em Ajustes"
```

---

## Task 6: `RemindersView` — lista + formulário criar/editar

**Files:**
- Create: `Knobler/RemindersView.swift`
- Modify: `Knobler/AppSettings.swift` (trocar o placeholder pela `RemindersView()`)

**Interfaces:**
- Consumes: `AppSettings.shared.reminders`, `Reminder`, `Schedule`, `ReminderClock`, `ReminderSounds`
- Produces: `struct RemindersView: View`

- [ ] **Step 1: Criar `RemindersView.swift` com lista e formulário**

Create `Knobler/RemindersView.swift`:

```swift
//
//  RemindersView.swift
//  Knobler
//
//  Aba "Lembretes" na janela de Ajustes: lista (liga/desliga, editar, apagar) +
//  formulário de criar/editar. Edita AppSettings.shared.reminders direto.
//

import SwiftUI
import AppKit

struct RemindersView: View {
    @ObservedObject var settings = AppSettings.shared
    @State private var editing: Reminder?
    @State private var creating = false

    var body: some View {
        VStack(spacing: 0) {
            if settings.reminders.isEmpty {
                ContentUnavailableView("Sem lembretes", systemImage: "bell.slash",
                    description: Text("Toque em + para criar um lembrete programado."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(settings.reminders) { r in row(r) }
                        .onDelete { settings.reminders.remove(atOffsets: $0) }
                }
            }
            Divider()
            HStack {
                Spacer()
                Button { creating = true } label: {
                    Image(systemName: "plus").frame(width: 24, height: 24)
                }
                .buttonStyle(.borderless).padding(8)
            }
        }
        .sheet(isPresented: $creating) {
            ReminderFormView(reminder: nil) { settings.reminders.append($0) }
        }
        .sheet(item: $editing) { r in
            ReminderFormView(reminder: r) { edited in
                if let i = settings.reminders.firstIndex(where: { $0.id == edited.id }) {
                    settings.reminders[i] = edited
                }
            }
        }
    }

    private func row(_ r: Reminder) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(r.title.isEmpty ? "(sem título)" : r.title)
                Text(r.scheduleSummary()).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Toggle("", isOn: Binding(
                get: { r.enabled },
                set: { on in
                    if let i = settings.reminders.firstIndex(where: { $0.id == r.id }) {
                        settings.reminders[i].enabled = on
                    }
                }))
                .labelsHidden()
        }
        .contentShape(Rectangle())
        .onTapGesture { editing = r }
    }
}

private struct ReminderFormView: View {
    enum Freq: String, CaseIterable, Identifiable {
        case oneShot = "Uma vez", daily = "Diária", weekly = "Semanal"
        case monthly = "Mensal", yearly = "Anual", nth = "N-ésimo dia", interval = "Intervalo"
        var id: String { rawValue }
    }

    let existing: Reminder?
    let onSave: (Reminder) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var bodyText = ""
    @State private var freq: Freq = .daily
    @State private var time = ReminderFormView.defaultTime()   // hora (modos de relógio)
    @State private var date = Date()                            // oneShot: data+hora
    @State private var weekdays: Set<Int> = [2]                 // 1=Dom..7=Sáb
    @State private var dayOfMonth = 1
    @State private var month = 1
    @State private var ordinal = 1                              // 1..4, -1 = última
    @State private var nthWeekday = 2
    @State private var intervalValue = 2
    @State private var intervalHours = true
    @State private var soundName: String? = "Glass"
    @State private var openURL = ""

    init(reminder: Reminder?, onSave: @escaping (Reminder) -> Void) {
        self.existing = reminder
        self.onSave = onSave
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    TextField("Título", text: $title)
                    TextField("Descrição (opcional)", text: $bodyText)
                }
                Section("Quando") {
                    Picker("Frequência", selection: $freq) {
                        ForEach(Freq.allCases) { Text($0.rawValue).tag($0) }
                    }
                    freqFields
                }
                Section("Ao disparar") {
                    Picker("Som", selection: $soundName) {
                        Text("Nenhum").tag(String?.none)
                        ForEach(ReminderSounds.all, id: \.self) { s in
                            Text(s).tag(String?.some(s))
                        }
                    }
                    .onChange(of: soundName) { _, new in
                        if let new { NSSound(named: new)?.play() }
                    }
                    TextField("Abrir ao clicar (URL, opcional)", text: $openURL)
                }
            }
            .formStyle(.grouped)
            Divider()
            HStack {
                Button("Cancelar") { dismiss() }
                Spacer()
                Button("Salvar") { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(12)
        }
        .frame(width: 380, height: 480)
        .onAppear(perform: loadExisting)
    }

    @ViewBuilder private var freqFields: some View {
        switch freq {
        case .oneShot:
            DatePicker("Data e hora", selection: $date)
        case .daily:
            DatePicker("Hora", selection: $time, displayedComponents: .hourAndMinute)
        case .weekly:
            DatePicker("Hora", selection: $time, displayedComponents: .hourAndMinute)
            weekdayPicker
        case .monthly:
            DatePicker("Hora", selection: $time, displayedComponents: .hourAndMinute)
            Stepper("Dia do mês: \(dayOfMonth)", value: $dayOfMonth, in: 1...31)
        case .yearly:
            DatePicker("Hora", selection: $time, displayedComponents: .hourAndMinute)
            Stepper("Dia: \(dayOfMonth)", value: $dayOfMonth, in: 1...31)
            Picker("Mês", selection: $month) {
                ForEach(1...12, id: \.self) { m in
                    Text(ReminderClock.monthNames[m - 1]).tag(m)
                }
            }
        case .nth:
            DatePicker("Hora", selection: $time, displayedComponents: .hourAndMinute)
            Picker("Posição", selection: $ordinal) {
                Text("1ª").tag(1); Text("2ª").tag(2); Text("3ª").tag(3)
                Text("4ª").tag(4); Text("Última").tag(-1)
            }
            Picker("Dia da semana", selection: $nthWeekday) {
                ForEach(1...7, id: \.self) { w in
                    Text(ReminderClock.weekdayNamesFull[w - 1]).tag(w)
                }
            }
        case .interval:
            Stepper("A cada \(intervalValue) \(intervalHours ? "h" : "min")",
                    value: $intervalValue, in: 1...99)
            Toggle("Em horas", isOn: $intervalHours)
        }
    }

    private var weekdayPicker: some View {
        HStack(spacing: 4) {
            ForEach(1...7, id: \.self) { w in
                let on = weekdays.contains(w)
                Text(ReminderClock.weekdayNames[w - 1])
                    .font(.caption)
                    .frame(width: 34, height: 26)
                    .background(on ? Color.accentColor : Color.gray.opacity(0.2))
                    .foregroundStyle(on ? Color.white : Color.primary)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .onTapGesture {
                        if on { weekdays.remove(w) } else { weekdays.insert(w) }
                    }
            }
        }
    }

    // MARK: - Fields <-> Schedule

    private func hourMinute() -> (Int, Int) {
        let c = ReminderClock.calendar.dateComponents([.hour, .minute], from: time)
        return (c.hour ?? 9, c.minute ?? 0)
    }

    private func makeSchedule() -> Schedule {
        let (h, m) = hourMinute()
        switch freq {
        case .oneShot:
            return .oneShot(date)
        case .daily:
            return .calendar([DateComponents(hour: h, minute: m)])
        case .weekly:
            let days = weekdays.isEmpty ? [2] : weekdays.sorted()
            return .calendar(days.map { DateComponents(hour: h, minute: m, weekday: $0) })
        case .monthly:
            return .calendar([DateComponents(day: dayOfMonth, hour: h, minute: m)])
        case .yearly:
            return .calendar([DateComponents(month: month, day: dayOfMonth, hour: h, minute: m)])
        case .nth:
            return .calendar([DateComponents(hour: h, minute: m,
                                             weekday: nthWeekday, weekdayOrdinal: ordinal)])
        case .interval:
            return .interval(minutes: intervalValue * (intervalHours ? 60 : 1))
        }
    }

    private func loadExisting() {
        guard let r = existing else { return }
        title = r.title; bodyText = r.body
        soundName = r.soundName; openURL = r.openURL ?? ""
        switch r.schedule {
        case .oneShot(let dt):
            freq = .oneShot; date = dt
        case .interval(let min):
            freq = .interval
            if min % 60 == 0 { intervalHours = true; intervalValue = max(1, min / 60) }
            else { intervalHours = false; intervalValue = min }
        case .calendar(let comps):
            loadCalendar(comps)
        }
    }

    private func loadCalendar(_ comps: [DateComponents]) {
        guard let first = comps.first else { return }
        setTime(hour: first.hour ?? 9, minute: first.minute ?? 0)
        if let ord = first.weekdayOrdinal, let wd = first.weekday {
            freq = .nth; ordinal = ord; nthWeekday = wd
        } else if first.weekday != nil {
            freq = .weekly; weekdays = Set(comps.compactMap { $0.weekday })
        } else if let mo = first.month, let day = first.day {
            freq = .yearly; month = mo; dayOfMonth = day
        } else if let day = first.day {
            freq = .monthly; dayOfMonth = day
        } else {
            freq = .daily
        }
    }

    private func setTime(hour: Int, minute: Int) {
        var c = ReminderClock.calendar.dateComponents([.year, .month, .day], from: Date())
        c.hour = hour; c.minute = minute
        if let dt = ReminderClock.calendar.date(from: c) { time = dt }
    }

    private func save() {
        var r = existing ?? Reminder(title: title, schedule: makeSchedule())
        r.title = title.trimmingCharacters(in: .whitespaces)
        r.body = bodyText
        r.schedule = makeSchedule()
        r.soundName = soundName
        let url = openURL.trimmingCharacters(in: .whitespaces)
        r.openURL = url.isEmpty ? nil : url
        onSave(r)
        dismiss()
    }

    static func defaultTime() -> Date {
        var c = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        c.hour = 9; c.minute = 0
        return Calendar.current.date(from: c) ?? Date()
    }
}
```

- [ ] **Step 2: Trocar o placeholder pela `RemindersView()`**

In `Knobler/AppSettings.swift`, in `SettingsView.body`, replace the placeholder:

```swift
            // ponytail: placeholder; vira RemindersView() na Task 6.
            Text("Lembretes em breve")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .tabItem { Label("Lembretes", systemImage: "bell.badge") }
```

with:

```swift
            RemindersView()
                .tabItem { Label("Lembretes", systemImage: "bell.badge") }
```

- [ ] **Step 3: Regenerar (novo arquivo) e buildar**

Run:
```bash
xcodegen generate && xcodebuild -project Knobler.xcodeproj -scheme Knobler -configuration Debug build 2>&1 | tail -3
```
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4: Smoke test manual**

```bash
open ~/Library/Developer/Xcode/DerivedData/Knobler-*/Build/Products/Debug/Knobler.app
```
Menu ◐ → "Ajustes…" → aba "Lembretes". Criar um lembrete (título "Teste", frequência "Diária", som "Glass"), salvar. Confirmar: aparece na lista com o resumo ("Todo dia · HH:MM"), toggle liga/desliga, tap reabre pra editar, swipe apaga. Testar preview de som ao trocar no Picker. Fechar o app.

- [ ] **Step 5: Commit**

```bash
git add Knobler/RemindersView.swift Knobler/AppSettings.swift
git commit -m "feat(reminders): aba Lembretes com lista + formulário criar/editar"
```

---

## Task 7: Fiar o `ReminderScheduler` no `AppDelegate` (disparo real)

**Files:**
- Modify: `Knobler/KnoblerApp.swift:38` (prop), `Knobler/KnoblerApp.swift:181` (fiação, após o bloco do Pomodoro)

**Interfaces:**
- Consumes: `ReminderScheduler`, `Reminder`, `AppSettings.shared.reminders`, `NotchNotification.openURL`

- [ ] **Step 1: Instanciar o scheduler**

In `Knobler/KnoblerApp.swift`, add the property after `private let pomodoro = Pomodoro()` (line 38):

```swift
    private let reminderScheduler = ReminderScheduler()
```

- [ ] **Step 2: Fiar `onFire`, wake e `start()`**

In `Knobler/KnoblerApp.swift`, insert after the `pomodoro.onPhaseEnd = { … }` closing (after line 181, before the `// espelho automático` comment):

```swift
        // Lembretes programados: engine dispara → notch + som. oneShot desliga após disparar.
        reminderScheduler.remindersProvider = { AppSettings.shared.reminders }
        reminderScheduler.onFire = { [weak self] r in
            guard let self else { return }
            self.notches.values.forEach {
                $0.viewModel.enqueue(NotchNotification(
                    appName: nil, title: r.title, body: r.body, openURL: r.openURL))
            }
            if let sound = r.soundName { NSSound(named: NSSound.Name(sound))?.play() }
            if case .oneShot = r.schedule,
               let i = AppSettings.shared.reminders.firstIndex(where: { $0.id == r.id }) {
                AppSettings.shared.reminders[i].enabled = false
            }
        }
        // Wake: NSWorkspace.didWakeNotification é postado no notificationCenter do
        // NSWorkspace, NÃO no default — observar no center errado = handler mudo.
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.reminderScheduler.tick() }
        reminderScheduler.start()
```

- [ ] **Step 3: Build**

Run:
```bash
xcodebuild -project Knobler.xcodeproj -scheme Knobler -configuration Debug build 2>&1 | tail -3
```
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4: Teste E2E manual**

```bash
open ~/Library/Developer/Xcode/DerivedData/Knobler-*/Build/Products/Debug/Knobler.app
```
Menu ◐ → "Ajustes…" → "Lembretes" → criar um lembrete "Intervalo, a cada 1 min", som "Glass", salvar. Esperar ~1 min. Confirmar: o card aparece no notch (ícone sininho, título/corpo), o som toca. Criar um segundo com URL (`https://example.com`), frequência "Uma vez" ~1 min à frente; ao disparar, clicar no card abre a URL no browser e o lembrete fica desligado na lista. Fechar o app.

- [ ] **Step 5: Commit**

```bash
git add Knobler/KnoblerApp.swift
git commit -m "feat(reminders): fiar ReminderScheduler no AppDelegate (disparo no notch + som)"
```

---

## Self-Review (do autor do plano)

**1. Cobertura da spec:**
- Modelo `Reminder`/`Schedule` + persistência UserDefaults → Tasks 2, 5. ✓
- 7 modos do picker (uma vez/diária/semanal/mensal/anual/n-ésimo/intervalo) → Task 6 `freqFields`+`makeSchedule`; matemática Task 1. ✓
- `.strict` uniforme + "última <dia>" helper + `weekdayOrdinal:-1` sentinela → Task 1. ✓
- Engine "nunca atrasado" + dedup + wake no center certo → Tasks 3, 7. ✓
- Disparo no notch (sininho, som, clique→URL) → Tasks 4, 7. ✓
- UI aba "Lembretes" no TabView (lista + form + toggle + editar + apagar + preview de som) → Tasks 5, 6. ✓
- Snapshot harness intacto → nenhuma task toca `NotchView` render nem `snapshot.sh`. ✓
- Cortes v1 (snooze, API de agendamento, master-toggle, campo de ícone) → não implementados, conforme spec. ✓

**2. Placeholders:** nenhum "TODO/TBD"; todo passo tem código ou comando real com saída esperada.

**3. Consistência de tipos:** `Schedule`/`Reminder`/`ReminderClock.nextOccurrence`/`ReminderScheduler.tick(now:)`/`onFire`/`NotchNotification.openURL`/`AppSettings.reminders` usados idênticos entre tasks. `weekday 1=Dom..7=Sáb` consistente em matemática, rótulos e form.

**Risco conhecido (o executor confirma no build):** o default `@State private var time = ReminderFormView.defaultTime()` referencia um static do próprio tipo num initializer de propriedade — válido em Swift, mas se o compilador reclamar, mover a inicialização de `time` para dentro de um `.onAppear` (setando via `setTime`) antes de `loadExisting()`.
