# Dictation Hardening Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Corrigir os oito problemas encontrados na revisão do ditado sem mudar o gesto de uso, perder transcrições ou adicionar dependências.

**Architecture:** Manter `DictationController` como coordenador único, agora isolado à main actor, e preservar `MicRecorder`, Parakeet, Deepgram e `TranscriptFormatter` como componentes existentes. Capturar engine e destino no início de cada gravação, tornar a escrita no pasteboard conservadora e cancelar callbacks temporizados obsoletos. Checks puros entram no self-check headless já existente; o reducer Ask continua coberto por `tools/askcheck.swift`.

**Tech Stack:** Swift 5, AppKit, AVFoundation, ApplicationServices, FluidAudio 0.15.5, Swift Concurrency, scripts Swift existentes.

## Global Constraints

- Deployment target permanece macOS 14.2.
- Não adicionar dependências nem criar novo target de testes.
- Preservar o gesto atual: segurar ⌥ direita grava; soltar transcreve.
- Parakeet v3 continua sendo o engine local e Deepgram nova-3 o engine cloud.
- Falha do formatter continua devolvendo o transcript bruto.
- Nunca sobrescrever um clipboard alterado pelo usuário depois do ditado.
- Nunca colar em um aplicativo ou pergunta diferente do destino capturado no início da gravação.
- Cada task termina com build/check executável e commit próprio.

## Mapa de arquivos

- `Knobler/Dictation.swift`: gravação, seleção de engine, estado temporário, destino e inserção segura.
- `Knobler/KnoblerApp.swift`: wiring do destino Ask/aplicativo e entrada do self-check.
- `Knobler/AskFeature.swift`: ação de append vinculada ao ID da pergunta capturada.
- `tools/askcheck.swift`: regressão do append por ID.
- `docs/dictation.md`: comportamento quando a janela/pergunta muda antes da transcrição terminar.

---

### Task 1: Preservar o clipboard sem apagar conteúdo novo

**Files:**
- Modify: `Knobler/Dictation.swift:372-394`
- Modify: `Knobler/KnoblerApp.swift:20-25`

**Interfaces:**
- Consumes: `NSPasteboard`, `NSPasteboardItem`, `NSPasteboard.changeCount`.
- Produces: `DictationController.insert(_:expectedPID:pasteboard:restoreDelay:postPaste:) -> Bool` e `DictationController._clipboardSelfCheck() -> Bool`.

- [ ] **Step 1: Adicionar o check que demonstra perda de formatos e sobrescrita concorrente**

Em `Dictation.swift`, dentro de `DictationController`, adicionar:

```swift
static func _clipboardSelfCheck() -> Bool {
    let pasteboard = NSPasteboard(name: .init("knobler.dictation.selfcheck"))
    let customType = NSPasteboard.PasteboardType("com.zoi.knobler.selfcheck")
    let original = Data([0x01, 0x02, 0x03])

    pasteboard.clearContents()
    let item = NSPasteboardItem()
    item.setData(original, forType: customType)
    pasteboard.writeObjects([item])

    _ = insert(
        "temporário",
        expectedPID: nil,
        pasteboard: pasteboard,
        restoreDelay: 0,
        postPaste: {})
    RunLoop.main.run(until: Date().addingTimeInterval(0.02))
    guard pasteboard.data(forType: customType) == original else { return false }

    _ = insert(
        "temporário",
        expectedPID: nil,
        pasteboard: pasteboard,
        restoreDelay: 0.02,
        postPaste: {})
    pasteboard.clearContents()
    pasteboard.setString("copiado depois", forType: .string)
    RunLoop.main.run(until: Date().addingTimeInterval(0.04))
    return pasteboard.string(forType: .string) == "copiado depois"
}
```

Em `KnoblerMain.main()`, ampliar o `--selfcheck`:

```swift
let ok = MicRecorder.exceptionGuardWorks()
    && DictationController._clipboardSelfCheck()
print(ok ? "selfcheck: dictation OK" : "selfcheck: FALHOU")
exit(ok ? 0 : 1)
```

