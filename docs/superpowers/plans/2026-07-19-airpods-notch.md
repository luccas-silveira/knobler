# AirPods/Bluetooth no notch — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Quando os AirPods conectam, o notch mostra um card transitório com nome + bateria L/R/estojo; enquanto conectados, a bateria fica consultável no hover (faixa junto da música, card dedicado quando não há música).

**Architecture:** Um `BluetoothMonitor` no molde do `BatteryMonitor` — conexão detectada por notificação event-driven do `IOBluetooth` (zero polling parado), bateria lida via `system_profiler SPBluetoothDataType -json` (parser puro e testável) no connect + poll de 60s enquanto conectado. Estado novo no `NotchViewModel` (`airpods`, `airpodsCard`, `Mode.airpods`); render inline na `NotchView` (mesmo idioma dos outros cards). Toggle opt-out no `AppSettings`.

**Tech Stack:** Swift 5, AppKit + SwiftUI, IOBluetooth, Foundation `Process`/`JSONSerialization`. Sem dependência nova.

## Global Constraints

- Deployment target **macOS 14.2** (guardar API mais nova com `if #available`).
- Projeto gerado por **XcodeGen** (`project.yml` faz glob de `Knobler/`): após criar arquivo novo, rodar `xcodegen generate`. **Nunca editar `Knobler.xcodeproj` à mão.**
- Comentários e strings de UI em **pt-BR**.
- Marcar simplificações deliberadas com `// ponytail:`.
- Manter **~0% CPU parado**: nada de polling quando não há AirPods conectados.
- `system_profiler` em **`/usr/sbin/system_profiler`**; app **não é sandboxed** (Process pode spawná-lo).
- Fonte de bateria: `SPBluetoothDataType -json`, chaves `device_batteryLevelLeft/Right/Case`, filtro `device_minorType == "Headphones"` (verificado na máquina real 2026-07-19; `ioreg` **não** tem as chaves).
- Loop de snapshot: `tools/snapshot.sh` tem lista **manual** de arquivos — ao adicionar `.swift` que a `NotchView`/`NotchViewModel` usem, incluir lá.

---

### Task 1: Modelo `AirPodsBattery` + parser (com self-check)

Unidade pura (só Foundation), testável isolada com `swiftc`. É a única lógica não-trivial (parse de JSON com campos ausentes), então leva um self-check runnable.

**Files:**
- Create: `Knobler/AirPodsBattery.swift`
- Create: `tools/airpods_selfcheck.swift`
- Modify: `tools/snapshot.sh` (adicionar `AirPodsBattery.swift` à lista do `swiftc`)

**Interfaces:**
- Produces: `struct AirPodsBattery: Equatable { var name: String; var left: Int?; var right: Int?; var case_: Int? }` e `static func parse(from data: Data) -> AirPodsBattery?`.

- [ ] **Step 1: Escrever o self-check (falha)**

Create `tools/airpods_selfcheck.swift`:

