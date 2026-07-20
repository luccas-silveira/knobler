# AirPods/Bluetooth no notch — design

Data: 2026-07-19 · Versão alvo: v0.17

## Objetivo

Trazer o momento icônico da Dynamic Island que ainda falta no Mac: conectou
AirPods → o notch mostra um card com o nome do dispositivo e o nível de bateria
de cada lado (esquerdo, direito, estojo). Enquanto conectado, a bateria fica
consultável no hover — convivendo com a música, que é o cenário real de uso.

Fiel ao `PRODUCT.md`: glanceável primeiro, nativo, some quando não precisa,
"a Apple poderia ter feito".

## Escopo (decidido)

- **Bateria:** L / R / case separados (card completo estilo iOS).
- **Gatilho/vida:** card transitório na conexão (~4s, some sozinho) + glance
  sob demanda no hover enquanto conectado.
- **Layout do glance:** faixinha discreta de AirPods embutida no card de música
  quando há música tocando; card dedicado no hover quando não há música.
- **Aviso de bateria baixa:** incluído (item 6a).
- **Toggle no AppSettings:** incluído, ligado por padrão (item 6b).

Fora de escopo: proximidade "abrir o estojo perto do Mac" (é recurso do iPhone,
depende de advertisement BLE proprietário no telefone pareado — não existe no
Mac); controle de ANC/transparência; múltiplos dispositivos simultâneos (mostra
o AirPods conectado; se houver mais de um, o mais recente).

## Arquitetura

Segue o molde dos monitores existentes (`BatteryMonitor.swift`,
`CalendarCountdown.swift`): classe pequena com callbacks, instanciada e fiada no
AppDelegate.

### Arquivos novos

- **`BluetoothMonitor.swift`** — duas responsabilidades:
  - *Conexão* (`IOBluetooth`, API nativa limpa): registra notificação de
    connect/disconnect, filtra AirPods por classe de dispositivo/nome. Dispara
    `onConnect(name)` / `onDisconnect()`.
  - *Bateria* (`system_profiler`): lê as porcentagens por componente. Uma
    leitura no connect + poll leve (~60s) enquanto conectado. Dispara
    `onBattery(AirPodsBattery)`.
- **`AirPodsView.swift`** — UI: o card dedicado (ícone + L/R/case grandes) e a
  faixa compacta (`🎧 L80 R75 ◎90`) pra embutir no card de música.

### Fonte de bateria — RESOLVIDO (pesquisa 2026-07-19)

Testado na máquina real com AirPods Pro conectados:

- **`ioreg -r -l -k BatteryPercent` → vazio.** As chaves `BatteryPercent*` não
  existem no IORegistry desta máquina/versão de macOS. **Plano `ioreg`
  descartado.**
- **`system_profiler SPBluetoothDataType -json` → entrega tudo:**
  `device_batteryLevelLeft: "90%"`, `Right: "89%"`, `Case: "31%"`,
  `device_minorType: "Headphones"`. **E foi rápido: ~0.19s** (não 1-2s) —
  adequado pra poll em background.

**Estrutura do JSON (parser):**
```
SPBluetoothDataType[0].device_connected → [
  { "<nome do device>": {
      device_batteryLevelLeft:  "90%",
      device_batteryLevelRight: "89%",
      device_batteryLevelCase:  "31%",
      device_minorType: "Headphones" } },
  …
]
```
Cada item é um dict de chave única (nome do device). Filtrar por
`device_minorType == "Headphones"` + presença das chaves `device_batteryLevel*`.
Parse `"90%"` → strip `%` → `Int`. Rodar em background (não main thread).

### Detecção de conexão — RESOLVIDO (pesquisa 2026-07-19)

API de `IOBluetooth` verificada por compilação (`swiftc -typecheck`, exit 0, sem
erro de depreciação):
- `IOBluetoothDevice.register(forConnectNotifications:selector:)` — notificação
  global de conexão (event-driven, sem polling → mantém ~0% CPU parado).
