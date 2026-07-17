# Capturas de tela direto no shelf (v0.10) — Plano de Implementação

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Toda captura de tela do macOS entra automaticamente na prateleira do notch (por referência) e o card dá um peek de 1,5s confirmando.

**Architecture:** `ScreenshotWatcher` (novo) roda um `NSMetadataQuery` vivo com predicado `kMDItemIsScreenCapture == 1 && kMDItemContentTypeTree == public.image`, ignora o gathering inicial e emite `onScreenshot(URL)` só para capturas novas. O AppDelegate liga isso ao `ShelfStore` existente (`shelf.add`) e faz o peek (`setExpandedDirect(true)` + fechar após 1,5s), respeitando notch ocupado (pergunta/ditado). Toggle nos Ajustes com start/stop no mesmo sink de `objectWillChange` que o `localAPI` já usa.

**Tech Stack:** Swift/AppKit/Foundation (NSMetadataQuery), SwiftUI (toggle), xcodegen.

**Spec:** `docs/superpowers/specs/2026-07-17-capturas-shelf-design.md`

## Global Constraints

- Deployment target macOS 14.2 (project.yml); app roda no Tahoe (26).
- Bundle: `com.zoi.knobler`; hardened runtime OFF; assinatura manual Apple Development.
- O repo NÃO tem test target. Validação = build Release + E2E manual (snapshot não se aplica: comportamento, não layout novo).
- Arquivo Swift NOVO exige `xcodegen generate` antes do `xcodebuild` — senão o build falha com "cannot find X in scope" (o .xcodeproj é gitignored e fica stale).
- Build: `xcodebuild -project Knobler.xcodeproj -scheme Knobler -configuration Release build` (esperar `** BUILD SUCCEEDED **`).
- Comentários e strings de UI em pt-BR, no tom dos arquivos existentes (comentários dizem o porquê; prefixo `ponytail:` para simplificações deliberadas).
- Cada módulo consulta o toggle no momento do evento — desligar vale na hora, sem reiniciar (padrão do AppSettings).
- Commits pequenos por task, mensagem em pt-BR.

---

### Task 1: Toggle screenshotsToShelf nos Ajustes

**Files:**
- Modify: `Knobler/AppSettings.swift`

**Interfaces:**
- Produces: `AppSettings.shared.screenshotsToShelf: Bool` (default true).

- [ ] **Step 1: Adicionar a flag**

Em `Knobler/AppSettings.swift`, depois da propriedade `dictationCloud` (linha ~53), adicionar:

```swift
    /// Toda captura de tela do macOS entra na prateleira automaticamente.
    @Published var screenshotsToShelf: Bool {
        didSet { UserDefaults.standard.set(screenshotsToShelf, forKey: "screenshotsToShelf") }
    }
```

No `private init()`, junto das outras flags (depois de `dictationCloud = ...`, linha ~82):

```swift
        screenshotsToShelf = flag("screenshotsToShelf")
```

- [ ] **Step 2: Toggle na UI**

Em `SettingsView`, na Section "Notch", depois do `Toggle("Indicador de microfone"...)` (linha ~100), adicionar:

```swift
                Toggle("Capturas de tela vão pro shelf", isOn: $settings.screenshotsToShelf)
```

- [ ] **Step 3: Buildar e commitar**

Run: `xcodebuild -project Knobler.xcodeproj -scheme Knobler -configuration Release build 2>&1 | tail -3`
Expected: `** BUILD SUCCEEDED **`

```bash
git add Knobler/AppSettings.swift
git commit -m "Capturas: toggle screenshotsToShelf nos Ajustes"
```

---

### Task 2: ScreenshotWatcher (NSMetadataQuery)

**Files:**
- Create: `Knobler/ScreenshotWatcher.swift`

**Interfaces:**
- Consumes: `AppSettings.shared.screenshotsToShelf` (Task 1).
- Produces: `ScreenshotWatcher` com `var onScreenshot: ((URL) -> Void)?`, `func start()`, `func stop()`.

- [ ] **Step 1: Criar o arquivo completo**

Criar `Knobler/ScreenshotWatcher.swift`:

```swift
//
//  ScreenshotWatcher.swift
//  Knobler
//
//  Observa capturas de tela do macOS via Spotlight (NSMetadataQuery) e
//  emite a URL de cada captura NOVA. Pega em qualquer pasta configurada
//  (⌘⇧5 → "Salvar em"), sem polling nem ler com.apple.screencapture.
//  ponytail: só imagens — gravações de tela (.mov) também têm o atributo
//  de captura mas não cabem na prateleira.
//

import Foundation

final class ScreenshotWatcher {
    /// URL de uma captura nova (arquivo já gravado). Sempre na main queue.
    var onScreenshot: ((URL) -> Void)?

    private var query: NSMetadataQuery?
    /// O primeiro resultado do query traz TODAS as capturas antigas do índice;
    /// só emitimos depois desse gathering — senão o shelf enche de histórico.
    private var gathered = false

    func start() {
        guard query == nil else { return }
        let query = NSMetadataQuery()
        // capturas de tela que são imagem (kMDItemIsScreenCapture só existe em
        // itens gerados pela captura do sistema)
        query.predicate = NSPredicate(
            format: "kMDItemIsScreenCapture == 1 && kMDItemContentTypeTree == %@",
            "public.image")
        query.searchScopes = [NSMetadataQueryLocalComputerScope]
        // mais recentes primeiro: o item [0] após um update é a captura nova
        query.sortDescriptors = [NSSortDescriptor(key: kMDItemFSCreationDate as String,
                                                  ascending: false)]

        NotificationCenter.default.addObserver(
            self, selector: #selector(finishedGathering),
            name: .NSMetadataQueryDidFinishGathering, object: query)
        NotificationCenter.default.addObserver(
            self, selector: #selector(updated),
            name: .NSMetadataQueryDidUpdate, object: query)

        gathered = false
        query.start()
        self.query = query
    }

    func stop() {
        guard let query else { return }
        query.stop()
        NotificationCenter.default.removeObserver(self, name: .NSMetadataQueryDidFinishGathering, object: query)
        NotificationCenter.default.removeObserver(self, name: .NSMetadataQueryDidUpdate, object: query)
        self.query = nil
    }

    @objc private func finishedGathering(_ note: Notification) {
        // marca o baseline: capturas já existentes não entram no shelf
        gathered = true
    }

    @objc private func updated(_ note: Notification) {
        guard gathered, let query else { return }
        // durante o processamento do update o query precisa ficar "parado"
        query.disableUpdates()
        defer { query.enableUpdates() }

        // itens adicionados nesta atualização (chave presente a partir do macOS 10.9)
        let added = note.userInfo?[kMDQueryUpdateAddedItems as String] as? [NSMetadataItem]
        guard let added, !added.isEmpty else { return }

        for item in added {
            guard let path = item.value(forAttribute: kMDItemPath as String) as? String
            else { continue }
            // ignora o arquivo temporário "." que o screencapture cria antes de gravar
            guard !(path as NSString).lastPathComponent.hasPrefix(".") else { continue }
            let url = URL(fileURLWithPath: path)
            DispatchQueue.main.async { [weak self] in
                self?.onScreenshot?(url)
            }
        }
    }

    deinit { stop() }
}
```

- [ ] **Step 2: Regenerar projeto (arquivo novo!) e buildar**

Run: `xcodegen generate && xcodebuild -project Knobler.xcodeproj -scheme Knobler -configuration Release build 2>&1 | tail -3`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Commit**

```bash
git add Knobler/ScreenshotWatcher.swift Knobler.xcodeproj
git commit -m "Capturas: ScreenshotWatcher via NSMetadataQuery (só imagens, só novas)"
```

(Nota: `Knobler.xcodeproj` é gitignored — o `git add` dele é no-op; commite só o .swift.)

---

### Task 3: Fiação no AppDelegate + peek de 1,5s

**Files:**
- Modify: `Knobler/KnoblerApp.swift`

**Interfaces:**
- Consumes: `ScreenshotWatcher` (Task 2), `AppSettings.shared.screenshotsToShelf` (Task 1), `shelf: ShelfStore` (existente), `vm.ask`/`vm.dictation`/`vm.setExpandedDirect` (existentes).

- [ ] **Step 1: Instanciar o watcher**

Em `Knobler/KnoblerApp.swift`, junto dos outros módulos (perto de `private let shelf = ShelfStore()`, linha ~38), adicionar:

```swift
    private let screenshots = ScreenshotWatcher()
    private var screenshotPeekWork: DispatchWorkItem?
```

- [ ] **Step 2: Ligar o callback + peek**

Em `applicationDidFinishLaunching`, depois do bloco `dictation.transcriptSink = { ... }` (perto da fiação de ditado, linha ~101), adicionar:

```swift
        // capturas de tela entram na prateleira e o notch dá um peek
        screenshots.onScreenshot = { [weak self] url in
            guard let self else { return }
            self.shelf.add(url)
            self.peekShelf()
        }
```

- [ ] **Step 3: Método peekShelf**

Ainda em `KnoblerApp.swift`, adicionar um método na AppDelegate (perto de `viewModelUnderMouse()`, linha ~288):