```swift
//
//  tools/airpods_selfcheck.swift — self-check do parser de bateria dos AirPods.
//  Roda: swiftc Knobler/AirPodsBattery.swift tools/airpods_selfcheck.swift -o build/apcheck && ./build/apcheck
//

import Foundation

func json(_ s: String) -> Data { s.data(using: .utf8)! }

// caso feliz: AirPods com L/R/estojo
let full = json("""
{ "SPBluetoothDataType": [ { "device_connected": [
  { "Fone de Alguém": {
      "device_batteryLevelLeft": "90%",
      "device_batteryLevelRight": "89%",
      "device_batteryLevelCase": "31%",
      "device_minorType": "Headphones" } },
  { "Alto-falante": { "device_minorType": "Speaker" } }
] } ] }
""")
let a = AirPodsBattery.parse(from: full)
assert(a == AirPodsBattery(name: "Fone de Alguém", left: 90, right: 89, case_: 31), "full: \(String(describing: a))")

// componente ausente vira nil (AirPods Max: sem estojo)
let noCase = json("""
{ "SPBluetoothDataType": [ { "device_connected": [
  { "Max": { "device_batteryLevelLeft": "70%", "device_batteryLevelRight": "72%", "device_minorType": "Headphones" } }
] } ] }
""")
assert(AirPodsBattery.parse(from: noCase) == AirPodsBattery(name: "Max", left: 70, right: 72, case_: nil))

// só fones sem bateria e não-fones → nil (não é AirPods)
let noBattery = json("""
{ "SPBluetoothDataType": [ { "device_connected": [
  { "Teclado": { "device_minorType": "Keyboard" } },
  { "Fone burro": { "device_minorType": "Headphones" } }
] } ] }
""")
assert(AirPodsBattery.parse(from: noBattery) == nil)

// nada conectado → nil
assert(AirPodsBattery.parse(from: json("{ \"SPBluetoothDataType\": [ { \"device_connected\": [] } ] }")) == nil)

// JSON lixo → nil (não crasha)
assert(AirPodsBattery.parse(from: json("nao é json")) == nil)

// bateria como número puro (algumas versões) também parseia
let intPct = json("""
{ "SPBluetoothDataType": [ { "device_connected": [
  { "Fone": { "device_batteryLevelLeft": 55, "device_minorType": "Headphones" } }
] } ] }
""")
assert(AirPodsBattery.parse(from: intPct) == AirPodsBattery(name: "Fone", left: 55, right: nil, case_: nil))

print("airpods parser: OK")
```

- [ ] **Step 2: Rodar e verificar que falha**

Run: `cd /Users/luccassilveira/Desktop/knobler && mkdir -p build && swiftc Knobler/AirPodsBattery.swift tools/airpods_selfcheck.swift -o build/apcheck 2>&1 | head`
Expected: FAIL de compilação — `error: cannot find 'AirPodsBattery' in scope` (arquivo ainda não existe).

- [ ] **Step 3: Implementar `AirPodsBattery.swift`**

Create `Knobler/AirPodsBattery.swift`:

```swift
//
//  AirPodsBattery.swift
//  Knobler
//
//  Bateria por componente dos AirPods conectados, lida do JSON do
//  `system_profiler SPBluetoothDataType -json`. Modelo puro (Foundation) —
//  o parser é testável isolado (tools/airpods_selfcheck.swift).
//

import Foundation

struct AirPodsBattery: Equatable {
    var name: String
    var left: Int?
    var right: Int?
    /// `case` é palavra reservada em Swift.
    var case_: Int?

    /// Menor nível reportado (pra aviso de bateria baixa). nil se nada reportou.
    var minLevel: Int? { [left, right, case_].compactMap { $0 }.min() }

    /// Extrai os AirPods conectados do JSON do system_profiler. nil se não há
    /// fone reportando bateria (só teclado/mouse/alto-falante, ou nada).
    static func parse(from data: Data) -> AirPodsBattery? {
        guard
            let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
            let group = (root["SPBluetoothDataType"] as? [[String: Any]])?.first,
            let connected = group["device_connected"] as? [[String: Any]]
        else { return nil }

        for entry in connected {
            // cada item é um dict de chave única: nome do device → propriedades
            guard let (name, raw) = entry.first,
                  let props = raw as? [String: Any],
                  props["device_minorType"] as? String == "Headphones"
            else { continue }

            let left = pct(props["device_batteryLevelLeft"])
            let right = pct(props["device_batteryLevelRight"])
            let case_ = pct(props["device_batteryLevelCase"])
            // AirPods reportam ao menos um nível; fone burro (sem bateria) é ignorado
            guard left != nil || right != nil || case_ != nil else { continue }
            return AirPodsBattery(name: name, left: left, right: right, case_: case_)
        }
        return nil
    }

    /// "90%" → 90; número puro → ele mesmo; qualquer outra coisa → nil.
    private static func pct(_ value: Any?) -> Int? {
        if let i = value as? Int { return i }
        guard let s = value as? String else { return nil }
        let digits = s.filter(\.isNumber)
        return digits.isEmpty ? nil : Int(digits)
    }
}
```