- [ ] **Step 2: Rodar o self-check e confirmar a regressão**

Run:

```bash
xcodebuild -project Knobler.xcodeproj -scheme Knobler -configuration Debug \
  -derivedDataPath /tmp/knobler-dictation-plan CODE_SIGNING_ALLOWED=NO build
/tmp/knobler-dictation-plan/Build/Products/Debug/Knobler.app/Contents/MacOS/Knobler --selfcheck
```

Expected: build falha com `extra arguments`/assinatura incompatível de `insert`;
o check já descreve o contrato que a implementação atual não oferece.

- [ ] **Step 3: Implementar snapshot profundo e restauração condicionada**

Substituir `insert(_:)` por:

```swift
@discardableResult
private static func insert(
    _ text: String,
    expectedPID: pid_t?,
    pasteboard: NSPasteboard = .general,
    restoreDelay: TimeInterval = 0.5,
    postPaste: () -> Void = postCommandV
) -> Bool {
    if let expectedPID,
       NSWorkspace.shared.frontmostApplication?.processIdentifier != expectedPID {
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        return false
    }

    let savedItems = pasteboard.pasteboardItems?.map { source in
        let copy = NSPasteboardItem()
        for type in source.types {
            if let data = source.data(forType: type) {
                copy.setData(data, forType: type)
            }
        }
        return copy
    } ?? []

    pasteboard.clearContents()
    pasteboard.setString(text, forType: .string)
    let temporaryChangeCount = pasteboard.changeCount
    postPaste()

    DispatchQueue.main.asyncAfter(deadline: .now() + restoreDelay) {
        guard pasteboard.changeCount == temporaryChangeCount else { return }
        pasteboard.clearContents()
        if !savedItems.isEmpty {
            pasteboard.writeObjects(savedItems)
        }
    }
    return true
}

private static func postCommandV() {
    let source = CGEventSource(stateID: .combinedSessionState)
    let down = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true)!
    let up = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false)!
    down.flags = .maskCommand
    up.flags = .maskCommand
    down.post(tap: .cghidEventTap)
    up.post(tap: .cghidEventTap)
}
```

Enquanto o destino ainda não foi implementado pela Task 6, atualizar o caller existente para `Self.insert(trimmed, expectedPID: nil)`.

- [ ] **Step 4: Rodar self-check e build**

Run:

```bash
xcodebuild -project Knobler.xcodeproj -scheme Knobler -configuration Debug \
  -derivedDataPath /tmp/knobler-dictation-plan CODE_SIGNING_ALLOWED=NO build
/tmp/knobler-dictation-plan/Build/Products/Debug/Knobler.app/Contents/MacOS/Knobler --selfcheck
```

Expected: `BUILD SUCCEEDED` e `selfcheck: dictation OK`.

- [ ] **Step 5: Commit**

```bash
git add Knobler/Dictation.swift Knobler/KnoblerApp.swift
git commit -m "fix(dictation): preserve clipboard changes and formats"
```

---

### Task 2: Garantir que soltar ⌥ sempre encerre uma gravação

**Files:**
- Modify: `Knobler/Dictation.swift:260-263`

**Interfaces:**
- Consumes: `recording`, `AppSettings.shared.dictation`.
- Produces: `rightOptionChanged(_:)` que aplica o toggle apenas ao início, nunca ao release de uma gravação ativa.

- [ ] **Step 1: Reproduzir manualmente o estado preso antes da correção**

Run:

```bash
open /tmp/knobler-dictation-plan/Build/Products/Debug/Knobler.app
```

Segurar ⌥ direita, desligar “Ditado” nos Ajustes usando o mouse e soltar ⌥.

Expected: antes da correção, `/status` mantém `"recording": true`:

```bash
curl -s http://localhost:4477/status | python3 -c \
  'import json,sys; print(json.load(sys.stdin)["dictation"]["recording"])'
```