```swift
    /// Expande o card mostrando a prateleira por 1,5s e fecha. Pergunta ou
    /// ditado na tela têm prioridade → só adiciona, sem peek. Nova captura
    /// renova o timer; mouse em cima segura (o hover reprograma o fechamento).
    private func peekShelf() {
        let busy = notches.values.contains {
            $0.viewModel.ask != nil || $0.viewModel.dictation != nil
        }
        guard !busy else { return }

        notches.values.forEach { $0.viewModel.setExpandedDirect(true) }
        screenshotPeekWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.notches.values.forEach { $0.viewModel.setExpandedDirect(false) }
        }
        screenshotPeekWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: work)
    }
```

- [ ] **Step 4: Start/stop pelo toggle**

Em `applicationDidFinishLaunching`, no sink de `AppSettings.shared.objectWillChange` (o bloco `apiCancellable = ...` que já liga/desliga `apiServer`, linha ~199), dentro da closure do `.sink`, depois do `if AppSettings.shared.localAPI { ... } else { ... }`, adicionar:

```swift
                    if AppSettings.shared.screenshotsToShelf {
                        self?.screenshots.start()
                    } else {
                        self?.screenshots.stop()
                    }
```

- [ ] **Step 5: Buildar e commitar**

Run: `xcodebuild -project Knobler.xcodeproj -scheme Knobler -configuration Release build 2>&1 | tail -3`
Expected: `** BUILD SUCCEEDED **`

```bash
git add Knobler/KnoblerApp.swift
git commit -m "Capturas: fiação no app (shelf.add + peek 1,5s) + start/stop pelo toggle"
```

---

### Task 4: Deploy + validação E2E

**Files:** nenhum novo — deploy e teste do app real.

- [ ] **Step 1: Reinstalar e relançar**

```bash
osascript -e 'tell application "Knobler" to quit'; sleep 1
ditto "$(ls -d ~/Library/Developer/Xcode/DerivedData/Knobler-*/Build/Products/Release/Knobler.app | head -1)" /Applications/Knobler.app
open /Applications/Knobler.app && sleep 2 && pgrep -x Knobler
```

Expected: PID impresso.

- [ ] **Step 2: E2E manual (pedir ao usuário)**

O agente não tira captura de tela do sistema — pedir ao usuário este roteiro:

1. `⌘⇧4` e selecionar uma região → soltar. Esperado: o card do notch faz peek
   de ~1,5s mostrando a prateleira com a captura nova; depois fecha.
2. Passar o mouse sobre o card durante o peek → ele NÃO fecha enquanto o mouse
   está em cima (fecha quando sair).
3. Arrastar a captura do shelf pra uma janela do Finder / campo de anexo →
   funciona (é o arquivo real referenciado).
4. `⌘⇧3` (tela cheia) duas vezes seguidas rápido → as duas entram; o peek
   renova (não pisca fechando entre uma e outra).
5. Ajustes → desligar "Capturas de tela vão pro shelf" → nova captura NÃO entra.
6. Religar → captura volta a entrar.
7. Com uma pergunta ativa no notch (`tools/knobler ask "x" "a" "b"` noutro
   terminal) → tirar captura: entra no shelf mas SEM peek (a pergunta continua
   na tela); responder a pergunta e conferir que a captura está no shelf.

- [ ] **Step 3: Fechar a versão**

Depois do OK do usuário no E2E:

```bash
git add -A && git status --short
```

Conferir que só entraram arquivos da feature; atualizar `HANDOFF.md` (nova seção
v0.10) e a seção v0.10 no MEMORY.md do projeto; commitar:

```bash
git commit -m "Capturas de tela no shelf v0.10: NSMetadataQuery → prateleira + peek"
```

---

## Self-review (feito na escrita)

- **Cobertura da spec:** detecção NSMetadataQuery só-imagem/só-novas (T2),
  referência via shelf.add existente (T3), peek 1,5s renovável respeitando
  notch ocupado (T3 peekShelf), toggle default ligado + start/stop na hora
  (T1+T3), validação E2E com todas as bordas da spec (T4). Filtro do arquivo
  temporário `.` (T2 Step 1). Captura deletada depois: coberto pelo init do
  ShelfStore existente (nada a fazer, citado na spec).
- **Placeholders:** nenhum; todo step tem código ou comando completo.
- **Consistência de tipos:** `screenshotsToShelf` (T1) lido em T3; `onScreenshot:
  ((URL) -> Void)?` + `start()`/`stop()` (T2) consumidos em T3; `shelf.add`,
  `setExpandedDirect`, `vm.ask`, `vm.dictation` são APIs já existentes no repo.
- **Risco declarado:** a chave exata do userInfo do update
  (`kMDQueryUpdateAddedItems`) e o comportamento do gathering inicial são a
  parte a confirmar no E2E — se o peek não disparar, logar `note.userInfo?.keys`
  no `updated(_:)` pra ver o que o macOS 26 manda, sem mudar a estrutura.
