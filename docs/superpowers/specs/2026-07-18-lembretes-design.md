# Spec — Lembretes programados

Notificações personalizadas, agendadas pelo usuário, que disparam **no notch**.
Cobre disparo único, recorrência de calendário (diária/semanal/mensal/anual/
n-ésimo dia da semana) e intervalo relativo ("a cada N min/h"). Feature nova,
independente do interceptor de banners do sistema.

## Princípios

- Coerente com o produto: o lembrete aparece no notch, não como banner nativo.
- Engine só-Foundation, no molde do `Pomodoro` (relógio de parede, self-check).
- "Nunca atrasado": disparo perdido durante sleep/off é pulado, nunca enfileirado.
- Nada é usado pela `NotchView` → harness de snapshot (`tools/snapshot.sh`) intacto.

## Modelo de dados

Persistido como JSON (`[Reminder]`) numa chave de `UserDefaults` (`reminders`),
exposto em `AppSettings` como `@Published var reminders: [Reminder]` (mesmo
padrão dos outros ajustes — a UI edita, a engine lê no momento do tick).

```swift
struct Reminder: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var title: String          // obrigatório; emoji no título dá identidade visual
    var body: String = ""      // opcional
    var schedule: Schedule
    var soundName: String?     // nome de som do sistema (NSSound); nil = mudo
    var openURL: String?       // clique abre (http/https/file/app); nil = só dispensa
    var enabled: Bool = true    // pausar sem apagar
}

enum Schedule: Codable, Equatable {
    case oneShot(Date)                 // "uma vez" → dispara e desliga (enabled = false)
    case calendar([DateComponents])    // diária/semanal/mensal/anual/n-ésimo
    case interval(minutes: Int)        // "a cada N" → re-ancora no wake
}
```

`DateComponents` é `Codable`. O `case calendar` guarda um **array** porque um
lembrete semanal com vários dias vira vários `DateComponents` (um por dia da
semana); o próximo disparo é o **menor** `nextDate` entre eles.

### Mapeamento dos 7 modos do picker → `Schedule`

| Modo (UI)            | Vira                                                             |
|----------------------|-----------------------------------------------------------------|
| Uma vez              | `oneShot(Date)`                                                 |
| Diária               | `calendar([{hour, minute}])`                                    |
| Semanal (dias)       | `calendar([{weekday, hour, minute}])` — um por dia selecionado  |
| Mensal (dia do mês)  | `calendar([{day, hour, minute}])`                              |
| Anual                | `calendar([{month, day, hour, minute}])`                       |
| N-ésimo dia da semana| `calendar([{weekdayOrdinal, weekday, hour, minute}])` — 1ª–4ª via `.strict`; "última" = `weekdayOrdinal: -1` (sentinela → helper) |
| Intervalo            | `interval(minutes:)`                                           |

### Achados da pesquisa (verificados com `swift` real — não presumir)

- **`weekday`:** `1=Dom, 2=Seg, …, 7=Sáb` (Gregoriano). Mapear os chips da UI assim.
- **`matchingPolicy: .strict` em TODOS os modos de calendário.** Testado: `.strict`
  não devolve `nil` nos casos normais (diária/semanal/anual/n-ésimo) e resolve o
  "dia 31" corretamente — pula fevereiro **e preserva a hora** (`2026-01-31` →
  `2026-03-31 09:00`). ⚠️ `.nextTime` **corrompe**: escorrega pro `2026-03-01 00:00`
  (perde o dia *e* zera a hora). Nunca usar `.nextTime` aqui.
- **`weekdayOrdinal = -1` NÃO funciona** — `Calendar.nextDate` devolve `nil` pra
  ordinal negativo (testado nos dois policies). "Última `<dia>`" é caso especial,
  com helper próprio (código abaixo, testado):

```swift
// Última ocorrência de `weekday` no mês de `d`, no horário h:m.
func lastWeekdayOfMonth(_ weekday: Int, hour: Int, minute: Int, monthOf d: Date) -> Date? {
    guard let range = cal.range(of: .day, in: .month, for: d) else { return nil }
    var last = cal.dateComponents([.year, .month], from: d)
    last.day = range.upperBound - 1; last.hour = hour; last.minute = minute
    guard let lastDay = cal.date(from: last) else { return nil }
    let back = (cal.component(.weekday, from: lastDay) - weekday + 7) % 7
    return cal.date(byAdding: .day, value: -back, to: lastDay)
}
// Próxima "última <weekday>" > after: tenta mês corrente, senão o próximo.
func nextLastWeekday(_ weekday: Int, hour: Int, minute: Int, after: Date) -> Date? {
    for offset in 0...1 {
        guard let m = cal.date(byAdding: .month, value: offset, to: after),
              let cand = lastWeekdayOfMonth(weekday, hour: hour, minute: minute, monthOf: m),
              cand > after else { continue }
        return cand
    }
    return nil
}
```

