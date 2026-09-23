# AirPods animados no notch — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Trocar o card estático de AirPods por uma ilha compacta animada (conexão) que vira card grande com um anel de bateria por peça (hover ou bateria baixa), com ícone do modelo certo.

**Architecture:** O modelo (`AirPodsBattery`) passa a saber o modelo do fone pelo `device_productID` e expõe os SF Symbols. O `BluetoothMonitor` diz o motivo do anúncio. `NotchContentState` ganha um estado `airpodsIsland` na mesma prioridade do card. O `NotchViewModel` decide ilha ou card e segura o timer no hover. As views novas moram em `Knobler/AirPodsViews.swift`, reusando `ActivityRingView`.

**Tech Stack:** Swift 5, SwiftUI (macOS 14.2), `symbolEffect` (macOS 14), XcodeGen, harnesses `tools/*check*.swift`, `tools/snapshot.sh`.

**Spec:** `docs/superpowers/specs/2026-09-22-airpods-animados-design.md` (decisões em `## Decisões do grill`). Dossiê: `docs/superpowers/research/2026-09-22-airpods-animados-research.md`.

## Global Constraints

- Deployment target macOS 14.2. Símbolo ou API mais novo só com `if #available(macOS 15.2, *)` e fallback.
- Usar os nomes de SF Symbols pré-macOS 15 (`airpodspro`, `airpodpro.left`, …), nunca `airpods.pro*`.
- Comentários e strings de UI em pt-BR. Simplificação deliberada marcada com `// ponytail:`.
- Nunca editar `Knobler.xcodeproj`; arquivo novo em `Knobler/` exige `xcodegen generate`.
- `.swift` novo que a `NotchView` use entra em `tools/notchview-fontes.txt`.
- Não editar `MARKETING_VERSION` nem criar tag; mudanças vão em `## [Unreleased]` do `CHANGELOG.md`.
- Limite de bateria baixa: ≤ 10 % (vermelho). Carga normal: verde.
- Ilha ~3 s; card por bateria baixa ~5 s; saída do hover reagenda ~1 s.
- **Pré-requisito:** `NotchView.swift`, `NotchViewModel.swift`, `KnoblerApp.swift`, `NotchPresentation.swift`, `CHANGELOG.md` e `tools/main.swift` (via `tools/check.sh`/`notchview-fontes.txt`) têm mudanças não commitadas da peça Monitores. Commitar esse trabalho antes de começar; senão os commits daqui arrastam código alheio (não há `git add -p` neste ambiente).
- Gate final: `./tools/check.sh` verde e `xcodebuild … build CODE_SIGNING_ALLOWED=NO` sem erro.

## Review Focus

1. Cursor já parado sobre o notch quando a ilha aparece: não chega `onHover(true)`, então a ilha some sozinha em 3 s sem promover — aceitável; conferir que não abre o card de música depois (Task 3, passo de hover).
2. Volume/brilho durante a ilha: o HUD toma o lugar e, se sobrar tempo, a ilha volta; ao acabar, o notch fecha — sem abrir o card de música (Task 2, asserção de prioridade).
3. Desconectar com a ilha ou o card na tela: os dois somem na hora e nenhum timer pendente reabre nada (Task 3, `dismissAirPods`).
4. Fone com só um lado reportando (o outro no estojo): ilha usa o nível que existe; card mostra anel vazio e "—" no lado ausente (Task 1 `islandLevel`, Task 4 pose).
5. `device_productID` ausente, minúsculo (`"0x200e"`) ou lixo: vira `.unknown` com ícone genérico, sem crash (Task 1).

---

### Task 1: Modelo do fone a partir do Product ID

**Files:**
- Modify: `Knobler/AirPodsBattery.swift`
- Test: `tools/airpods_selfcheck.swift`

**Interfaces:**
- Produces:
  - `enum AirPodsModel: Equatable { case pro, gen12, gen3, gen4, max, unknown }` com `init(productID: Int?)`, `var pairSymbol: String`, `var leftSymbol: String`, `var rightSymbol: String`, `var caseSymbol: String?`.
  - `AirPodsBattery.model: AirPodsModel` (default `.unknown`, último campo — o init memberwise existente continua compilando).
  - `AirPodsBattery.islandLevel: Int?` = menor entre `left` e `right` reportados.
  - `static func AirPodsBattery.isLow(_ level: Int) -> Bool` (≤ 10).
  - `enum AirPodsAnnounce: Equatable { case connected, lowBattery }`.

- [ ] **Step 1: Escrever os testes que falham**

Acrescentar em `tools/airpods_selfcheck.swift`, antes do `print`:

```swift
        // modelo pelo device_productID (string hex, qualquer caixa)
        let pro2 = json("""
        { "SPBluetoothDataType": [ { "device_connected": [
          { "AirPods Pro": { "device_batteryLevelLeft": "100%", "device_batteryLevelRight": "90%",
            "device_batteryLevelCase": "82%", "device_minorType": "Headphones",
            "device_productID": "0x2024" } }
        ] } ] }
        """)
        precondition(AirPodsBattery.parse(from: pro2)?.model == .pro, "pro2 usb-c")
        precondition(AirPodsModel(productID: 0x200E) == .pro, "pro1")
        precondition(AirPodsModel(productID: 0x2013) == .gen3, "gen3")
        precondition(AirPodsModel(productID: 0x2019) == .gen4, "gen4")
        precondition(AirPodsModel(productID: 0x201B) == .gen4, "gen4 anc")
        precondition(AirPodsModel(productID: 0x200F) == .gen12, "gen2")
        precondition(AirPodsModel(productID: 0x200A) == .max, "max")
        precondition(AirPodsModel(productID: 0x9999) == .unknown, "desconhecido")
        precondition(AirPodsModel(productID: nil) == .unknown, "sem id")

        // caixa baixa e lixo no campo
        let lower = json("""
        { "SPBluetoothDataType": [ { "device_connected": [
          { "F": { "device_batteryLevelLeft": "50%", "device_minorType": "Headphones", "device_productID": "0x200e" } }
        ] } ] }
        """)
        precondition(AirPodsBattery.parse(from: lower)?.model == .pro, "hex minúsculo")
        let lixo = json("""
        { "SPBluetoothDataType": [ { "device_connected": [
          { "F": { "device_batteryLevelLeft": "50%", "device_minorType": "Headphones", "device_productID": "zz" } }
        ] } ] }
        """)
        precondition(AirPodsBattery.parse(from: lixo)?.model == .unknown, "id lixo")

        // símbolos: nomes pré-macOS 15; Max sem estojo
        precondition(AirPodsModel.pro.leftSymbol == "airpodpro.left", "lado pro")
        precondition(AirPodsModel.gen12.caseSymbol == "airpods.chargingcase", "estojo gen12")
        precondition(AirPodsModel.max.caseSymbol == nil, "max sem estojo")
        precondition(AirPodsModel.unknown.pairSymbol == "airpodspro", "fallback")

        // nível da ilha: menor fone reportado, estojo fora
        precondition(AirPodsBattery(name: "x", left: 80, right: 40, case_: 5).islandLevel == 40, "ilha min")
        precondition(AirPodsBattery(name: "x", left: nil, right: 60, case_: 5).islandLevel == 60, "ilha um lado")
        precondition(AirPodsBattery(name: "x", left: nil, right: nil, case_: 5).islandLevel == nil, "ilha sem fones")
        precondition(AirPodsBattery.isLow(10) && !AirPodsBattery.isLow(11), "limite baixo")
```

- [ ] **Step 2: Rodar e ver falhar**

Run: `xcrun swiftc -parse-as-library -swift-version 5 Knobler/AirPodsBattery.swift tools/airpods_selfcheck.swift -o /tmp/apcheck && /tmp/apcheck`
Expected: erro de compilação `cannot find 'AirPodsModel' in scope`.

- [ ] **Step 3: Implementar**

Em `Knobler/AirPodsBattery.swift`, adicionar à struct:

```swift
    /// Modelo pelo `device_productID`; define os ícones. Último campo com
    /// default pra o init memberwise antigo continuar valendo.
    var model: AirPodsModel = .unknown

    /// O que a ilha mostra: o fone mais descarregado. Estojo fica fora, como no iPhone.
    var islandLevel: Int? { [left, right].compactMap { $0 }.min() }

    /// Mesmo limite do aviso do `BluetoothMonitor`.
    static func isLow(_ level: Int) -> Bool { level <= 10 }
```

No `parse`, trocar o `return` por:

```swift
            let id = (props["device_productID"] as? String)
                .flatMap { Int($0.lowercased().replacingOccurrences(of: "0x", with: ""), radix: 16) }
            return AirPodsBattery(name: name, left: left, right: right, case_: case_,
                                  model: AirPodsModel(productID: id))
```

No fim do arquivo:

```swift
/// Por que o monitor anunciou: conexão abre a ilha, bateria baixa abre o card.
enum AirPodsAnnounce: Equatable { case connected, lowBattery }

/// Modelos pelos Product IDs da Apple (vendor 0x004C). Fonte: AirBattery e
/// status-trio; ver docs/superpowers/research/2026-09-22-airpods-animados-research.md.
enum AirPodsModel: Equatable {
    case pro, gen12, gen3, gen4, max, unknown

    init(productID: Int?) {
        switch productID {
        case 0x200E, 0x2014, 0x2024, 0x2027, 0x2028: self = .pro
        case 0x2002, 0x200F: self = .gen12
        case 0x2013: self = .gen3
        case 0x2019, 0x201B: self = .gen4
        case 0x200A, 0x201F: self = .max
        default: self = .unknown
        }
    }

    /// AirPods 4 só tem símbolo próprio a partir do macOS 15.2; antes usa o da 3ª.
    private var gen4Disponivel: Bool {
        if #available(macOS 15.2, *) { return true }
        return false
    }

    var pairSymbol: String {
        switch self {
        case .pro, .unknown: return "airpodspro"
        case .gen12: return "airpods"
        case .gen3: return "airpods.gen3"
        case .gen4: return gen4Disponivel ? "airpods.gen4" : "airpods.gen3"
        case .max: return "airpodsmax"
        }
    }

    var leftSymbol: String { side("left") }
    var rightSymbol: String { side("right") }

    /// Lados usam o singular ("airpod.left"), exceto o 4, que já nasceu no plural.
    private func side(_ lado: String) -> String {
        switch self {
        case .pro, .unknown: return "airpodpro.\(lado)"
        case .gen12: return "airpod.\(lado)"
        case .gen3: return "airpod.gen3.\(lado)"
        case .gen4: return gen4Disponivel ? "airpods.gen4.\(lado)" : "airpod.gen3.\(lado)"
        case .max: return "airpodsmax"
        }
    }

    /// nil = sem estojo (Max): a coluna some.
    var caseSymbol: String? {
        switch self {
        case .pro, .unknown: return "airpodspro.chargingcase.wireless"
        case .gen12: return "airpods.chargingcase"
        case .gen3: return "airpods.gen3.chargingcase.wireless"
        case .gen4: return gen4Disponivel ? "airpods.gen4.chargingcase.wireless" : "airpods.gen3.chargingcase.wireless"
        case .max: return nil
        }
    }
}
```

- [ ] **Step 4: Rodar e ver passar**

Run: o mesmo comando do Step 2.
Expected: `airpods parser: OK`

- [ ] **Step 5: Commit**

```bash
git add Knobler/AirPodsBattery.swift tools/airpods_selfcheck.swift
git commit -m "feat(airpods): detecta o modelo pelo product ID"
```

---

### Task 2: Estado de apresentação da ilha

**Files:**
- Modify: `Knobler/NotchPresentation.swift:6,20,33,111,143,154`
- Test: `tools/presentationcheck.swift:37-58`

**Interfaces:**
- Consumes: nada das outras tasks.
- Produces:
  - `NotchMode.airpodsIsland`.
  - `NotchContentState.airpodsIsland: Bool` (default `false`).
  - `NotchPresentation.airpodsCardWidth: CGFloat = 380` e `airpodsCardHeight: CGFloat = 112` (estáticos; a `NotchView` lê daqui — decisão A13).

- [ ] **Step 1: Escrever o teste que falha**

Em `tools/presentationcheck.swift`, trocar o trecho `state.update = false … state.airpods = false` por:

```swift
        state.update = false
        state.airpodsIsland = true
        assert(state.mode == .airpods, "card vence a ilha")
        state.airpods = false
        assert(state.mode == .airpodsIsland)
        state.hud = true
        assert(state.mode == .hud, "volume toma o lugar da ilha")
        state.hud = false
        state.airpodsIsland = false
        assert(state.mode == .music)
```

(O `NotchContentState(...)` da linha 35 não muda: `airpodsIsland` tem default.)

Depois do laço `for real in [true, false]` existente, acrescentar:

```swift
        do {
            var layout = NotchPresentation.Layout()
            layout.realNotch = true
            let ilha = NotchPresentation(content: NotchContentState(airpodsIsland: true), layout: layout)
            let hud = NotchPresentation(content: NotchContentState(hud: true), layout: layout)
            assert(ilha.size == hud.size && ilha.compact, "ilha tem o tamanho da pílula")
            let card = NotchPresentation(content: NotchContentState(airpods: true), layout: layout)
            assert(card.size.width == NotchPresentation.airpodsCardWidth)
            assert(card.size.width >= ilha.size.width, "card não pode encolher sob o cursor")
        }
```

- [ ] **Step 2: Rodar e ver falhar**

Run: `xcrun swiftc -parse-as-library -swift-version 5 Knobler/NotchSectionOrder.swift Knobler/NotchPresentation.swift tools/presentationcheck.swift -o /tmp/presentationcheck && /tmp/presentationcheck`
Expected: erro `value of type 'NotchContentState' has no member 'airpodsIsland'`.

