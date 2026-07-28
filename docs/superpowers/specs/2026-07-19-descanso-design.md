# Spec — Descanso (bloqueio forçado de tela)

Bloqueio de tela agendado que **força uma pausa**: na hora marcada, cobre todas
as telas com um overlay escuro + contador regressivo e trava a interação até o
tempo acabar. Reusa o motor de agenda dos Lembretes (`Schedule`/`ReminderClock`)
e é acionável por dois gatilhos: a **lista própria** (aba "Descanso") e as
**pausas do Pomodoro** (via toggle). Feature nova, separada do Pomodoro.

## Princípios

- Coerente com o produto: escurece, não enfeita. Sem chrome, sem card — só o
  escuro, o contador e um rótulo. Fade suave (~0.4s), motion a serviço da clareza.
- Reusa o que já existe: mesma matemática de agenda dos Lembretes (`Schedule`,
  `ReminderClock`, política "nunca atrasado"). Zero duplicação da lógica de tick.
- Teto honesto: um app não-root não trava 100% o Mac. Fazemos o **máximo nativo**
  (modo quiosque: `disableForceQuit` + `disableProcessSwitching`), mas a pesquisa
  mostrou que escapam também **Cmd+Q**, **Spotlight** e o Monitor de Atividade
  (ver Achados). É um **empurrão com atrito real, não um lock de segurança** —
  coerente com deixar a dica de escape visível. Não fingimos ser um kernel lock.
- Segurança primeiro: **válvula de emergência** sempre presente (segurar Esc 5s),
  com dica fixa no rodapé — nunca prender o usuário numa call/apresentação/emergência.
- Núcleo do modelo só-`Foundation` com self-check (molde de `Reminders.swift`/
  `Pomodoro.swift`). A janela/quiosque vive à parte, em AppKit.

## Modelo de dados

Persistido como JSON (`[ScreenBreak]`) em `UserDefaults` (chave `screenBreaks`),
exposto em `AppSettings` como `@Published var screenBreaks: [ScreenBreak]` (mesmo
padrão dos Lembretes — a UI edita, a engine lê no tick).

```swift
struct ScreenBreak: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var label: String = ""          // opcional; mostrado no overlay; fallback "descanse um pouco"
    var schedule: Schedule          // reusa o enum dos Lembretes
    var durationMinutes: Int = 5    // quanto a tela fica travada (1–120)
    var enabled: Bool = true        // pausar sem apagar
}
```

`Schedule` (de `Reminders.swift`) é reaproveitado inteiro: `.oneShot(Date)`,
`.calendar([DateComponents])`, `.interval(minutes:)`. **Não** há case novo.

### Mapeamento dos modos do picker → `Schedule`

Os 7 modos dos Lembretes + **"Daqui a X"** (o 8º, exigido pela ideia original;
não existe nos Lembretes porque eles só usam horário absoluto):

| Modo (UI)            | Vira                                                    |
|----------------------|--------------------------------------------------------|
| **Daqui a X** (min/h)| `oneShot(Date() + X)` — calculado **no save**          |
| Uma vez              | `oneShot(Date)`                                         |
| Diária               | `calendar([{hour, minute}])`                           |
| Semanal (dias)       | `calendar([{weekday, hour, minute}])` — um por dia     |
| Mensal (dia do mês)  | `calendar([{day, hour, minute}])`                     |
| Anual                | `calendar([{month, day, hour, minute}])`              |
| N-ésimo dia da semana| `calendar([{weekdayOrdinal, weekday, hour, minute}])` |
| Intervalo            | `interval(minutes:)`                                  |

**"Daqui a X" é açúcar de UI, não enum novo:** o formulário só computa
`oneShot(now + X·60)` no momento de salvar. Consequência (aceita): ao **reabrir**
pra editar, aparece como "Uma vez" no horário absoluto resultante. Re-salvar no
modo "Daqui a X" re-ancora a partir de agora. `// ponytail: relativo é UI; sem case novo no Schedule`

## Engine — generalizar o scheduler dos Lembretes

O `ReminderScheduler` já tem a lógica sutil que o Descanso precisa igual
(dedup, "nunca atrasado", re-âncora de intervalo, observer de wake). Duplicar
isso = dois lugares pra bug de timing divergir. Então **generaliza** sobre um
protocolo, em vez de um segundo scheduler.