- **Fuso/DST:** sai de graça — `Calendar.current` casa hora local. Brasil sem
  horário de verão desde 2019, então o risco de `.strict` devolver `nil` por
  horário inexistente em gap de DST é nulo na prática.
- **`DateComponents` é `Codable`** — JSON limpo (`{"hour":9,"weekday":2,...}`),
  roundtrip verificado. Persistência via `JSONEncoder` confirmada.

## Engine — `ReminderScheduler`

Arquivo `Reminders.swift` (modelo + engine + self-check), só `Foundation`.

```swift
final class ReminderScheduler {
    var remindersProvider: () -> [Reminder] = { [] }
    var onFire: ((Reminder) -> Void)?
    func start()   // Timer(~15s, .common) + observa wake (ver gotcha abaixo)
    func stop()
}
```

⚠️ **Gotcha do wake (verificado):** `NSWorkspace.didWakeNotification` é postado no
**`NSWorkspace.shared.notificationCenter`**, não no `NotificationCenter.default`.
Observar no center errado → o handler nunca dispara.

```swift
NSWorkspace.shared.notificationCenter.addObserver(
    self, selector: #selector(tick),
    name: NSWorkspace.didWakeNotification, object: nil)
```

**Cálculo do próximo disparo** — `nextOccurrence(for: Schedule, after: Date) -> Date?`:

- `oneShot(d)` → `d` se `d > after`, senão `nil` (já passou).
- `calendar(comps)` → menor, entre os `DateComponents`, de:
  - se `weekdayOrdinal ?? 0 < 0` (sentinela de "última"): `nextLastWeekday(...)`;
  - senão: `cal.nextDate(after:, matching:, matchingPolicy: .strict)`.
- `interval(min)` → tratado direto no tick (âncora `firedAt + min·60`), não aqui.

### Regra de disparo ("nunca atrasado")

A cada tick, `now = Date()`. Para cada lembrete **habilitado**:

- **calendar / oneShot:** calcula o instante agendado mais próximo. Dispara
  **só** se esse instante ∈ `(now - tolerance, now]`, onde `tolerance ≈ 90s`
  (folga sobre o tick). Se o instante ficou pra trás disso (dormiu/desligou),
  **não dispara** — apenas segue (a próxima ocorrência futura será pega no
  tick certo). Isso é o "nunca atrasado".
- **interval:** âncora em memória `firedAt[id]` (default: quando entrou/foi
  carregado). Vence quando `now >= firedAt + N·60`. Se venceu dentro da
  `tolerance` → dispara; se venceu durante sleep (fora da tolerance) → **não
  dispara**; em ambos os casos re-ancora `firedAt = now` (re-inicia a contagem
  a partir do wake).

### Dedup

Como `tolerance` (~90s) > tick (~15s), a mesma ocorrência cairia na janela em
vários ticks seguidos. Guardar em memória `lastFiredInstant[id]` e não redisparar
o mesmo instante. Dict **não persistido** — no relaunch, "nunca atrasado" já
impede refire de ocorrências passadas.

### Ciclo de vida

- `oneShot` que dispara → `enabled = false` (fica na lista, riscado/off; usuário
  apaga se quiser). Alternativa a decidir na UI: remover da lista ao disparar.
- Editar/criar/apagar/toggle na UI muda `AppSettings.reminders`; a engine lê
  `remindersProvider()` a cada tick, então pega a mudança no próximo tick sem
  fiação extra. `firedAt`/`lastFiredInstant` de ids que sumiram são limpos.

### Self-check (assert-based, `#if REMINDERS_SELFCHECK`)

Função pura testável: `nextOccurrence(for: Schedule, after: Date) -> Date?`.

- diária 09:00 depois de um `Date` fixo às 08:00 → mesmo dia 09:00.
- diária 09:00 depois de 10:00 → dia seguinte 09:00.
- semanal {seg, qua} → menor `nextDate` entre os dois.
- mensal dia 15 → próximo dia 15.
- instante > tolerance no passado **não** dispara (regra "nunca atrasado").
- Entrada standalone `@main` no molde do `Pomodoro.selfCheck()`.