- [ ] **Step 2: Separar as regras de press e release**

Substituir `rightOptionChanged(_:)` por:

```swift
func rightOptionChanged(_ pressed: Bool) {
    if pressed {
        guard AppSettings.shared.dictation else { return }
        begin()
    } else if recording {
        finish()
    }
}
```

Não chamar `finish()` quando não existe gravação; isso preserva releases normais da tecla e evita efeitos laterais.

- [ ] **Step 3: Verificar o caso corrigido**

Repetir o hold, desligar o toggle e soltar.

Expected:

```bash
curl -s http://localhost:4477/status | python3 -c \
  'import json,sys; assert json.load(sys.stdin)["dictation"]["recording"] is False'
```

- [ ] **Step 4: Rodar checks existentes**

Run:

```bash
/tmp/knobler-dictation-plan/Build/Products/Debug/Knobler.app/Contents/MacOS/Knobler --selfcheck
```

Expected: `selfcheck: dictation OK`.

- [ ] **Step 5: Commit**

```bash
git add Knobler/Dictation.swift
git commit -m "fix(dictation): always finish recording on option release"
```

---

### Task 3: Impedir timers antigos de esconder estados novos

**Files:**
- Modify: `Knobler/Dictation.swift:205-212, 275-369`

**Interfaces:**
- Consumes: `DispatchWorkItem`, `onState`.
- Produces: `setState(_:)`, `flash(_:duration:)` e `flashWorkItem`.

- [ ] **Step 1: Adicionar check de invalidação do flash**

Adicionar dentro de `DictationController`:

```swift
static func _flashSelfCheck() -> Bool {
    let controller = DictationController()
    var states: [DictationPhase?] = []
    controller.onState = { states.append($0) }
    controller.flash(.preparing, duration: 0.01)
    controller.setState(.recording(level: 0))
    RunLoop.main.run(until: Date().addingTimeInterval(0.03))
    return states.last! == .recording(level: 0)
}
```

Acrescentar `&& DictationController._flashSelfCheck()` ao `ok` do `--selfcheck`.

- [ ] **Step 2: Rodar o check e confirmar a falha**

Run:

```bash
xcodebuild -project Knobler.xcodeproj -scheme Knobler -configuration Debug \
  -derivedDataPath /tmp/knobler-dictation-plan CODE_SIGNING_ALLOWED=NO build
/tmp/knobler-dictation-plan/Build/Products/Debug/Knobler.app/Contents/MacOS/Knobler --selfcheck
```

Expected: falha de compilação porque `setState(_:)` e `flash(_:duration:)` ainda não existem.

- [ ] **Step 3: Centralizar publicação de estado e cancelar trabalho antigo**

Adicionar:

```swift
private var flashWorkItem: DispatchWorkItem?

private func setState(_ phase: DictationPhase?) {
    flashWorkItem?.cancel()
    flashWorkItem = nil
    onState?(phase)
}

private func flash(_ phase: DictationPhase, duration: TimeInterval = 2) {
    flashWorkItem?.cancel()
    onState?(phase)
    let work = DispatchWorkItem { [weak self] in
        guard let self else { return }
        self.flashWorkItem = nil
        self.onState?(nil)
    }
    flashWorkItem = work
    DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: work)
}
```

Trocar todas as publicações não temporárias em `DictationController`:

```swift
setState(.recording(level: level))
setState(.recording(level: 0))
setState(nil)
setState(.transcribing)
```

Manter erros e preparação usando `flash(...)`.

- [ ] **Step 4: Rodar self-check**

Run:

```bash
xcodebuild -project Knobler.xcodeproj -scheme Knobler -configuration Debug \
  -derivedDataPath /tmp/knobler-dictation-plan CODE_SIGNING_ALLOWED=NO build
/tmp/knobler-dictation-plan/Build/Products/Debug/Knobler.app/Contents/MacOS/Knobler --selfcheck
```