```swift
protocol Scheduled: Identifiable where ID == UUID {
    var enabled: Bool { get }
    var schedule: Schedule { get }
}
extension Reminder: Scheduled {}
extension ScreenBreak: Scheduled {}

final class ScheduleEngine<Item: Scheduled> {   // era ReminderScheduler
    var itemsProvider: () -> [Item] = { [] }     // era remindersProvider
    var onFire: ((Item) -> Void)?
    var tolerance: TimeInterval = 90
    func start(); func stop(); func tick(now: Date = Date())
}
typealias ReminderScheduler = ScheduleEngine<Reminder>   // mantém o nome no resto do código
```

- O corpo do `tick`/`computeNext`/`nextFire` **não muda** — só troca `Reminder`
  por `Item` e `remindersProvider` por `itemsProvider`. `r.schedule.hashValue`,
  `onFire?(r)`, tudo genérico-safe.
- Sítios tocados: declaração/uso em `AppDelegate` (`remindersProvider` →
  `itemsProvider`) e o self-check de `Reminders.swift` (idem). O `typealias`
  segura o nome `ReminderScheduler` onde já é usado.
- **Regra "nunca atrasado" vale igual pro Descanso:** dormiu na hora do disparo
  → pula (você já estava longe do PC, o objetivo se cumpriu sozinho).

## Overlay + quiosque — `DescansoController`

Arquivo novo, AppKit+SwiftUI (NÃO só-Foundation — mexe em janela/`NSApp`). É o
controlador reutilizável acionado pelos dois gatilhos.

```swift
final class DescansoController {
    private(set) var isActive = false
    var onEnd: (() -> Void)?
    func begin(label: String, duration: TimeInterval)   // ignora se já ativo
    func abort()                                         // fim antecipado (Esc 5s)
}
```

### Ciclo de um bloqueio

1. **Um por vez:** se `isActive`, `begin` é ignorado (não empilha).
   `// ponytail: um lock ativo por vez; enfileirar só se algum dia precisar`
2. `endDate = Date() + duration`. Publica num pequeno `ObservableObject`
   (`endDate`, `label`, `holdProgress`) que as views observam.
3. **Uma janela por tela** (`NSScreen.screens`), cobrindo `screen.frame`:
   - `styleMask: [.borderless]`, `isOpaque = false`, `backgroundColor = .clear`.
   - `level = CGShieldingWindowLevel()` — medido = 2.147.483.628, acima de tudo,
     inclusive do notch (`.mainMenu + 3` = 27). **Confirmado**: é o nível que dá o
     z-order (cobre barra de menus e outras janelas); precedente real csexton/
     full-screen-overlay. Com `.hideMenuBar` a barra some de qualquer jeito.
   - `collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]`
     — ⚠️ estes **não** empilham por cima (isso é o nível): `.canJoinAllSpaces`
     faz o shield **seguir** o usuário se ele trocar de Space; `.fullScreenAuxiliary`
     o torna visível no Space de um app em tela cheia. Cobrir um full screen de
     verdade é item de validação empírica (ver Achados).
   - `contentView = NSHostingView(rootView: BreakOverlayView(model:))`.
4. **Ativa + quiosque:** `NSApp.setActivationPolicy(.regular)`,
   `NSApp.activate(ignoringOtherApps: true)`, janela principal `makeKeyAndOrderFront`
   (override `canBecomeKey = true`), e:

```swift
NSApp.presentationOptions = [
    .hideDock, .hideMenuBar, .disableAppleMenu,
    .disableForceQuit, .disableProcessSwitching, .disableSessionTermination,
]
```

   ⚠️ **Regra de validade da Apple (senão lança `NSInvalidArgumentException`):**
   `.hideMenuBar` exige `.hideDock`; os `.disable*` exigem `.hideDock`/`.autoHideDock`.
   O conjunto acima satisfaz — **confirmado** (Kiosk Mode TN + precedente SplashBuddy,
   ver Achados). As opções só valem com o app **ativo** e **revertem sozinhas** quando
   outro app fica ativo → ativar o app **antes** de setá-las.
   ⚠️ **Cmd+Q escapa** (não é coberto por nenhuma flag): bloquear à parte —
   `applicationShouldTerminate` devolve `.terminateCancel` enquanto `isActive`.
5. **Fade in:** janelas entram com `alphaValue = 0` e animam pra `1` em ~0.4s
   (`NSAnimationContext`, ease-out). Fade out simétrico no fim.
6. **Contador sleep-proof:** um `Timer` de ~0.25s recomputa
   `remaining = endDate.timeIntervalSinceNow` (nunca decrementa um contador). Dormiu
   e acordou → o timer volta e lê o `endDate` real. Se `remaining <= 0` → `end()`.