- [ ] **Step 4: Rodar o self-check e verificar que passa**

Run: `cd /Users/luccassilveira/Desktop/knobler && swiftc Knobler/AirPodsBattery.swift tools/airpods_selfcheck.swift -o build/apcheck && ./build/apcheck`
Expected: `airpods parser: OK`

- [ ] **Step 5: Adicionar `AirPodsBattery.swift` ao harness de snapshot**

Modify `tools/snapshot.sh` — na lista do `swiftc`, adicionar a linha após `Knobler/NotchViewModel.swift \`:

```bash
  Knobler/NotchViewModel.swift \
  Knobler/AirPodsBattery.swift \
  Knobler/Pomodoro.swift \
```

- [ ] **Step 6: Commit**

```bash
cd /Users/luccassilveira/Desktop/knobler
git add Knobler/AirPodsBattery.swift tools/airpods_selfcheck.swift tools/snapshot.sh
git commit -m "feat(airpods): modelo AirPodsBattery + parser de system_profiler (com self-check)"
```

---

### Task 2: `BluetoothMonitor`

Detecção de conexão (IOBluetooth, event-driven) + leitura de bateria (system_profiler, off-main) + poll 60s enquanto conectado + aviso de bateria baixa. É glue de hardware — validado por compilação aqui; comportamento E2E na Task 5.

**Files:**
- Create: `Knobler/BluetoothMonitor.swift`

**Interfaces:**
- Consumes: `AirPodsBattery` + `AirPodsBattery.parse(from:)` (Task 1).
- Produces:
  - `final class BluetoothMonitor: NSObject`
  - `var onAnnounce: ((AirPodsBattery) -> Void)?` — connect novo OU bateria cruzou baixa → mostrar card transitório.
  - `var onUpdate: ((AirPodsBattery) -> Void)?` — refresh silencioso da bateria (atualiza a faixa).
  - `var onDisconnect: (() -> Void)?` — AirPods saíram → limpar estado.
  - `func start()` (idempotente) / `func stop()`.

- [ ] **Step 1: Implementar `BluetoothMonitor.swift`**

Create `Knobler/BluetoothMonitor.swift`:

```swift
//
//  BluetoothMonitor.swift
//  Knobler
//
//  AirPods no notch: conexão detectada por notificação event-driven do
//  IOBluetooth (sem polling parado); bateria lida do system_profiler no
//  connect + poll de 60s enquanto conectado. system_profiler é a fonte de
//  verdade tanto pra "há AirPods?" quanto pros níveis — o IOBluetooth só
//  dispara a checagem, evitando poll quando nada mudou.
//

import Foundation
import IOBluetooth

final class BluetoothMonitor: NSObject {
    /// Connect novo ou bateria cruzando o limite baixo → card transitório.
    var onAnnounce: ((AirPodsBattery) -> Void)?
    /// Refresh silencioso (mantém a faixa de bateria atual).
    var onUpdate: ((AirPodsBattery) -> Void)?
    /// AirPods desconectaram → limpar o estado no notch.
    var onDisconnect: (() -> Void)?

    private var connectNote: IOBluetoothUserNotification?
    private var disconnectNotes: [IOBluetoothUserNotification] = []
    private var pollTimer: Timer?
    private var present = false
    private var warnedLow = false

    private let lowThreshold = 10   // avisa ao cair pra ≤10%
    private let recoverThreshold = 20  // rearma o aviso ao voltar >20%

    func start() {
        guard connectNote == nil else { return }   // idempotente (sink chama sempre)
        connectNote = IOBluetoothDevice.register(
            forConnectNotifications: self,
            selector: #selector(bluetoothConnected(_:device:)))
        // AirPods já conectados ao subir: registra disconnect e popula sem card
        for d in (IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] ?? [])
        where d.isConnected() {
            registerDisconnect(d)
        }
        refresh(announce: false)
    }

    func stop() {
        connectNote?.unregister()
        connectNote = nil
        disconnectNotes.forEach { $0.unregister() }
        disconnectNotes.removeAll()
        pollTimer?.invalidate()
        pollTimer = nil
        if present { present = false; onDisconnect?() }
        warnedLow = false
    }