Expected: `selfcheck: dictation OK`.

- [ ] **Step 5: Commit**

```bash
git add Knobler/Dictation.swift Knobler/KnoblerApp.swift
git commit -m "fix(dictation): cancel stale state timers"
```

---

### Task 4: Não carregar Parakeet quando Deepgram está configurado

**Files:**
- Modify: `Knobler/Dictation.swift:213-237`

**Interfaces:**
- Consumes: `AppSettings.shared.dictationCloud`.
- Produces: `start()` que prepara Parakeet somente em modo local.

- [ ] **Step 1: Registrar a condição esperada antes de criar a política**

Adicionar ao corpo de `_enginePolicySelfCheck()`:

```swift
return Self.shouldPrepareLocalEngine(cloud: false)
    && !Self.shouldPrepareLocalEngine(cloud: true)
```

Acrescentar `&& DictationController._enginePolicySelfCheck()` ao self-check principal.

- [ ] **Step 2: Rodar e confirmar que o contrato ainda não existe**

Run:

```bash
xcodebuild -project Knobler.xcodeproj -scheme Knobler -configuration Debug \
  -derivedDataPath /tmp/knobler-dictation-plan CODE_SIGNING_ALLOWED=NO build
```

Expected: falha de compilação informando que `shouldPrepareLocalEngine` não existe.

- [ ] **Step 3: Implementar a política e aplicá-la no launch**

Adicionar:

```swift
static func shouldPrepareLocalEngine(cloud: Bool) -> Bool {
    !cloud
}

static func _enginePolicySelfCheck() -> Bool {
    shouldPrepareLocalEngine(cloud: false)
        && !shouldPrepareLocalEngine(cloud: true)
}
```

Trocar:

```swift
prepareLocalEngine()
```

por:

```swift
if Self.shouldPrepareLocalEngine(cloud: AppSettings.shared.dictationCloud) {
    prepareLocalEngine()
}
```

- [ ] **Step 4: Verificar local e cloud**

Com Deepgram selecionado, iniciar o app e consultar:

```bash
curl -s http://localhost:4477/status | python3 -c \
  'import json,sys; d=json.load(sys.stdin)["dictation"]; assert d["cloud"] is True and d["modelReady"] is False'
```

Depois selecionar Local, reiniciar e aguardar até `modelReady` virar `true`:

```bash
until curl -s http://localhost:4477/status | python3 -c \
  'import json,sys; raise SystemExit(not json.load(sys.stdin)["dictation"]["modelReady"])'
do sleep 1; done
```

Expected: cloud não prepara Parakeet; local prepara.

- [ ] **Step 5: Commit**

```bash
git add Knobler/Dictation.swift Knobler/KnoblerApp.swift
git commit -m "perf(dictation): skip local model in cloud mode"
```

---

### Task 5: Tratar Deepgram sem chave como configuração inválida

**Files:**
- Modify: `Knobler/Dictation.swift:16-88, 275-357`

**Interfaces:**
- Consumes: `DeepgramKeyStore.load()`.
- Produces: `TranscriptionSelection`, `transcriptionSelection(cloud:key:)` e engine capturado por gravação.

- [ ] **Step 1: Escrever assertions antes da política de seleção**

Substituir `_enginePolicySelfCheck()` pelo check abaixo, ainda sem criar
`TranscriptionSelection` nem `transcriptionSelection(cloud:key:)`:

```swift
guard shouldPrepareLocalEngine(cloud: false),
      !shouldPrepareLocalEngine(cloud: true),
      transcriptionSelection(cloud: false, key: "") == .local,
      transcriptionSelection(cloud: true, key: "  ") == .missingDeepgramKey,
      transcriptionSelection(cloud: true, key: "abc") == .deepgram(apiKey: "abc")
else { return false }
return true
```

- [ ] **Step 2: Rodar e confirmar que a seleção ainda não existe**

Run:

```bash
xcodebuild -project Knobler.xcodeproj -scheme Knobler -configuration Debug \
  -derivedDataPath /tmp/knobler-dictation-plan CODE_SIGNING_ALLOWED=NO build
```

Expected: falha de compilação informando que `transcriptionSelection` e os
cases de `TranscriptionSelection` não existem.

- [ ] **Step 3: Implementar a política mínima**

Adicionar perto dos engines:

```swift
enum TranscriptionSelection: Equatable {
    case local
    case deepgram(apiKey: String)
    case missingDeepgramKey
}
```

Adicionar ao controller:

```swift
static func transcriptionSelection(cloud: Bool, key: String) -> TranscriptionSelection {
    guard cloud else { return .local }
    let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? .missingDeepgramKey : .deepgram(apiKey: trimmed)
}
```

Run:

```bash
xcodebuild -project Knobler.xcodeproj -scheme Knobler -configuration Debug \
  -derivedDataPath /tmp/knobler-dictation-plan CODE_SIGNING_ALLOWED=NO build
/tmp/knobler-dictation-plan/Build/Products/Debug/Knobler.app/Contents/MacOS/Knobler --selfcheck
```

Expected: build e `_enginePolicySelfCheck()` passam.

- [ ] **Step 4: Capturar o engine válido no começo da gravação**

Adicionar:

```swift
private var recordingEngine: (any TranscriptionEngine)?
```

No início de `begin()`, depois dos guards de estado:

```swift
switch Self.transcriptionSelection(
    cloud: AppSettings.shared.dictationCloud,
    key: DeepgramKeyStore.load()
) {
case .missingDeepgramKey:
    flash(.error("Configure a chave do Deepgram"))
    return
case .local:
    guard modelReady else {
        prepareLocalEngine()
        flash(.preparing)
        return
    }
    recordingEngine = parakeet
case .deepgram(let apiKey):
    recordingEngine = DeepgramEngine(apiKey: apiKey)
}
```

Remover o guard antigo baseado apenas em `dictationCloud`.
No `catch` de `recorder.start()`, definir `recordingEngine = nil` antes de
mostrar o erro, para a tentativa falha não contaminar a próxima gravação.

Em `finish()`, antes da `Task`:

```swift
guard let engine = recordingEngine else {
    setState(nil)
    return
}
recordingEngine = nil
```

Usar:

```swift
var text = try await engine.transcribe(samples)
```

Em `cancel()`, definir `recordingEngine = nil`. Remover `activeEngine()`.

- [ ] **Step 5: Verificar chave ausente**

Selecionar Deepgram, apagar a chave, segurar e soltar ⌥ direita.

Expected: pílula mostra “Configure a chave do Deepgram”; `/status` permanece com `recording == false` e `transcribing == false`; nenhum download do Parakeet começa.

- [ ] **Step 6: Build e commit**

```bash
xcodebuild -project Knobler.xcodeproj -scheme Knobler -configuration Debug \
  -derivedDataPath /tmp/knobler-dictation-plan CODE_SIGNING_ALLOWED=NO build
/tmp/knobler-dictation-plan/Build/Products/Debug/Knobler.app/Contents/MacOS/Knobler --selfcheck
git add Knobler/Dictation.swift Knobler/KnoblerApp.swift
git commit -m "fix(dictation): reject cloud mode without API key"
```

Expected: build e self-check passam.

---

### Task 6: Fixar o destino no começo da gravação

**Files:**
- Modify: `Knobler/Dictation.swift:195-394`
- Modify: `Knobler/KnoblerApp.swift:113-128`
- Modify: `Knobler/AskFeature.swift:21-31, 113-117`
- Modify: `tools/askcheck.swift:140-155`
- Modify: `docs/dictation.md`

**Interfaces:**
- Consumes: `AskStore.state.active?.id`, `NSWorkspace.shared.frontmostApplication`.
- Produces: `DictationDestination`, `destinationProvider`, `transcriptSink(_:destination:)` e `AskAction.appendText(id:text:)`.