## Disparo → notch

`onFire` (no `AppDelegate`) monta um `NotchNotification` e enfileira em todas as
janelas de notch, tocando o som:

```swift
scheduler.onFire = { [weak self] r in
    let n = NotchNotification(appName: nil, title: r.title, body: r.body,
                              openURL: r.openURL)          // sininho + clique
    self?.notches.values.forEach { $0.viewModel.enqueue(n) }
    if let s = r.soundName { NSSound(named: s)?.play() }
}
```

- **Ícone:** sem `bundleID` → `appIcon(for:)` já cai no `bell.badge.fill`.
- **Clique:** adicionar `var openURL: String? = nil` em `NotchNotification`;
  em `openSourceApp(_:)`, se `openURL` presente, `NSWorkspace.shared.open(url)`
  antes dos ramos de supacode/bundleID. Sem `openURL`, o tap só dispensa (hoje).
- **Prioridade/tempo:** entra como `.notification` — herda o auto-dismiss de 5s,
  a fila FIFO e o "segurar mouse pausa dismiss" que já existem no `NotchViewModel`.

## UI — aba "Lembretes"

`SettingsView` vira `TabView`:

- **Aba "Geral":** o `Form` atual, sem mudança de conteúdo.
- **Aba "Lembretes"** (`RemindersView.swift`):
  - Lista de `AppSettings.shared.reminders`: cada linha mostra emoji/título,
    resumo humano do schedule ("Seg, Qua, Sex · 09:00", "A cada 2h", "Uma vez
    · 20/jul 14:00"), `Toggle` de `enabled`, swipe/botão apagar; tap edita.
  - Botão **"+"** → formulário (sheet ou navegação) reutilizado por criar/editar:
    - `TextField` título (obrigatório) · `TextField` corpo (opcional).
    - `Picker` de frequência (7 modos) → revela os campos do modo:
      - Uma vez: `DatePicker` (data+hora).
      - Diária: `DatePicker` só hora.
      - Semanal: chips/toggles de dias da semana + hora.
      - Mensal: `Picker`/stepper dia (1–31) + hora.
      - Anual: mês + dia + hora.
      - N-ésimo: posição (1ª/2ª/3ª/4ª/última) + dia da semana + hora.
      - Intervalo: valor + unidade (min/h).
    - `Picker` de som + "Nenhum"; tocar preview na seleção (`NSSound(named:)?.play()`).
      Nomes válidos (de `/System/Library/Sounds`, verificado): `Basso, Blow, Bottle,
      Frog, Funk, Glass, Hero, Morse, Ping, Pop, Purr, Sosumi, Submarine, Tink`.
    - `TextField` opcional "abrir ao clicar" (URL).
  - Resumo humano do schedule: uma função pura `describe(_ r: Reminder) -> String`.

Janela hoje é `.frame(width: 340).fixedSize()`; a aba de lista precisa de mais
altura — ajustar o frame do `TabView` (largura ~360, altura confortável).

## Arquivos

| Arquivo                 | Mudança                                                        |
|-------------------------|---------------------------------------------------------------|
| `Reminders.swift`       | **novo** — `Reminder`, `Schedule`, `ReminderScheduler`, self-check |
| `RemindersView.swift`   | **novo** — aba de lista + formulário criar/editar             |
| `AppSettings.swift`     | `@Published var reminders` (JSON em UserDefaults); `SettingsView` → `TabView` |
| `KnoblerApp.swift`      | instanciar/fiar `ReminderScheduler` em `didFinishLaunching`   |
| `NotificationInterceptor.swift` | `NotchNotification` ganha `var openURL: String? = nil` |
| `NotchView.swift`       | `openSourceApp` abre `openURL` quando presente                 |
| `project.yml`           | sem mudança (arquivos entram por diretório `sources: Knobler`) |
| `tools/snapshot.sh`     | sem mudança (nada novo é usado pela `NotchView`)               |

## Cortado da v1

- Soneca/snooze — o banner some em 5s; adicionar depois muda a interação do card.
- Agendar via API HTTP (`POST /schedule`) — UI-only por ora; enum já permitiria.
- Master-toggle da feature — cada lembrete já tem `enabled`.
- Campo de ícone/SF-Symbol por lembrete — emoji no título resolve sem código.