    @objc private func bluetoothConnected(_ note: IOBluetoothUserNotification,
                                          device: IOBluetoothDevice) {
        registerDisconnect(device)
        refresh(announce: true)
    }

    @objc private func bluetoothDisconnected(_ note: IOBluetoothUserNotification,
                                             device: IOBluetoothDevice) {
        refresh(announce: true)
    }

    private func registerDisconnect(_ device: IOBluetoothDevice) {
        if let n = device.register(forDisconnectNotification: self,
                                   selector: #selector(bluetoothDisconnected(_:device:))) {
            disconnectNotes.append(n)
        }
    }

    /// Lê a bateria e reconcilia o estado. `announce` = evento de usuário
    /// (connect/disconnect) que pode mostrar card; poll usa announce=false.
    private func refresh(announce: Bool) {
        readBattery { [weak self] battery in
            guard let self else { return }
            guard let battery else {
                if self.present {
                    self.present = false
                    self.warnedLow = false
                    self.stopPolling()
                    self.onDisconnect?()
                }
                return
            }

            let wasPresent = self.present
            self.present = true
            self.startPolling()
            self.onUpdate?(battery)   // sempre atualiza a faixa

            if !wasPresent, announce {
                self.onAnnounce?(battery)   // primeira conexão → card
            }

            // aviso de bateria baixa, uma vez por ciclo (rearma ao recarregar)
            if let min = battery.minLevel {
                if min <= self.lowThreshold, !self.warnedLow {
                    self.warnedLow = true
                    self.onAnnounce?(battery)
                } else if min > self.recoverThreshold {
                    self.warnedLow = false
                }
            }
        }
    }

    private func startPolling() {
        guard pollTimer == nil else { return }
        // ponytail: poll fixo de 60s só enquanto conectado; subir se a bateria
        // parecer defasada demais no card.
        pollTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) {
            [weak self] _ in self?.refresh(announce: false)
        }
    }

    private func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    /// Roda system_profiler fora da main e devolve o parse na main.
    private func readBattery(_ completion: @escaping (AirPodsBattery?) -> Void) {
        DispatchQueue.global(qos: .utility).async {
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
            task.arguments = ["SPBluetoothDataType", "-json"]
            let pipe = Pipe()
            task.standardOutput = pipe
            task.standardError = FileHandle.nullDevice
            var battery: AirPodsBattery?
            do {
                try task.run()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                task.waitUntilExit()
                battery = AirPodsBattery.parse(from: data)
            } catch {
                NSLog("knobler bluetooth: %@", error.localizedDescription)
            }
            DispatchQueue.main.async { completion(battery) }
        }
    }
}
```

- [ ] **Step 2: Verificar que compila (typecheck isolado)**

Run: `cd /Users/luccassilveira/Desktop/knobler && swiftc -typecheck Knobler/AirPodsBattery.swift Knobler/BluetoothMonitor.swift 2>&1 | head; echo "exit: ${PIPESTATUS[0]:-$?}"`
Expected: sem erros (só possíveis warnings de depreciação); exit 0.

- [ ] **Step 3: Commit**

```bash
cd /Users/luccassilveira/Desktop/knobler
git add Knobler/BluetoothMonitor.swift
git commit -m "feat(airpods): BluetoothMonitor (IOBluetooth connect + system_profiler + poll + aviso baixo)"
```

---

### Task 3: Estado no `NotchViewModel` + render na `NotchView` + snapshots

Deliverable visual: o notch mostra o card de conexão e a faixa de bateria. Validado por PNG (loop de snapshot do projeto).

**Files:**
- Modify: `Knobler/NotchViewModel.swift` (Mode, estado, `showAirPodsCard`)
- Modify: `Knobler/NotchView.swift` (case `.airpods`, faixa, placeholder, tamanhos)
- Modify: `tools/main.swift` (cenários de snapshot)

**Interfaces:**
- Consumes: `AirPodsBattery` (Task 1).
- Produces (NotchViewModel): `@Published var airpods: AirPodsBattery?`, `@Published var airpodsCard: Bool`, `Mode.airpods`, `func showAirPodsCard(duration:)`.

- [ ] **Step 1: Adicionar cenários de snapshot (o "teste" visual)**

Modify `tools/main.swift` — inserir estes cenários no array `scenarios`, logo após o bloco de `pomodoro-card-with-music` (antes do `]` que fecha o array, linha ~248):

```swift
    // AirPods: card de conexão (transitório), faixa junto da música,
    // card dedicado sem música, e aviso de bateria baixa.
    Scenario(name: "airpods-connect", realNotch: true) { vm, _ in
        vm.airpods = AirPodsBattery(name: "AirPods Pro", left: 90, right: 89, case_: 31)
        vm.airpodsCard = true
    },
    Scenario(name: "airpods-connect-external", realNotch: false) { vm, _ in
        vm.airpods = AirPodsBattery(name: "AirPods Pro", left: 90, right: 89, case_: 31)
        vm.airpodsCard = true
    },
    Scenario(name: "airpods-strip-music", realNotch: true) { vm, media in
        media.injectPreview(state: fakeState(), artwork: fakeArtwork())
        vm.airpods = AirPodsBattery(name: "AirPods Pro", left: 90, right: 89, case_: 31)
        vm.expanded = true
    },
    Scenario(name: "airpods-card-nomusic", realNotch: true) { vm, _ in
        vm.airpods = AirPodsBattery(name: "AirPods Pro", left: 90, right: 89, case_: 31)
        vm.expanded = true
    },
    Scenario(name: "airpods-low", realNotch: false) { vm, _ in
        vm.airpods = AirPodsBattery(name: "AirPods Pro", left: 8, right: 74, case_: nil)
        vm.airpodsCard = true
    },