7. **Fim (`end`/`abort`):** fade out → fecha janelas → `NSApp.presentationOptions = []`
   → `NSApp.setActivationPolicy(.accessory)` → `isActive = false` → `onEnd?()`.
   App morto no meio (kill/crash) encerra tudo pelo SO; **não** ressuscita ao
   reabrir (o estado é só em memória — é a válvula de último caso + segurança).

### Escape de emergência (segurar Esc 5s)

- `NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp])` enquanto ativo
  (o app está `.regular` + key window, então recebe). Esc = keyCode 53.
- `keyDown` (ignorar `isARepeat`) inicia o hold; o timer de tick preenche
  `holdProgress` (0→1 em 5s); `keyUp` zera. `holdProgress >= 1` → `abort()`.
- Engole o Esc (retorna `nil` do monitor) pra não vazar pro app de trás.
- **Recorrente:** `abort()` encerra só a ocorrência de agora; o agendamento segue
  armado (não mexe em `enabled`). O oneShot/relativo já se auto-desliga ao disparar,
  não no abort.

### Multi-monitor

Uma janela dimmed por tela; todas leem o mesmo `endDate`/`holdProgress`, então o
contador e o anel de hold aparecem iguais em todos os monitores. Uma janela por
`NSScreen` (não uma esticada) — confirmado pelo SplashBuddy.

## Achados da pesquisa (verificados — não presumir de memória)

Símbolos compilados localmente (Swift 6.3.3, target `macosx26`); regras e
comportamento cruzados com doc/campo. Fontes ao fim.

### Quiosque (`presentationOptions`) — regras e realidade

- **O conjunto da spec é VÁLIDO.** Regra canônica (Apple *Kiosk Mode Technical
  Note*): `.hideMenuBar` exige `.hideDock`; `.disableForceQuit`/
  `.disableProcessSwitching`/`.disableSessionTermination` exigem `.hideDock` **ou**
  `.autoHideDock`; `.disableAppleMenu` **não** tem dependência; `hideDock`⊕
  `autoHideDock` e `hideMenuBar`⊕`autoHideMenuBar` são mutuamente exclusivos.
  Combinação inválida → `setPresentationOptions` **lança `NSInvalidArgumentException`**.
  O conjunto `[.hideDock, .hideMenuBar, .disableAppleMenu, .disableForceQuit,
  .disableProcessSwitching, .disableSessionTermination]` satisfaz tudo. Precedente
  de produção: **SplashBuddy** (macadmins) usa quase o mesmo.
- **Só valem com o app ATIVO** e **revertem sozinhas (KVO) quando outro app fica
  ativo.** Ordem: `.regular` → `NSApp.activate(ignoringOtherApps:)` → setar as
  opções. Se o app perde o foco, os bloqueios "duros" lapsam — mas o **shield
  visual não** (nível de janela independe de estar ativo).
- **Cobertura real (o teto honesto de verdade):** bloqueia **Force Quit (⌥⌘Esc),
  Cmd-Tab, Dock e barra de menus**. **NÃO** bloqueia: **Cmd+Q** do próprio app (!),
  **Spotlight (⌘Espaço)**, Mission Control / troca de Space, Notification/Control
  Center, Terminal. Escapes na prática: Monitor de Atividade, Spotlight→matar
  processo, Cmd+Q. → **empurrão com atrito, não lock de segurança.**
- **Cmd+Q → tratar à parte:** `applicationShouldTerminate` devolve `.terminateCancel`
  enquanto um lock está ativo (as flags não pegam Cmd+Q).
- **Lock "de verdade" existe mas é vetado:** `AEAssessmentSession`
  (`AutomaticAssessmentConfiguration`, macOS 10.15.4+) bloqueia Spotlight/Dictation/
  Notification Center, mas exige o entitlement restrito
  `com.apple.developer.automatic-assessment-configuration`, aprovado caso-a-caso pela
  Apple pra apps de prova. Fora do escopo do Knobler.

### Janela de shield

- **`CGShieldingWindowLevel()` (= 2.147.483.628) é o nível certo** pro z-order: cobre
  barra de menus e fica acima de outras janelas. `.canJoinAllSpaces`/
  `.fullScreenAuxiliary` **não** empilham por cima — só dão presença em Spaces; quem
  empilha é o nível. Usar os dois juntos.
- **Boato descartado:** "CGShieldingWindowLevel não funciona no macOS 15+" era sobre
  *captura de tela* (framebuffer já composto pelo ScreenCaptureKit), **não** z-order
  de exibição. Não afeta o overlay.

### A validar empiricamente na implementação (doc não prova)

- Cobrir um app genuinamente em **tela cheia** (Space dedicado) — shield level +
  `.fullScreenAuxiliary` deve resolver; testar.