- [ ] **Step 1: Fazer o reducer rejeitar texto destinado a outra pergunta**

Trocar a action:

```swift
case appendText(id: String, text: String)
```

E o reducer:

```swift
case .appendText(let id, let appended):
    guard state.active?.id == id, !appended.isEmpty else { return [] }
    state.text = state.text.isEmpty ? appended : state.text + " " + appended
    return []
```

Atualizar `tools/askcheck.swift` para:

```swift
send(.appendText(id: "req-1", text: "primeiro"), to: &state)
send(.appendText(id: "req-1", text: "segundo"), to: &state)
assert(state.text == "primeiro segundo")
send(.appendText(id: "outra", text: "não entra"), to: &state)
assert(state.text == "primeiro segundo")
send(.appendText(id: "req-1", text: "fora"), to: &emptyState)
assert(emptyState.text.isEmpty)
```

- [ ] **Step 2: Rodar o reducer check**

Run:

```bash
swiftc Knobler/AskModels.swift Knobler/AskFeature.swift tools/askcheck.swift \
  -o /tmp/knobler-askcheck && /tmp/knobler-askcheck
```

Expected: antes de atualizar o reducer, falha de compilação pela nova assinatura; depois, `askcheck: OK`.

- [ ] **Step 3: Modelar e capturar o destino**

Adicionar em `Dictation.swift`:

```swift
enum DictationDestination: Equatable {
    case ask(id: String)
    case application(pid: pid_t)
}
```

No controller:

```swift
var destinationProvider: (() -> DictationDestination?)?
var transcriptSink: ((String, DictationDestination) -> Bool)?
private var recordingDestination: DictationDestination?
```

Em `begin()`, imediatamente antes de `recorder.start()`:

```swift
recordingDestination = destinationProvider?()
```

Em falha de `recorder.start()` e em `cancel()`:

```swift
recordingDestination = nil
```

Em `finish()`, capturar e limpar:

```swift
let destination = recordingDestination
recordingDestination = nil
```

- [ ] **Step 4: Entregar somente ao destino capturado**

No bloco main após a transcrição:

```swift
guard !trimmed.isEmpty else { return }
switch destination {
case .some(.ask(let id)):
    if self.transcriptSink?(trimmed, .ask(id: id)) != true {
        Self.copy(trimmed)
        self.flash(.error("Pergunta mudou — texto copiado"))
    }
case .some(.application(let pid)):
    if !Self.insert(trimmed, expectedPID: pid) {
        self.flash(.error("App mudou — texto copiado"))
    }
case .none:
    Self.copy(trimmed)
    self.flash(.error("Sem destino — texto copiado"))
}
```

Adicionar:

```swift
private static func copy(_ text: String) {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(text, forType: .string)
}
```

- [ ] **Step 5: Atualizar o wiring do app**

Em `applicationDidFinishLaunching`:

```swift
dictation.destinationProvider = { [weak self] in
    if let id = self?.askStore?.state.active?.id {
        return .ask(id: id)
    }
    guard let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier else {
        return nil
    }
    return .application(pid: pid)
}

dictation.transcriptSink = { [weak self] text, destination in
    guard case .ask(let id) = destination,
          self?.askStore?.state.active?.id == id else {
        return false
    }
    self?.askStore?.send(.appendText(id: id, text: text))
    return true
}
```

- [ ] **Step 6: Documentar o fallback seguro**

Adicionar em `docs/dictation.md`, após o fluxo de inserção:

```markdown
O Knobler fixa o destino quando a gravação começa. Se você trocar de aplicativo
ou se a pergunta ativa mudar antes do fim da transcrição, ele não cola no lugar
errado: deixa o texto no clipboard e mostra “texto copiado” no notch.
```

- [ ] **Step 7: Verificar os três destinos**