```

- [ ] **Step 2: Rodar snapshot e verificar que falha**

Run: `cd /Users/luccassilveira/Desktop/knobler && ./tools/snapshot.sh 2>&1 | head`
Expected: FAIL de compilação — `value of type 'NotchViewModel' has no member 'airpods'` / `airpodsCard`.

- [ ] **Step 3: Estado no `NotchViewModel.swift`**

Modify `Knobler/NotchViewModel.swift`:

(a) Adicionar as propriedades publicadas após `@Published var pomodoro: PomodoroState?` (linha ~46):

```swift
    /// AirPods conectados: bateria por componente (nil = desconectado). Alimenta
    /// a faixa junto da música e o card dedicado no hover.
    @Published var airpods: AirPodsBattery?
    /// Card transitório de AirPods (connect / bateria baixa), auto-some.
    @Published var airpodsCard = false
```

(b) Adicionar o case ao enum `Mode` (linha ~64):

```swift
    enum Mode: Equatable {
        case closed, music, notification, hud, dictation, question, pomodoro, airpods
    }
```

(c) Inserir a prioridade no computed `mode`, entre o HUD e a música (após `if hud != nil { return .hud }`, linha ~72):

```swift
        if hud != nil { return .hud }
        if airpodsCard { return .airpods }
        if expanded { return .music }
```

E atualizar o comentário da doc do `mode` (linha ~67):

```swift
    /// Prioridade: pergunta > ditado > notificação > HUD > AirPods(card) > música (hover) > pomodoro > fechado.
```

(d) Adicionar o auto-dismiss após o método `showHUD(...)` (após a linha ~207, fim da seção HUD):

```swift
    // MARK: - Card de AirPods (transitório)

    private var airpodsWork: DispatchWorkItem?

    /// Mostra o card de AirPods por `duration` e some (igual ao HUD).
    func showAirPodsCard(duration: TimeInterval = 4.0) {
        airpodsCard = true
        airpodsWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.airpodsCard = false }
        airpodsWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: work)
    }
