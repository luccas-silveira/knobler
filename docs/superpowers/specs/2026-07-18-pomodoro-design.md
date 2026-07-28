# SPEC — Pomodoro no Knobler

Timer de foco no notch. Reaproveita a arquitetura que já existe (`CalendarCountdown`
como molde do engine, pílula compacta no naipe do `dictationPill`, notificação via
`vm.enqueue`, som via `NSSound`). Controlado pelo menu da barra.

## Objetivo

Um Pomodoro clássico (foco → pausa → …) visível de relance no notch, com ritmo
intencional: o timer para no fim de cada fase e espera o usuário iniciar a próxima.

**Não-objetivos (v1):** endpoint na API local, atalho global de teclado, stats/
histórico, sobreviver a quit/crash, pausar no sleep, pontinhos de ciclo, card de
pomodoro expandido no hover.

## Decisões travadas

| # | Decisão | Escolha |
|---|---------|---------|
| 1 | Controle | Menu da barra (`NSStatusItem`) |
| 2 | Fases | Clássico configurável: foco 25 / pausa curta 5 / pausa longa 15 / a cada 4 focos |
| 3 | Exibição | Pílula própria no notch, número + cor por fase |
| 4 | Convivência | Toma conta do estado fechado enquanto ativo; HUD interrompe 1,5s e volta |
| 5 | Transição | Para no fim da fase → avisa (notch + som) → espera o usuário iniciar |
| 6 | Espera | Pílula fixa com a próxima ação até iniciar pelo menu |
| 7 | Sono/tempo | Relógio de parede (`endDate` absoluto), some ao fechar o app |

## Máquina de estados

**Fase** (`enum Phase`): `.focus`, `.shortBreak`, `.longBreak`
**Estado de execução** (`enum RunState`): `.idle`, `.running`, `.paused`, `.waiting`

Campos do engine:
- `phase: Phase` — fase corrente (em `.waiting` já aponta pra PRÓXIMA fase)
- `runState: RunState`
- `endDate: Date?` — só em `.running`; regressivo = `endDate − Date()`
- `remaining: TimeInterval?` — congelado em `.paused`
- `completedFocusSessions: Int` — focos concluídos ao natural (define a pausa longa)

Transições:

```
.idle ──start()──▶ .running(phase=.focus, endDate=now+focoDur)

.running ──pause()──▶ .paused  (remaining = endDate−now, endDate=nil)
.paused  ──resume()─▶ .running (endDate = now+remaining)

.running ──tick vê endDate≤now──▶ .waiting
    se phase==.focus: completedFocusSessions += 1
    phase = próximaFase()            // ver abaixo
    notifica + som
    (endDate=nil)

.waiting ──startNext()──▶ .running (endDate = now+dur(phase))

qualquer ──skip()──▶ .running na próxima fase, começa a rodar já
    (skip é ação explícita = "próxima agora", NÃO conta foco, NÃO espera)

qualquer ──reset()──▶ .idle (zera completedFocusSessions)
```

`próximaFase()`:
```
se fase concluída era .focus:
    (completedFocusSessions % cyclesUntilLong == 0) ? .longBreak : .shortBreak
senão (era pausa):
    .focus
```

`dur(phase)` lê os valores de `AppSettings` (minutos → segundos).

## Modelo de dados no ViewModel

`NotchViewModel` ganha:
```swift
@Published var pomodoro: PomodoroState?   // nil = idle (sem pílula)
struct PomodoroState: Equatable {
    var phase: Phase
    var runState: RunState        // running | paused | waiting
    var remaining: TimeInterval   // já calculado pelo engine, pronto pra formatar
}
```
O engine publica esse struct a cada tick (1s) e nas transições. `nil` quando `.idle`.

Prioridade de `Mode` (em `NotchViewModel.mode`):
```
question > dictation > notification > hud > music(expandido) > pomodoro > closed
```
Novo `case pomodoro`. Fica ABAIXO de hud/notification → HUD de volume/brilho e
notificações interrompem por 1,5s/5s e voltam pro pomodoro de graça. Fica ACIMA de
closed e ABAIXO de music → hover ainda expande o card de música pra controlar áudio.

```swift
if ask != nil { return .question }
if dictation != nil { return .dictation }
if activeNotification != nil { return .notification }
if hud != nil { return .hud }
if expanded { return .music }
if pomodoro != nil { return .pomodoro }
return .closed
```

## Rendering — `pomodoroPill`

Novo estado compacto no `NotchView`, no mesmo naipe de `hudPill`/`dictationPill`
(mesma largura de asa `hudWingWidth`, respeitando `hasRealNotch`). Recortado pela
`NotchShape` como os outros. `.transition(.blurReplace)`.

Conteúdo por estado:
- `.running` foco → `🍅 23:14` (tom vermelho/laranja)
- `.running` pausa → `☕ 04:32` (tom verde)
- `.paused` → mesmo, com ícone de pause (`⏸`) e o número estático
- `.waiting` → próxima ação: `☕ Pausa ▸ 5:00` / `🍅 Foco ▸ 25:00` (▸ = "clique Iniciar no menu")