1. Gravar no TextEdit e permanecer nele: texto é colado e clipboard anterior volta.
2. Gravar no TextEdit e trocar para Terminal durante “Transcrevendo”: nada é colado no Terminal; transcript fica no clipboard.
3. Gravar com Ask `req-1` aberto e resolver/trocar a pergunta durante a transcrição: texto não entra na nova pergunta; fica no clipboard.

Run final:

```bash
/tmp/knobler-askcheck
xcodebuild -project Knobler.xcodeproj -scheme Knobler -configuration Debug \
  -derivedDataPath /tmp/knobler-dictation-plan CODE_SIGNING_ALLOWED=NO build
/tmp/knobler-dictation-plan/Build/Products/Debug/Knobler.app/Contents/MacOS/Knobler --selfcheck
```

Expected: `askcheck: OK`, `BUILD SUCCEEDED`, `selfcheck: dictation OK`.

- [ ] **Step 8: Commit**

```bash
git add Knobler/Dictation.swift Knobler/KnoblerApp.swift \
  Knobler/AskFeature.swift tools/askcheck.swift docs/dictation.md
git commit -m "fix(dictation): bind transcript to captured destination"
```

---

### Task 7: Limpar o tap quando o audio engine falhar ao iniciar

**Files:**
- Modify: `Knobler/Dictation.swift:104-140`

**Interfaces:**
- Consumes: `AVAudioEngine.start()`, `AVAudioInputNode.removeTap(onBus:)`.
- Produces: `MicRecorder.cleanup()` usado por falha, `stop()` e encerramento.

- [ ] **Step 1: Extrair cleanup idempotente**

Adicionar ao `MicRecorder`:

```swift
private func cleanup() {
    engine.inputNode.removeTap(onBus: 0)
    engine.stop()
    converter = nil
}
```

Alterar `stop()`:

```swift
func stop() -> [Float] {
    cleanup()
    samplesLock.lock()
    let captured = samples
    samplesLock.unlock()
    return captured
}
```

- [ ] **Step 2: Limpar se `engine.start()` lançar**

Trocar o final de `start()`:

```swift
engine.prepare()
do {
    try engine.start()
} catch {
    cleanup()
    throw error
}
```

- [ ] **Step 3: Verificar dispositivo inválido e recuperação**

Com entrada Bluetooth/virtual que falhe no start, tentar ditado.

Expected: mostra “Sem acesso ao microfone”, `/status` mantém `recording == false`, e uma segunda tentativa após escolher um microfone válido funciona sem reiniciar o Knobler.

Rodar o crash guard determinístico:

```bash
/tmp/knobler-dictation-plan/Build/Products/Debug/Knobler.app/Contents/MacOS/Knobler --selfcheck
```

Expected: `selfcheck: dictation OK`.

- [ ] **Step 4: Build e commit**

```bash
xcodebuild -project Knobler.xcodeproj -scheme Knobler -configuration Debug \
  -derivedDataPath /tmp/knobler-dictation-plan CODE_SIGNING_ALLOWED=NO build
git add Knobler/Dictation.swift
git commit -m "fix(dictation): clean audio tap after start failure"
```

Expected: `BUILD SUCCEEDED`.

---

### Task 8: Isolar o controller à MainActor e eliminar warnings de concorrência

**Files:**
- Modify: `Knobler/Dictation.swift:18-19, 197-349`

**Interfaces:**
- Consumes: callbacks de áudio fora da main e engines assíncronos.
- Produces: `@MainActor DictationController` e `TranscriptionEngine: Sendable`.

- [ ] **Step 1: Registrar os warnings atuais**

Run:

```bash
xcodebuild -project Knobler.xcodeproj -scheme Knobler -configuration Debug \
  -derivedDataPath /tmp/knobler-concurrency CODE_SIGNING_ALLOWED=NO \
  SWIFT_STRICT_CONCURRENCY=complete clean build 2>&1 | \
  tee /tmp/knobler-concurrency.log
grep 'Dictation.swift.*warning:' /tmp/knobler-concurrency.log
```

Expected: três warnings de captura de `DictationController` não-`Sendable`.