```

- [ ] **Step 4: Render na `NotchView.swift`**

Modify `Knobler/NotchView.swift`:

(a) Adicionar o case ao switch de `notch` (após o bloco `case .question:`, linha ~95):

```swift
            case .airpods:
                airpodsConnectCard
                    .frame(width: 320 - 40)
                    .padding(.top, topInset)
                    .padding(.bottom, 12)
                    // desce do notch, como as notificações
                    .transition(.blurReplace.combined(with: .move(edge: .top)))
```

(b) Adicionar o tamanho no switch de `currentSize` (após o bloco `case .notification:`, linha ~183 — antes de `case .question:`):

```swift
        case .airpods:
            return CGSize(width: 320, height: topInset + 64)
```

(c) No `case .music:` do `currentSize` (linha ~167), incluir os AirPods no cálculo de altura e no placeholder. Substituir:

```swift
            let placeholder = !hasMusic && vm.activity == nil && !hasShelf
                && !vm.mirrorOn && !hasPomodoro
```

por:

```swift
            let placeholder = !hasMusic && vm.activity == nil && !hasShelf
                && !vm.mirrorOn && !hasPomodoro && vm.airpods == nil
```

E adicionar, logo antes de `return CGSize(width: expandedSize.width, height: height)` (linha ~181):

```swift
            // faixa (com música) ou card dedicado (sem música) dos AirPods
            if vm.airpods != nil { height += hasMusic ? 30 : 66 }
```

(d) No `expandedContent` (linha ~519), inserir a faixa de AirPods logo antes do bloco da música (`if !vm.mirrorOn, vm.pomodoro == nil { musicSection }`, linha ~540):

```swift
            if let ap = vm.airpods {
                airpodsRow(ap, compact: hasMusic)
                    .transition(.blurReplace)
            }
```

E adicionar `airpods` à lista de `.animation` no fim do `expandedContent` (após a linha ~547):

```swift
        .animation(.easeOut(duration: 0.3), value: vm.airpods)