- `device.register(forDisconnectNotification:selector:)` — por dispositivo.
- Propriedades: `.name`, `.isConnected()`, `.addressString`, `.deviceClassMinor`,
  `IOBluetoothDevice.pairedDevices()`.

Selector recebe `(IOBluetoothUserNotification, IOBluetoothDevice)`.

## Estado (NotchViewModel)

```swift
struct AirPodsBattery: Equatable {
    var name: String
    var left: Int?    // nil = lado não reportou
    var right: Int?
    var case_: Int?
}

@Published var airpods: AirPodsBattery?   // não-nil enquanto conectado
```

- Novo `Mode.airpods` para o card de conexão transitório, com auto-dismiss ~4s
  (mesmo mecanismo do HUD/notificação).
- **Prioridade:**
  `question > dictation > notification > hud > airpods(connect) > music > pomodoro > closed`.
  O card de conexão nunca atropela uma pergunta ou ditado em andamento.
- `airpods` permanece populado enquanto conectado (mesmo depois do card sumir),
  porque a faixa de música e o card de glance leem esse estado.

## Fluxo de dados

1. AirPods conectam → `BluetoothMonitor.onConnect` → lê bateria → seta `airpods`
   e mostra o card dedicado transitório (~4s) → some sozinho.
2. Enquanto conectado, `airpods` fica atualizado (poll ~60s).
3. Glance no hover:
   - Com música → faixa `🎧 L80 R75 ◎90` no rodapé do card de música.
   - Sem música → hover mostra o card dedicado de AirPods.
4. Bateria baixa (algum lado ≤10%) → card transitório uma vez por ciclo
   (padrão `warnedLow` do `BatteryMonitor`; reseta ao recarregar/reconectar).
5. Desconectou → `airpods = nil` → faixa/card somem.

## Erros e bordas

- Sem AirPods pareados / máquina sem Bluetooth → `airpods` nil, zero UI
  (igual ao `BatteryMonitor` em desktop sem bateria).
- Lado sem reportar bateria → mostra só os componentes com valor (`Int?`).
- `ioreg`/`system_profiler` falhou → mantém último valor conhecido; o card de
  conexão ainda funciona (só precisa do nome).
- AirPods Max (sem estojo) / modelos que não reportam `case` → oculta o
  componente ausente.
- Toggle desligado no AppSettings → monitor não inicia, nenhuma UI.
- **Permissão Bluetooth (TCC) — atenção na implementação:** `system_profiler`
  roda em processo separado (sem entitlement) e as APIs clássicas do
  `IOBluetooth` (nome/estado de pareados, notificação de conexão) normalmente
  não disparam o prompt TCC — que é do CoreBluetooth/BLE. Se ainda assim
  aparecer prompt, adicionar `NSBluetoothAlwaysUsageDescription` ao Info.plist
  via `project.yml`.

## Fiação e build

- `KnoblerApp.swift` (AppDelegate): instancia `BluetoothMonitor`, fia callbacks
  no `NotchViewModel` (mesmo padrão do `BatteryMonitor`); respeita o toggle.
- `NotchView.swift`: adiciona `case .airpods` (card dedicado) e a faixa no card
  de música.
- `AppSettings.swift`: novo toggle "Mostrar AirPods no notch" (default on).
- `tools/snapshot.sh`: adicionar `AirPodsView.swift` à lista manual pra validar
  os estados via PNG (loop de snapshot do projeto).

## Testes / validação

- Snapshot PNG dos novos estados: card de conexão, faixa junto da música, card
  dedicado (sem música), bateria baixa.
- Teste manual E2E: conectar/desconectar AirPods reais e conferir card +
  atualização de bateria + convivência com música tocando.
- `demo()`/self-check no parser de bateria (item não-trivial): dado um dump de
  `ioreg`/`system_profiler` de exemplo, asserta que L/R/case são extraídos e que
  componentes ausentes viram `nil`.