- [ ] **Step 3: Implementar**

`Knobler/NotchPresentation.swift`:

```swift
enum NotchMode: Equatable {
    case closed, music, notification, hud, dictation, question, pomodoro, airpods, airpodsIsland, message, update
}
```

Em `NotchContentState`, depois de `var airpods = false`:

```swift
    /// Ilha compacta de conexão dos AirPods; o card (`airpods`) vence ela.
    var airpodsIsland = false
```

Em `mode`, logo depois de `if airpods { return .airpods }`:

```swift
        if airpodsIsland { return .airpodsIsland }
```

`compact`:

```swift
    var compact: Bool { [.closed, .hud, .dictation, .pomodoro, .airpodsIsland].contains(mode) }
```

No `switch mode` do tamanho:

```swift
        case .hud, .dictation, .pomodoro, .airpodsIsland:
```

e

```swift
        case .airpods: target = CGSize(width: Self.airpodsCardWidth, height: topInset + Self.airpodsCardHeight)
```

Dentro de `struct NotchPresentation`, perto de `hostFrame`:

```swift
    /// Largura/altura do card de AirPods, lidas também pela NotchView. A largura
    /// cobre a ilha (notch + 170) pra o card não encolher sob o cursor no hover.
    static let airpodsCardWidth: CGFloat = 380
    static let airpodsCardHeight: CGFloat = 112
```

- [ ] **Step 4: Rodar e ver passar**

Run: o comando do Step 2.
Expected: sai com código 0, sem `Assertion failed`.

- [ ] **Step 5: Commit**

```bash
git add Knobler/NotchPresentation.swift tools/presentationcheck.swift
git commit -m "feat(airpods): estado de apresentação da ilha compacta"
```

---

### Task 3: Ilha vs. card, hold no hover e motivo do anúncio

**Files:**
- Modify: `Knobler/BluetoothMonitor.swift:17,98-112`
- Modify: `Knobler/NotchViewModel.swift:215-219,444,669-680`
- Modify: `Knobler/KnoblerApp.swift:293-309`
- Modify: `Knobler/NotchView.swift:234-243` (só o `.onHover`)

**Interfaces:**
- Consumes: `AirPodsAnnounce` (Task 1), `NotchContentState.airpodsIsland` (Task 2).
- Produces:
  - `BluetoothMonitor.onAnnounce: ((AirPodsBattery, AirPodsAnnounce) -> Void)?`
  - `NotchViewModel.airpodsIsland: Bool` (`@Published`)
  - `NotchViewModel.showAirPods(_ reason: AirPodsAnnounce)`
  - `NotchViewModel.holdAirPods(_ hovering: Bool)`
  - `NotchViewModel.dismissAirPods()`
  - `showAirPodsCard(duration:)` é removido.

Sem harness hermético para o view model (depende de SwiftUI/AppKit). A verificação é o build + o cenário de snapshot da Task 4 + o teste ao vivo do Step 6.

- [ ] **Step 1: Monitor com motivo, um anúncio só**

`Knobler/BluetoothMonitor.swift:17`:

```swift
    var onAnnounce: ((AirPodsBattery, AirPodsAnnounce) -> Void)?
```

Substituir o bloco de `if !wasPresent, announce {` até o fim do `if let min` por:

```swift
            // bateria baixa, uma vez por ciclo (rearma ao recarregar)
            var low = false
            if let min = battery.minLevel {
                if min <= self.lowThreshold, !self.warnedLow {
                    self.warnedLow = true
                    low = true
                } else if min > self.recoverThreshold {
                    self.warnedLow = false
                }
            }
            // conectar já descarregado vira um anúncio só: o de bateria baixa
            if low {
                self.onAnnounce?(battery, .lowBattery)
            } else if !wasPresent, announce {
                self.onAnnounce?(battery, .connected)
            }
```

- [ ] **Step 2: View model**

`Knobler/NotchViewModel.swift`, trocar o comentário de `airpods` e o de `airpodsCard`, e acrescentar a ilha:

```swift
    /// AirPods conectados: bateria por componente (nil = desconectado).
    @Published var airpods: AirPodsBattery?
    /// Card grande de AirPods (hover na ilha ou bateria baixa), auto-some.
    @Published var airpodsCard = false
    /// Ilha compacta de conexão dos AirPods, auto-some.
    @Published var airpodsIsland = false
```

Em `contentState`, trocar `airpods: airpodsCard,` por `airpods: airpodsCard, airpodsIsland: airpodsIsland,`.

Substituir `showAirPodsCard` (e manter `airpodsWork`) por:

```swift
    /// Conexão abre a ilha (~3 s); bateria baixa abre o card direto (~5 s).
    func showAirPods(_ reason: AirPodsAnnounce) {
        airpodsIsland = reason == .connected
        airpodsCard = reason == .lowBattery
        scheduleAirPodsDismiss(after: reason == .connected ? 3.0 : 5.0)
    }

    /// Cursor sobre a ilha promove para o card e segura o timer; ao sair,
    /// reagenda curto. Não passa pelo `setHover`: senão o card de música
    /// acordaria por baixo e assumiria quando os AirPods somem.
    func holdAirPods(_ hovering: Bool) {
        guard airpodsIsland || airpodsCard else { return }
        if hovering {
            airpodsWork?.cancel()
            airpodsIsland = false
            airpodsCard = true
        } else {
            scheduleAirPodsDismiss(after: 1.0)
        }
    }

    func dismissAirPods() {
        airpodsWork?.cancel()
        airpodsIsland = false
        airpodsCard = false
    }

    private func scheduleAirPodsDismiss(after duration: TimeInterval) {
        airpodsWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.dismissAirPods() }
        airpodsWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: work)
    }
```

- [ ] **Step 3: Fiação no AppDelegate**

`Knobler/KnoblerApp.swift`, trocar o bloco dos AirPods:

```swift
        // AirPods: ilha na conexão, card na bateria baixa.
        // start()/stop() ficam no sink de settings (reage ao toggle).
        bluetooth.onAnnounce = { [weak self] ap, reason in
            self?.notches.values.forEach {
                $0.viewModel.airpods = ap
                $0.viewModel.showAirPods(reason)
            }
        }
        bluetooth.onUpdate = { [weak self] ap in
            self?.notches.values.forEach { $0.viewModel.airpods = ap }
        }
        bluetooth.onDisconnect = { [weak self] in
            self?.notches.values.forEach {
                $0.viewModel.airpods = nil
                $0.viewModel.dismissAirPods()
            }
        }
```

- [ ] **Step 4: Hover**

`Knobler/NotchView.swift`, no `.onHover`, depois do ramo `mode == .message`:

```swift
            } else if mode == .airpods || mode == .airpodsIsland {
                vm.holdAirPods(inside)
```

- [ ] **Step 5: Compilar**

Run: `xcodebuild -project Knobler.xcodeproj -scheme Knobler -configuration Debug build CODE_SIGNING_ALLOWED=NO 2>&1 | grep -E "error:|BUILD" | head`
Expected: erro só em `NotchView.swift` por `switch must be exhaustive` (falta `.airpodsIsland`) — resolvido na Task 4. Se houver qualquer outro erro, corrija antes de seguir. Não commitar ainda: Task 3 e 4 entram juntas.

---

### Task 4: Views da ilha e do card, anel, snapshots

**Files:**
- Create: `Knobler/AirPodsViews.swift`
- Modify: `Knobler/NotchView.swift:194-200` (switch), `:1415-1455` (remover card antigo), `:1532-1555` (`ActivityRingView`)
- Modify: `tools/notchview-fontes.txt`
- Modify: `tools/main.swift:629-651` (cenários)

**Interfaces:**
- Consumes: `AirPodsBattery.model/islandLevel/isLow`, `AirPodsModel.*Symbol` (Task 1); `NotchPresentation.airpodsCardWidth/Height` (Task 2); `vm.airpods` (Task 3).
- Produces:
  - `struct AirPodsIslandView: View { let battery: AirPodsBattery }`
  - `struct AirPodsCardView: View { let battery: AirPodsBattery }`
  - `struct BatteryRingView: View { let level: Int?; var delay: Double = 0; var lineWidth: CGFloat = 3 }`
  - `BatteryRingView.animaEntrada: Bool` (estático; o harness zera)
  - `ActivityRingView(progress:color:lineWidth:)` — `color` default `.orange`, `lineWidth` default `2.5`; os três usos atuais não mudam.

- [ ] **Step 1: Parametrizar o anel existente**

`Knobler/NotchView.swift`, `ActivityRingView`:

```swift
struct ActivityRingView: View {
    var progress: Double?
    var color: Color = .orange
    var lineWidth: CGFloat = 2.5
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if let progress {
            ZStack {
                Circle().stroke(.white.opacity(0.25), lineWidth: lineWidth)
                Circle()
                    .trim(from: 0, to: max(0.03, progress))
                    .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            .animation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.9), value: progress)
        } else {
            TimelineView(.animation(minimumInterval: 1.0 / 30)) { context in
                let phase = context.date.timeIntervalSinceReferenceDate
                    .truncatingRemainder(dividingBy: 1.2) / 1.2
                Circle()
                    .trim(from: 0, to: 0.7)
                    .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(phase * 360))
            }
        }
    }
}
```