- Se banners de **Notificação** vazam por cima do shield (Tahoe só liga DND
  automático em mirroring, não em full screen). Se incomodar, ligar DND no lock.
- O **monitor local de `.keyDown`** pegando o Esc com o app `.regular` + key window.

### Fontes

- Kiosk Mode Technical Note (regras de combinação) — developer.apple.com/library/archive/technotes/KioskMode/
- TN2062 "Creating Kiosks" (reset por KVO; buracos de escape) — developer.apple.com/library/archive/technotes/tn2062/
- `presentationOptions` / `disableProcessSwitching` — developer.apple.com/documentation/appkit/nsapplication
- SplashBuddy (conjunto de flags em produção) — github.com/macadmins/SplashBuddy
- `AEAssessmentSession` + entitlement restrito — developer.apple.com/documentation/automaticassessmentconfiguration
- `CGShieldingWindowLevel()` — developer.apple.com/documentation/coregraphics/cgshieldingwindowlevel()
- csexton/full-screen-overlay (shield level em uso) — github.com/csexton/full-screen-overlay
- z-order sobre full screen (resposta de eng. Apple) — developer.apple.com/forums/thread/26677
- Ignorar Cmd+Q em LSUIElement — developer.apple.com/forums/thread/743070

## View do contador — `BreakOverlayView`

SwiftUI puro (sem janela/`NSApp`), pra entrar no harness de snapshot. Observa o
`ObservableObject` do controller.

- Fundo: `Color.black.opacity(0.9)` cobrindo tudo (a tela aparece fantasma ~10%
  atrás). `// ponytail: 0.9 é o único knob de "quão escuro"; ajustar aqui`
- Centro: contador grande (SF Pro ~72pt, `ink`). `mm:ss`; se `remaining >= 3600`
  vira `h:mm:ss` (duração vai até 120min).
- Abaixo: rótulo pequeno (`ink-tertiary`) — `label` do bloqueio, ou "Pausa do
  Pomodoro", ou fallback "descanse um pouco".
- Rodapé (fixo): "segurar Esc para sair" (`label` mono 9pt, `ink-muted`). Enquanto
  segura, um anel/barra fina preenche com `holdProgress`.

Segue o `DESIGN.md` (cores `ink*`, SF Pro/SF Mono, motion ease-out sem bounce).

## Gatilho 1 — lista de Descanso (`onFire`)

No `AppDelegate`, em `didFinishLaunching`:

```swift
breakScheduler.itemsProvider = { AppSettings.shared.screenBreaks }
breakScheduler.onFire = { [weak self] b in
    self?.descanso.begin(label: b.label,
                         duration: TimeInterval(max(1, b.durationMinutes) * 60))
    // oneShot/relativo dispara uma vez → desliga (fica na lista, off)
    if case .oneShot = b.schedule,
       let i = AppSettings.shared.screenBreaks.firstIndex(where: { $0.id == b.id }) {
        AppSettings.shared.screenBreaks[i].enabled = false
    }
}
breakScheduler.start()
```

O observer de wake que já existe pros Lembretes passa a tickar os dois:
`{ self?.reminderScheduler.tick(); self?.breakScheduler.tick() }`.

## Gatilho 2 — pausas do Pomodoro

Toggle novo `AppSettings.pomodoroLockScreen` (default `false`). O lock precisa
disparar quando uma **pausa começa a rodar** (não no fim do foco, que hoje só vai
pra `.waiting`). Adiciona um hook no `Pomodoro`:

```swift
// Pomodoro.swift — chamado no fim de beginRunning(phase:)
var onPhaseBegin: ((PomodoroPhase) -> Void)?
```

No `AppDelegate`:

```swift
pomodoro.onPhaseBegin = { [weak self] phase in
    guard AppSettings.shared.pomodoroLockScreen,
          phase == .shortBreak || phase == .longBreak else { return }
    let dur = Pomodoro.duration(of: phase, config: .fromSettings())
    self?.descanso.begin(label: "Pausa do Pomodoro", duration: dur)
}
```

- O card do Pomodoro fica coberto pelo overlay — a pausa é forçada. O timer da
  pausa corre por baixo; lock e pausa acabam juntos (mesmo relógio de parede).
- Escape num lock do Pomodoro encerra **só o overlay**; a pausa segue contando
  destravada. `// ponytail: escape não pula a fase do Pomodoro`

## UI — aba "Descanso"

`SettingsView` (hoje `TabView` com Geral + Lembretes) ganha a 3ª aba "Descanso"
(`systemImage: "moon.zzz"` ou `"lock.display"`), no molde do `RemindersView`:

- Lista de `AppSettings.shared.screenBreaks`: cada linha mostra `label` (ou
  "(sem nome)"), resumo humano do schedule (reusa `ReminderClock.humanCalendar`/
  `humanInterval`) + "· Nmin de bloqueio", `Toggle` de `enabled`, swipe apagar;
  tap edita. `ContentUnavailableView` quando vazia.
- Botão **"+"** → formulário (sheet) criar/editar:
  - `TextField` "Nome (opcional)".
  - `Picker` de frequência (8 modos: **Daqui a X** + os 7) → revela os campos do
    modo (mesmo layout do `ReminderFormView`: chips de dias, stepper de dia,
    posição n-ésima, etc.).
  - `Stepper` **"Bloquear por: N min"** (1–120), default 5.
  - Sem campos de som/URL (não fazem sentido aqui).

**Duplicação do picker de frequência (deliberada):** o layout dos 8 modos
espelha o `ReminderFormView`. É layout mecânico (baixo risco); duplicar isola o
Descanso sem tocar o form de Lembretes já testado. Extrair um `SchedulePickerView`
compartilhado fica pro dia em que aparecer um 3º consumidor (regra de três).
`// ponytail: duplica o layout; abstrai na 3ª vez, não na 2ª`

## Snapshot

`BreakOverlayView` é snapshot-able (SwiftUI puro). Em `tools/snapshot.sh`,
adicionar `Knobler/Descanso.swift` e `Knobler/DescansoView.swift` à lista do
`swiftc`; em `tools/main.swift`, um cenário renderizando o overlay (ex: 14:32 +
"Almoço", e um com hold a 60%) sobre um fundo fake pra ver o "fantasma".

## Arquivos

| Arquivo                 | Mudança                                                             |
|-------------------------|--------------------------------------------------------------------|
| `Descanso.swift`        | **novo** — `ScreenBreak`, conformance `Scheduled`, self-check (mapeamento modos↔Schedule, "Daqui a X", duração). Só `Foundation` (usa `Schedule`/`ReminderClock` de `Reminders.swift`). |
| `DescansoView.swift`    | **novo** — `BreakOverlayView` (contador/rótulo/rodapé) + aba de Ajustes (lista + formulário 8 modos + duração). SwiftUI. |
| `DescansoController.swift` | **novo** — janelas por tela, nível de shield, quiosque (`presentationOptions`), captura + Esc-hold, contador sleep-proof, fade. AppKit. |
| `Reminders.swift`       | `ReminderScheduler` → `ScheduleEngine<Item: Scheduled>` genérico + `protocol Scheduled` + `typealias`; `remindersProvider`→`itemsProvider`; self-check ajustado. |
| `Pomodoro.swift`        | `var onPhaseBegin: ((PomodoroPhase) -> Void)?` chamado no fim de `beginRunning`. |
| `AppSettings.swift`     | `@Published var screenBreaks` (JSON) + `@Published var pomodoroLockScreen` (default false); 3ª aba "Descanso" + toggle "Travar a tela nas pausas" na seção Pomodoro. |
| `KnoblerApp.swift`      | instanciar/fiar `breakScheduler` + `descanso` (DescansoController), `pomodoro.onPhaseBegin`, `itemsProvider` renomeado, wake ticka os dois; `applicationShouldTerminate` → `.terminateCancel` enquanto `descanso.isActive` (bloqueia Cmd+Q). |
| `tools/snapshot.sh`     | +`Descanso.swift` +`DescansoView.swift` na lista do `swiftc`.       |
| `tools/main.swift`      | cenário renderizando `BreakOverlayView`.                            |
| `project.yml`           | sem mudança (arquivos entram pelo diretório `sources: Knobler`).    |

## Cortado da v1

- **Master-toggle da feature** — cada bloqueio já tem `enabled`.
- **Agendar via API HTTP** (`POST /break`) — UI-only por ora; o enum já permitiria.
- **`SchedulePickerView` compartilhado** — só na 3ª reutilização (regra de três).
- **Pausar mídia no bloqueio** — decidido: áudio continua tocando.
- **Auto-remover oneShot gasto da lista** — v1 só desliga (`enabled=false`),
  consistente com Lembretes; usuário apaga se quiser.
- **Bloqueio "infinito" / até um horário** — v1 é sempre por duração fixa.
- **Lock "de verdade" (bloquear Spotlight/Terminal/etc.)** — só via
  `AEAssessmentSession`, que exige entitlement aprovado pela Apple pra apps de prova.
  Fora do alcance; Descanso é empurrão com atrito, não segurança. Assumido.