Cor por fase, não só ícone (acessibilidade — daltonismo): foco = laranja/vermelho,
pausa (curta e longa) = verde. Rótulo "Pausa" / "Pausa longa" distingue as duas.
Formato do tempo: `MM:SS` via `String(format: "%02d:%02d", …)`.

Sizing: adicionar `case .pomodoro` junto de `.hud`/`.dictation` em `currentSize` e no
`compact` de `notch` (raios menores). Largura: `notchSize.width + hudWingWidth*2` no
notch real; ~232 no externo (igual hud/dictation).

## Menu da barra

`AppDelegate` vira `NSMenuDelegate`; o menu do `statusItem` reconstrói os itens de
Pomodoro em `menuNeedsUpdate(_:)` conforme o `runState`. Itens acima do separador de
"Ajustes…". Todos com `.target = self`.

| Estado | Itens |
|--------|-------|
| `.idle` | `▶ Iniciar foco (25 min)` |
| `.running` | `⏸ Pausar` · `⏭ Pular fase` · `↺ Resetar` |
| `.paused` | `▶ Retomar` · `⏭ Pular fase` · `↺ Resetar` |
| `.waiting` | `▶ Iniciar pausa (5 min)` (ou `Iniciar foco`) · `↺ Resetar` |

As durações no rótulo vêm de `AppSettings`. Ações chamam os métodos do engine.

## Notificação + som (fim de fase)

Na transição pra `.waiting`:
- `vm.enqueue(NotchNotification(appName: "Pomodoro", title: <título>, body: <corpo>))`
  - foco→pausa: "Foco concluído" / "Hora da pausa — 5 min"
  - pausa→foco: "Pausa acabou" / "Bora focar — 25 min"
- Se `AppSettings.pomodoroSound`: `NSSound(named: "Glass")?.play()` (precedente:
  `NSSound(named: "Pop")` já usado no app).

## Settings — seção "Pomodoro"

Nova `Section("Pomodoro")` no `SettingsView`, campos persistidos em `UserDefaults`
(padrão do `AppSettings`):
```
Foco (min):           [25]   pomodoroFocus        default 25
Pausa curta (min):    [ 5]   pomodoroShortBreak   default 5
Pausa longa (min):    [15]   pomodoroLongBreak    default 15
Focos até pausa longa:[ 4]   pomodoroCyclesLong   default 4
Som ao trocar de fase: (on)  pomodoroSound        default true
```
Sem toggle master — o menu é o liga/desliga. Ints via `Stepper`/`TextField`;
clamp mínimo 1 min pra não zerar o timer.

## Correção de tempo

- Regressivo sempre = `endDate − Date()` (relógio de parede). `Timer` de 1s só
  atualiza o display; um tick perdido não acumula erro.
- Mac dorme → `Timer` não dispara; no wake o primeiro tick recalcula pelo `endDate`
  (o tempo "correu" durante o sono; pode já ter estourado a fase → cai em `.waiting`).
- Estado é in-memory; fechar o Knobler zera (`.idle`).

## Arquivos tocados

- **`Knobler/Pomodoro.swift`** (novo) — engine: `Phase`, `RunState`, `PomodoroState`,
  a classe `Pomodoro` (métodos start/pause/resume/skip/reset/startNext, `próximaFase`,
  `Timer`, callback `onState`). Self-check `#if DEBUG` do `próximaFase`/ciclo.
- **`Knobler/NotchViewModel.swift`** — `@Published var pomodoro`, `case pomodoro` no
  `Mode` e na prioridade.
- **`Knobler/NotchView.swift`** — `pomodoroPill` + `case .pomodoro` em `notch`/`currentSize`.
- **`Knobler/AppSettings.swift`** — 5 prefs + campos na `Section("Pomodoro")`.
- **`Knobler/KnoblerApp.swift`** — instancia o engine, fia `onState → vm.pomodoro`,
  `NSMenuDelegate` + itens de menu + ações.
- **`tools/`** — estado `pomodoro` no harness de snapshot; gerar `Snapshots/pomodoro*.png`.

## Self-check (obrigatório — ponytail)

No `Pomodoro.swift`, `#if DEBUG` rodado no launch (padrão do projeto):
```
assert nextPhase após foco #1..#3 == .shortBreak
assert nextPhase após foco #4 (cyclesLong=4) == .longBreak
assert nextPhase após qualquer pausa == .focus
assert skip de um foco NÃO incrementa completedFocusSessions
assert pause→resume preserva remaining (± tolerância de 1s)
```

## Gate visual

`tools/snapshot.sh` deve renderizar os estados `pomodoro` (foco rodando, pausa
rodando, espera) e os PNGs olhados antes de fechar — é o gate de UI do projeto.