- [ ] **Step 2: Criar `Knobler/AirPodsViews.swift`**

```swift
//
//  AirPodsViews.swift
//  Knobler
//
//  Ilha compacta (conexão) e card grande (hover / bateria baixa) dos AirPods,
//  no ritmo do iPhone: fone quica, anéis de bateria enchem.
//

import SwiftUI

/// Anel de bateria: verde normal, vermelho ≤ 10 %, trilho vazio sem leitura.
/// Enche de 0 até o nível ao aparecer, depois de `delay` (cascata do card).
struct BatteryRingView: View {
    let level: Int?
    var delay: Double = 0
    var lineWidth: CGFloat = 3
    /// ponytail: chave global pro harness de snapshot desenhar o nível final
    /// (o ImageRenderer não roda o onAppear animado). Trocar por injeção se
    /// outra view precisar do mesmo.
    static var animaEntrada = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var cheio = !BatteryRingView.animaEntrada

    var body: some View {
        Group {
            if let level {
                ActivityRingView(progress: cheio || reduceMotion ? Double(level) / 100 : 0,
                                 color: AirPodsBattery.isLow(level) ? .red : .green,
                                 lineWidth: lineWidth)
            } else {
                Circle().stroke(.white.opacity(0.25), lineWidth: lineWidth)
            }
        }
        .onAppear {
            guard !cheio else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { cheio = true }
        }
    }
}

/// Ilha de conexão: fone do modelo à esquerda, anel + número à direita.
struct AirPodsIslandView: View {
    let battery: AirPodsBattery
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulos = 0

    var body: some View {
        HStack(spacing: 0) {
            Image(systemName: battery.model.pairSymbol)
                .font(.subheadline)
                .foregroundStyle(.white)
                .symbolEffect(.bounce, value: pulos)
                .padding(.leading, 16)
            Spacer(minLength: 0)
            HStack(spacing: 6) {
                if let level = battery.islandLevel {
                    Text("\(level)%")
                        .font(.caption.monospacedDigit().weight(.semibold))
                        .foregroundStyle(AirPodsBattery.isLow(level) ? .red : .white)
                }
                BatteryRingView(level: battery.islandLevel, lineWidth: 2.5)
                    .frame(width: 16, height: 16)
            }
            .padding(.trailing, 16)
        }
        .onAppear { if !reduceMotion { pulos += 1 } }
    }
}

/// Card grande: nome no topo, uma coluna por peça com ícone e anel.
struct AirPodsCardView: View {
    let battery: AirPodsBattery
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulos = 0

    var body: some View {
        VStack(spacing: 10) {
            Text(battery.name)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
            HStack(spacing: 32) {
                coluna(battery.model.leftSymbol, battery.left, "Esquerdo", delay: 0)
                coluna(battery.model.rightSymbol, battery.right, "Direito", delay: 0.12)
                if let estojo = battery.model.caseSymbol {
                    coluna(estojo, battery.case_, "Estojo", delay: 0.24)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .onAppear { if !reduceMotion { pulos += 1 } }
    }

    private func coluna(_ simbolo: String, _ level: Int?, _ rotulo: String,
                        delay: Double) -> some View {
        VStack(spacing: 6) {
            Image(systemName: simbolo)
                .font(.title2)
                .foregroundStyle(.white)
                .frame(height: 26)
                .symbolEffect(.bounce, value: pulos)
            ZStack {
                BatteryRingView(level: level, delay: delay)
                Text(level.map { "\($0)" } ?? "—")
                    .font(.caption2.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.white)
            }
            .frame(width: 34, height: 34)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(rotulo): \(level.map { "\($0)%" } ?? "sem leitura")")
    }
}
```

- [ ] **Step 3: Ligar na `NotchView`**

Substituir o `case .airpods:` do switch (`NotchView.swift:194-200`) por:

```swift
            case .airpodsIsland:
                if let ap = vm.airpods {
                    AirPodsIslandView(battery: ap)
                        .transition(reduceMotion ? .opacity : AnyTransition(.blurReplace))
                }
            case .airpods:
                if let ap = vm.airpods {
                    AirPodsCardView(battery: ap)
                        .frame(width: NotchPresentation.airpodsCardWidth - 40)
                        .padding(.top, topInset + 6)
                        .padding(.bottom, 12)
                        // desce do notch, como as notificações
                        .transition(reduceMotion ? .opacity : AnyTransition(.blurReplace).combined(with: .move(edge: .top)))
                }
```