- [ ] **Step 2: Declarar isolamento e sendability**

Alterar:

```swift
protocol TranscriptionEngine: Sendable {
    func transcribe(_ samples: [Float]) async throws -> String
}

@MainActor
final class DictationController {
```

`ParakeetEngine` é actor e já é `Sendable`; marcar o tipo de valor:

```swift
struct DeepgramEngine: TranscriptionEngine, Sendable {
```

- [ ] **Step 3: Remover dispatches redundantes e atravessar o callback de áudio corretamente**

Em `prepareLocalEngine()`, manter `Task { [weak self] in ... }` e atualizar diretamente após os `await`:

```swift
Task { [weak self] in
    guard let self else { return }
    try? await parakeet.prepare()
    modelReady = await parakeet.ready
    preparing = false
}
```

No `onLevel`, atravessar explicitamente para a main actor:

```swift
recorder.onLevel = { [weak self] level in
    Task { @MainActor in
        guard self?.recording == true else { return }
        self?.setState(.recording(level: level))
    }
}
```

No `Task` de transcrição, remover os três `DispatchQueue.main.async`; como o task herda a main actor, atualizar `transcribing`, estado, destino e flash diretamente depois de cada `await`.

- [ ] **Step 4: Rodar strict concurrency e filtrar somente o ditado**

Run:

```bash
xcodebuild -project Knobler.xcodeproj -scheme Knobler -configuration Debug \
  -derivedDataPath /tmp/knobler-concurrency CODE_SIGNING_ALLOWED=NO \
  SWIFT_STRICT_CONCURRENCY=complete clean build 2>&1 | \
  tee /tmp/knobler-concurrency.log
test -z "$(grep 'Dictation.swift.*warning:' /tmp/knobler-concurrency.log)"
```

Expected: `BUILD SUCCEEDED` e nenhum warning originado em `Dictation.swift`. Warnings preexistentes de outros módulos não pertencem a este plano.

- [ ] **Step 5: Rodar todos os checks**

```bash
swiftc Knobler/AskModels.swift Knobler/AskFeature.swift tools/askcheck.swift \
  -o /tmp/knobler-askcheck && /tmp/knobler-askcheck
/tmp/knobler-concurrency/Build/Products/Debug/Knobler.app/Contents/MacOS/Knobler --selfcheck
```

Expected: `askcheck: OK` e `selfcheck: dictation OK`.

- [ ] **Step 6: Smoke test ponta a ponta**

Executar:

1. Local: gravar uma frase no TextEdit, confirmar transcrição e restauração do clipboard.
2. Formatter ligado: confirmar texto formatado; parar Ollama e confirmar fallback para o bruto.
3. Deepgram com chave: confirmar transcrição cloud sem carregar Parakeet.
4. Deepgram sem chave: confirmar erro imediato.
5. Apertar outra tecla durante o hold: confirmar cancelamento e ausência de texto.
6. Trocar de app durante transcrição: confirmar fallback para clipboard.

Expected: nenhuma gravação fica presa, nenhum texto vai para destino diferente e nenhuma transcrição é perdida.

- [ ] **Step 7: Commit**

```bash
git add Knobler/Dictation.swift
git commit -m "refactor(dictation): isolate controller to main actor"
```

---

## Cobertura dos achados

1. Perda/sobrescrita do clipboard — Task 1.
2. Release ignorado ao desligar ditado — Task 2.
3. Timer antigo escondendo estado novo — Task 3.
4. Parakeet carregado no modo Deepgram — Task 4.
5. Deepgram sem chave caindo silenciosamente no local — Task 5.
6. Destino decidido depois da transcrição — Task 6.
7. Tap pendurado quando `AVAudioEngine.start()` falha — Task 7.
8. Warnings e dívida de concorrência Swift 6 — Task 8.

Nenhum achado ficou sem task; os nomes e assinaturas consumidos pelas tasks posteriores são definidos antes do uso.