```

(e) No `musicSection` (linha ~651), suprimir o placeholder "Nada tocando" quando há AirPods (senão ele briga com o card dedicado). Substituir:

```swift
        } else if vm.activity == nil, shelf.items.isEmpty, !vm.mirrorOn {
```

por:

```swift
        } else if vm.activity == nil, shelf.items.isEmpty, !vm.mirrorOn, vm.airpods == nil {
```

(f) Adicionar as views novas no fim do `struct NotchView` (antes do `static func timeString`, linha ~861):

```swift
    // MARK: - AirPods

    /// Card transitório mostrado quando os AirPods conectam ou ficam com bateria
    /// baixa: nome + bateria L / R / estojo.
    @ViewBuilder
    private var airpodsConnectCard: some View {
        if let ap = vm.airpods {
            HStack(spacing: 12) {
                Image(systemName: "airpodspro")
                    .font(.title2)
                    .foregroundStyle(.white)
                    .frame(width: 30)
                VStack(alignment: .leading, spacing: 4) {
                    Text(ap.name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    HStack(spacing: 14) {
                        airpodsPip("L", ap.left)
                        airpodsPip("R", ap.right)
                        airpodsPip("Estojo", ap.case_)
                    }
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// Faixa de AirPods no card expandido: compacta junto da música, ou uma
    /// linha maior (com nome) quando não há música tocando.
    private func airpodsRow(_ ap: AirPodsBattery, compact: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "airpodspro")
                .font(compact ? .subheadline : .title3)
                .foregroundStyle(.white.opacity(0.9))
            if !compact {
                Text(ap.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            airpodsPip("L", ap.left)
            airpodsPip("R", ap.right)
            airpodsPip("◎", ap.case_)
        }
        .frame(maxWidth: .infinity)
    }

    /// Um componente (rótulo + %); vermelho quando ≤10%, "—" quando não reportou.
    private func airpodsPip(_ label: String, _ level: Int?) -> some View {
        HStack(spacing: 3) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.55))
            Text(level.map { "\($0)%" } ?? "—")
                .font(.caption.monospacedDigit().weight(.semibold))
                .foregroundStyle((level ?? 100) <= 10 ? .red : .white)
        }
    }
```

- [ ] **Step 5: Rodar snapshot e ler os PNGs**

Run: `cd /Users/luccassilveira/Desktop/knobler && ./tools/snapshot.sh 2>&1 | tail`
Expected: PASS — imprime `ok Snapshots/airpods-connect.png`, `...strip-music`, `...card-nomusic`, `...low`, `...connect-external`.

Ler os PNGs gerados (`Snapshots/airpods-*.png`) e conferir: card de conexão com nome + L/R/estojo; faixa compacta convivendo com a música; card dedicado sem música; "8%" em vermelho no cenário `airpods-low`; nada cortado pela forma do notch.

- [ ] **Step 6: Commit**

```bash
cd /Users/luccassilveira/Desktop/knobler
git add Knobler/NotchViewModel.swift Knobler/NotchView.swift tools/main.swift Snapshots
git commit -m "feat(airpods): estado no NotchViewModel + card/faixa na NotchView + snapshots"
```

---

### Task 4: Toggle no `AppSettings` + fiação no `AppDelegate` + build

Integra a feature no app: toggle opt-out e fiação do monitor (start/stop reagindo ao toggle, como localAPI/screenshots).

**Files:**
- Modify: `Knobler/AppSettings.swift` (propriedade + init + UI)
- Modify: `Knobler/KnoblerApp.swift` (instância + callbacks + start/stop no sink)

**Interfaces:**
- Consumes: `BluetoothMonitor` (Task 2), `NotchViewModel.airpods/airpodsCard/showAirPodsCard` (Task 3), `AppSettings.shared.airpodsNotch`.

- [ ] **Step 1: Toggle no `AppSettings.swift`**

Modify `Knobler/AppSettings.swift`:

(a) Adicionar a propriedade após `micIndicator` (linha ~45):

```swift
    /// Card de AirPods no notch (connect + bateria L/R/estojo no hover).
    @Published var airpodsNotch: Bool {
        didSet { UserDefaults.standard.set(airpodsNotch, forKey: "airpodsNotch") }
    }
```

(b) No `init()`, após `micIndicator = flag("micIndicator")` (linha ~139):

```swift
        airpodsNotch = flag("airpodsNotch")
```

(c) Na Section "Notch" do `generalTab`, após o toggle "Indicador de microfone" (linha ~200):

```swift
                Toggle("AirPods no notch", isOn: $settings.airpodsNotch)
```

- [ ] **Step 2: Fiação no `KnoblerApp.swift`**

Modify `Knobler/KnoblerApp.swift`:

(a) Declarar a instância após `private let battery = BatteryMonitor()` (linha ~33):

```swift
    private let bluetooth = BluetoothMonitor()
```

(b) Adicionar os callbacks em `applicationDidFinishLaunching`, logo após o bloco `battery.start()` (após a linha ~125):

```swift
        // AirPods: card no connect + faixa de bateria enquanto conectado.
        // start()/stop() ficam no sink de settings (reage ao toggle).
        bluetooth.onAnnounce = { [weak self] battery in
            self?.notches.values.forEach {
                $0.viewModel.airpods = battery
                $0.viewModel.showAirPodsCard()
            }
        }
        bluetooth.onUpdate = { [weak self] battery in
            self?.notches.values.forEach { $0.viewModel.airpods = battery }
        }
        bluetooth.onDisconnect = { [weak self] in
            self?.notches.values.forEach {
                $0.viewModel.airpods = nil
                $0.viewModel.airpodsCard = false
            }
        }
```

(c) No sink `apiCancellable = AppSettings.shared.objectWillChange...`, dentro do `DispatchQueue.main.async` (junto de localAPI/screenshots, após o bloco de `screenshots`, linha ~304):

```swift
                    if AppSettings.shared.airpodsNotch {
                        self?.bluetooth.start()
                    } else {
                        self?.bluetooth.stop()
                    }
```

- [ ] **Step 3: Regenerar o projeto e compilar**

Run: `cd /Users/luccassilveira/Desktop/knobler && xcodegen generate && xcodebuild -project Knobler.xcodeproj -scheme Knobler -configuration Debug build 2>&1 | tail -20`
Expected: `** BUILD SUCCEEDED **` (o `xcodegen generate` inclui `AirPodsBattery.swift` e `BluetoothMonitor.swift` no alvo).

- [ ] **Step 4: Rodar o self-check do parser de novo (garantir que nada quebrou)**

Run: `cd /Users/luccassilveira/Desktop/knobler && swiftc Knobler/AirPodsBattery.swift tools/airpods_selfcheck.swift -o build/apcheck && ./build/apcheck`
Expected: `airpods parser: OK`

- [ ] **Step 5: Commit**

```bash
cd /Users/luccassilveira/Desktop/knobler
git add Knobler/AppSettings.swift Knobler/KnoblerApp.swift Knobler.xcodeproj
git commit -m "feat(airpods): toggle no AppSettings + fiação do BluetoothMonitor no AppDelegate"
```

---

### Task 5: Verificação E2E com AirPods reais

Exercita o fluxo no app rodando — o único jeito de validar hardware/permissão.

**Files:** nenhum (verificação).

- [ ] **Step 1: Instalar e rodar o app compilado**

Rodar o `.app` do build (matar instância anterior do Knobler primeiro). Confirmar que subiu sem prompt inesperado de permissão de Bluetooth; se aparecer prompt TCC, adicionar `NSBluetoothAlwaysUsageDescription` ao `info.properties` em `project.yml`, `xcodegen generate` e rebuildar.

- [ ] **Step 2: Testar connect**

Com o app rodando e o toggle "AirPods no notch" ligado, conectar os AirPods. Esperado: card transitório desce do notch com o nome e L/R/estojo, some sozinho em ~4s. Os valores batem com o Bluetooth do Ajustes do Sistema (tolerância de ~10% pelos degraus que o system_profiler reporta).

- [ ] **Step 3: Testar a faixa no hover**

Com música tocando (Spotify) e AirPods conectados, passar o mouse no notch → o card de música mostra a faixinha `🎧 L R ◎` no rodapé. Pausar/fechar a música e passar o mouse → aparece o card dedicado de AirPods (sem "Nada tocando").

- [ ] **Step 4: Testar disconnect + toggle**

Desconectar os AirPods → a faixa/card somem. Desligar o toggle nos Ajustes → nenhum card de AirPods aparece ao reconectar; religar → volta a funcionar (sem reiniciar o app).

- [ ] **Step 5: Conferir CPU parado**

Sem AirPods conectados, confirmar que o app segue em ~0% de CPU parado (nenhum poll rodando quando desconectado).

---

## Self-Review

**Spec coverage:**
- Bateria L/R/case → Task 1 (modelo/parser) + Task 3 (render). ✓
- Gatilho connect + glance no hover → Task 3 (`Mode.airpods` transitório + faixa/card em `expandedContent`). ✓
- Faixa junto da música / card sem música → Task 3 (`airpodsRow(compact:)` + guarda do placeholder). ✓
- Aviso de bateria baixa (6a) → Task 2 (`warnedLow`/`lowThreshold`) + cenário `airpods-low` na Task 3. ✓
- Toggle opt-out (6b) → Task 4. ✓
- system_profiler (não ioreg) + estrutura JSON → Task 1/2. ✓
- IOBluetooth event-driven, ~0% idle → Task 2 (sem poll quando desconectado) + Task 5 Step 5. ✓
- Bordas (componente ausente, JSON lixo, sem AirPods) → Task 1 self-check. ✓
- snapshot.sh lista manual → Task 1 Step 5. ✓
- xcodegen após arquivo novo → Task 4 Step 3. ✓
- Permissão TCC (item de atenção) → Task 5 Step 1. ✓

**Placeholder scan:** sem TBD/TODO; todo passo de código tem o código real.

**Type consistency:** `AirPodsBattery(name:left:right:case_:)`, `parse(from:)`, `minLevel`, `onAnnounce/onUpdate/onDisconnect`, `start()/stop()`, `airpods`, `airpodsCard`, `showAirPodsCard(duration:)`, `Mode.airpods` — usados de forma idêntica entre as tasks.