Apagar `// MARK: - AirPods`, `airpodsConnectCard` e `airpodsPip` (`NotchView.swift:1415-1455`).

Acrescentar `Knobler/AirPodsViews.swift` em `tools/notchview-fontes.txt`, logo depois de `Knobler/AirPodsBattery.swift`.

- [ ] **Step 4: Gerar projeto e compilar**

Run: `xcodegen generate && xcodebuild -project Knobler.xcodeproj -scheme Knobler -configuration Debug build CODE_SIGNING_ALLOWED=NO 2>&1 | grep -E "error:|BUILD" | head`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 5: Cenários de snapshot**

Em `tools/main.swift`, no reset por cenário (perto de `QuickNote.shared.active = false`, linha ~705), acrescentar:

```swift
    // anéis desenhados já no nível final: o ImageRenderer não roda a entrada
    BatteryRingView.animaEntrada = false
```

Substituir os cinco cenários `airpods-*` (`:629-651`) por:

```swift
    // AirPods: ilha de conexão, card (hover), bateria baixa, modelo
    // desconhecido e fone sem leitura de um lado.
    Scenario(name: "airpods-island", realNotch: true) { vm, _, _ in
        vm.airpods = AirPodsBattery(name: "AirPods Pro", left: 90, right: 82, case_: 31, model: .pro)
        vm.airpodsIsland = true
    },
    Scenario(name: "airpods-island-external", realNotch: false) { vm, _, _ in
        vm.airpods = AirPodsBattery(name: "AirPods Pro", left: 90, right: 82, case_: 31, model: .pro)
        vm.airpodsIsland = true
    },
    Scenario(name: "airpods-connect", realNotch: true) { vm, _, _ in
        vm.airpods = AirPodsBattery(name: "AirPods Pro", left: 90, right: 89, case_: 31, model: .pro)
        vm.airpodsCard = true
    },
    Scenario(name: "airpods-connect-external", realNotch: false) { vm, _, _ in
        vm.airpods = AirPodsBattery(name: "AirPods Pro", left: 90, right: 89, case_: 31, model: .pro)
        vm.airpodsCard = true
    },
    Scenario(name: "airpods-low", realNotch: false) { vm, _, _ in
        vm.airpods = AirPodsBattery(name: "AirPods Pro", left: 8, right: 74, case_: nil, model: .pro)
        vm.airpodsCard = true
    },
    Scenario(name: "airpods-gen3", realNotch: true) { vm, _, _ in
        vm.airpods = AirPodsBattery(name: "AirPods", left: 64, right: nil, case_: 100, model: .gen3)
        vm.airpodsCard = true
    },
    Scenario(name: "airpods-unknown", realNotch: true) { vm, _, _ in
        vm.airpods = AirPodsBattery(name: "Fone Bluetooth", left: 50, right: 50, case_: nil)
        vm.airpodsCard = true
    },
```

Apagar os PNGs mortos: `git rm Snapshots/airpods-strip-music.png Snapshots/airpods-card-nomusic.png`.

- [ ] **Step 6: Renderizar e olhar**

Run: `./tools/snapshot.sh`
Abrir e conferir `Snapshots/airpods-island.png`, `airpods-connect.png`, `airpods-low.png`, `airpods-gen3.png`, `airpods-unknown.png`:
- ilha: ícone à esquerda, `82%` e anel verde à direita, sem corte pela borda do notch;
- card: nome, três colunas centradas, anéis verdes cheios no nível, número dentro;
- low: anel esquerdo vermelho com `8`, coluna do estojo com anel vazio e `—`;
- gen3: lado direito com anel vazio e `—`;
- nenhum conteúdo cortado embaixo. Se cortar ou sobrar espaço, ajustar só `NotchPresentation.airpodsCardHeight` e renderizar de novo.

- [ ] **Step 7: Teste ao vivo**

Com o app compilado rodando (`open` do produto do Step 4) e os AirPods à mão:
1. Guardar os fones no estojo e tirar de novo: a ilha aparece, o fone quica, o anel enche; some em ~3 s e o notch fecha.
2. Repetir e passar o mouse na ilha: vira o card, anéis enchem em cascata; enquanto o mouse fica, o card não some; ao tirar, some em ~1 s e **não** abre o card de música.
3. Durante a ilha, apertar uma tecla de volume: o volume aparece no lugar.
4. Ajustes do Sistema → Acessibilidade → Tela → Reduzir movimento ligado: repetir 1 — nada quica nem enche.
5. `curl -s 127.0.0.1:4477/status | jq .mode` durante a ilha: `"airpodsIsland"`.

- [ ] **Step 8: Gates e commit**

Run: `./tools/check.sh`
Expected: todos os gates verdes.

```bash
git add Knobler/AirPodsViews.swift Knobler/NotchView.swift Knobler/NotchViewModel.swift \
  Knobler/BluetoothMonitor.swift Knobler/KnoblerApp.swift tools/notchview-fontes.txt \
  tools/main.swift Snapshots/airpods-*.png
git commit -m "feat(airpods): ilha e card animados no ritmo do iPhone"
```

`Knobler.xcodeproj` é artefato: não adicionar se não estiver versionado (`git ls-files Knobler.xcodeproj | head -1` vazio = não versionado).

---

### Task 5: Documentação e novidades

**Files:**
- Modify: `docs/airpods.md`
- Modify: `docs/images/airpods-connect.png`, `docs/images/airpods-low.png`; Create: `docs/images/airpods-island.png`
- Modify: `CHANGELOG.md` (`## [Unreleased]`)
- Modify/Create: `Knobler/Novidades/0.30.0.html`
- Modify: `Knobler/NovidadesCatalogo.swift:20` (se `0.30.0` ainda não estiver na lista)

- [ ] **Step 1: Imagens**

```bash
cp Snapshots/airpods-island.png docs/images/airpods-island.png
cp Snapshots/airpods-connect.png docs/images/airpods-connect.png
cp Snapshots/airpods-low.png docs/images/airpods-low.png
```

- [ ] **Step 2: `docs/airpods.md`**

Trocar o topo (imagens e "O que faz") por:

```markdown
# AirPods no notch

![Ilha de conexão](images/airpods-island.png)

*Conectou — o notch alarga, o fone quica e o anel mostra a bateria.*

![Card com bateria por peça](images/airpods-connect.png)

*Passe o mouse na ilha — esquerdo, direito e estojo, cada um com seu anel.*

![Aviso de bateria baixa](images/airpods-low.png)

*Bateria baixa — o card abre sozinho, com a peça fraca em vermelho.*

## O que faz

Ao conectar os AirPods, o notch alarga por uns 3 segundos como a ilha do
iPhone: o ícone do seu modelo entra quicando e um anel verde enche até o
nível do fone mais descarregado. Passar o mouse na ilha abre o card com um
anel por peça (esquerdo, direito, estojo). Com 10% ou menos, o card abre
direto e o anel da peça fraca fica vermelho.

O modelo (Pro, 1ª/2ª/3ª geração, 4) sai do identificador que o macOS
informa; modelo desconhecido usa o ícone dos AirPods Pro. AirPods Max ainda
não aparecem.

Com **Reduzir movimento** ligado no macOS, nada quica nem enche: os anéis
aparecem no nível certo.

A conexão é detectada por notificação do IOBluetooth; a bateria vem do
`system_profiler SPBluetoothDataType`, lido no connect e a cada 60 s
enquanto os AirPods seguem conectados.
```

Manter `## Como usar` e `## Permissões` como estão.

- [ ] **Step 3: CHANGELOG**

Em `## [Unreleased]` → `### Added`, acrescentar:

```markdown
- AirPods no ritmo do iPhone: ilha animada na conexão, com o ícone do seu
  modelo e anel de bateria; passe o mouse para ver um anel por peça
  (esquerdo, direito, estojo). Bateria baixa abre o card direto.
```

- [ ] **Step 4: Novidades**

Se `Knobler/Novidades/0.30.0.html` não existir, criá-lo no formato de `0.29.0.html` (só `<section class="novidade">`, sem cabeçalho) e acrescentar `"0.30.0"` ao fim de `NovidadesCatalogo.versoes`. Se já existir (a peça Monitores também está no Unreleased), só acrescentar a seção:

```html
<section class="novidade">
  <h3>Seus AirPods, como no iPhone</h3>
  <p>Ao conectar, o notch alarga, o fone quica e um anel mostra a bateria.
     Passe o mouse para ver esquerdo, direito e estojo, cada um com seu anel.
     Com a bateria baixa, o aviso abre sozinho, em vermelho.</p>
</section>
```

- [ ] **Step 5: Gates e commit**

Run: `./tools/check.sh`
Expected: todos verdes (há gate de novidades/catálogo).

```bash
git add docs/airpods.md docs/images/airpods-*.png CHANGELOG.md Knobler/Novidades/0.30.0.html Knobler/NovidadesCatalogo.swift \
  docs/superpowers/specs/2026-09-22-airpods-animados-design.md docs/superpowers/specs/2026-07-19-airpods-notch-design.md \
  docs/superpowers/research/2026-09-22-airpods-animados-research.md docs/superpowers/plans/2026-09-22-airpods-animados.md
git commit -m "docs(airpods): ilha e card animados"
```
