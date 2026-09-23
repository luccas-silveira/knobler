# Extrair texto da tela — plano de implementação

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Peça "Texto da tela": atalho (⌃⇧T), ícone no notch ou item de menu congela a tela, a pessoa seleciona uma região, o texto reconhecido vai pro clipboard e o notch confirma.

**Architecture:** Três arquivos novos. `TextoDaTela.swift` é lógica pura (geometria, OCR via Vision, texto do aviso) e compila isolado no check. `SelecaoDeTela.swift` é a camada AppKit (um painel por monitor mostrando a foto congelada). `TextoDaTelaServico.swift` é o coordenador (permissão, captura via ScreenCaptureKit, camada, OCR, clipboard, aviso, atalho) e é o `PluginServico` que a peça devolve ao nascer.

**Tech Stack:** Swift 5, AppKit, SwiftUI, ScreenCaptureKit (`SCScreenshotManager.captureImage(contentFilter:configuration:)`, macOS 14.0), Vision (`VNRecognizeTextRequest`), Carbon hotkeys do vendor `KeyboardShortcuts`.

**Spec:** `docs/superpowers/specs/2026-09-23-extrair-texto-tela-design.md` (dossiê: `docs/superpowers/research/2026-09-23-extrair-texto-tela-research.md`)

## Global Constraints

- Deployment target macOS 14.2. Nada de `captureImage(in:)` (15.2), `RecognizeTextRequest` (15) nem `CGWindowListCreateImage` (obsoleta no 15).
- Vorssaint (`~/Desktop/Projetos/vorssaint-utils`) é GPL-3.0: só referência, **nenhum trecho copiado ou adaptado**.
- Comentários e strings de UI em pt-BR; simplificação deliberada marcada com `// ponytail:`.
- Nunca editar `Knobler.xcodeproj`; arquivo novo exige `xcodegen generate`.
- Peça nasce **desinstalada** em instalação nova (como `.monitores`).
- Atalho padrão ⌃⇧T; só registrado com a peça ligada.
- Reconhecimento: nível `.accurate`, `usesLanguageCorrection = true` sempre, idiomas `["pt-BR", "en-US"]`.
- Seleção menor que 4 pt em qualquer lado = cancelamento silencioso.
- Textos do notch: "Texto copiado", "Nenhum texto encontrado", "Não consegui ler a tela".
- Não versionar à mão: CHANGELOG em `## [Unreleased]`, novidade em `Knobler/Novidades/0.34.0.html` + `NovidadesCatalogo.versoes`.

## Review Focus

1. Monitor secundário à esquerda/abaixo do principal (origem negativa): o recorte tem que cair na região certa — teste de geometria com origem negativa (Task 1).
2. Desligar a peça Monitores (ou esta peça) não pode matar o atalho da outra — teste no check do vendor (Task 3).
3. Instalação nova não pode ligar a peça sozinha e pedir Gravação de Tela — asserção no `plugincheck` (Task 4).
4. Seleção mínima/clique sem arrasto não pode ler nada nem mexer no clipboard — teste de `selecaoValida` (Task 1).
5. Texto longo/multilinha no aviso: primeira linha, cortada com "…" — teste de `resumo` (Task 1).

---

### Task 1: Núcleo puro (geometria, OCR, aviso) + check

**Files:**
- Create: `Knobler/TextoDaTela.swift`
- Create: `tools/textodatelacheck.swift`
- Modify: `tools/check.sh` (nova linha `swift_check`, junto das outras perto da linha 127)

**Interfaces:**
- Produces:
  - `enum TextoDaTela`
  - `static func recortePixels(selecao: CGRect, tela: CGRect, escala: CGFloat) -> CGRect` — `selecao` e `tela` em pontos globais AppKit (origem embaixo-esquerda do principal); devolve pixels da foto do monitor, origem em cima-esquerda, inteiros.
  - `static func selecaoValida(_ r: CGRect) -> Bool`
  - `static func linhas(em imagem: CGImage) throws -> [String]`
  - `static func resumo(_ texto: String, limite: Int = 60) -> String`

- [ ] **Step 1: Escrever o check (falha por falta do arquivo)**

```swift
//
//  textodatelacheck.swift
//  Cobre a parte pura do Texto da tela (TextoDaTela.swift): recorte em pixels
//  com Retina e monitor de origem negativa, descarte de seleção pequena, resumo
//  do aviso e o OCR de verdade numa imagem gerada.
//
//  xcrun swiftc -parse-as-library -swift-version 5 \
//    Knobler/TextoDaTela.swift tools/textodatelacheck.swift \
//    -o /tmp/textodatelacheck && /tmp/textodatelacheck
//

import AppKit

@main
enum TextoDaTelaCheck {
    static func main() {
        testRecorteRetina()
        testRecorteOrigemNegativa()
        testSelecaoValida()
        testResumo()
        testOCR()
        print("textodatelacheck ok")
    }

    /// Principal 1440×900 em 2x: seleção a 100 pt da esquerda e 200 pt do topo.
    static func testRecorteRetina() {
        let tela = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let sel = CGRect(x: 100, y: 900 - 200 - 50, width: 300, height: 50)
        let r = TextoDaTela.recortePixels(selecao: sel, tela: tela, escala: 2)
        assert(r == CGRect(x: 200, y: 400, width: 600, height: 100), "retina: \(r)")
    }

    /// Secundário à esquerda e abaixo do principal, 1x.
    static func testRecorteOrigemNegativa() {
        let tela = CGRect(x: -1920, y: -300, width: 1920, height: 1080)
        let sel = CGRect(x: -1900, y: 700, width: 100, height: 40)
        let r = TextoDaTela.recortePixels(selecao: sel, tela: tela, escala: 1)
        // x: -1900 - (-1920) = 20; y do topo: 780 - (700 + 40) = 40
        assert(r == CGRect(x: 20, y: 40, width: 100, height: 40), "negativa: \(r)")
    }

    static func testSelecaoValida() {
        assert(!TextoDaTela.selecaoValida(CGRect(x: 0, y: 0, width: 3.9, height: 100)))
        assert(!TextoDaTela.selecaoValida(CGRect(x: 0, y: 0, width: 100, height: 0)))
        assert(TextoDaTela.selecaoValida(CGRect(x: 0, y: 0, width: 4, height: 4)))
    }

    static func testResumo() {
        assert(TextoDaTela.resumo("  Olá mundo \nsegunda linha") == "Olá mundo")
        let longo = String(repeating: "a", count: 80)
        let r = TextoDaTela.resumo(longo, limite: 60)
        assert(r.count == 60 && r.hasSuffix("…"), "resumo: \(r)")
    }

    /// OCR pelo mesmo caminho do app, sobre uma imagem com texto conhecido.
    static func testOCR() {
        let w = 800, h = 120
        let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(.white); ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
        ("Knobler extrai texto" as NSString).draw(
            at: NSPoint(x: 20, y: 35),
            withAttributes: [.font: NSFont.systemFont(ofSize: 48), .foregroundColor: NSColor.black])
        NSGraphicsContext.current = nil
        let linhas = try! TextoDaTela.linhas(em: ctx.makeImage()!)
        assert(linhas.joined(separator: " ") == "Knobler extrai texto", "ocr: \(linhas)")
    }
}
```

- [ ] **Step 2: Rodar e ver falhar**

Run: `xcrun swiftc -parse-as-library -swift-version 5 Knobler/TextoDaTela.swift tools/textodatelacheck.swift -o /tmp/textodatelacheck`
Expected: erro "no such file" para `Knobler/TextoDaTela.swift`.

- [ ] **Step 3: Implementar `Knobler/TextoDaTela.swift`**

```swift
//
//  TextoDaTela.swift
//  Knobler
//
//  A parte pura do Texto da tela: converter a seleção em pixels da foto do
//  monitor, ler o texto com o Vision e montar o resumo do aviso. Sem AppKit de
//  propósito — o textodatelacheck compila isto isolado.
//

import CoreGraphics
import Foundation
import Vision

enum TextoDaTela {
    /// Seleção em pontos globais do AppKit (origem embaixo-esquerda do
    /// principal) → retângulo em pixels da foto de `tela`, origem no topo.
    static func recortePixels(selecao: CGRect, tela: CGRect, escala: CGFloat) -> CGRect {
        CGRect(x: (selecao.minX - tela.minX) * escala,
               y: (tela.maxY - selecao.maxY) * escala,
               width: selecao.width * escala,
               height: selecao.height * escala).integral
    }

    /// Clique sem arrasto ou fiapo de seleção conta como cancelar.
    static func selecaoValida(_ r: CGRect) -> Bool {
        r.width >= 4 && r.height >= 4
    }

    /// Linhas na ordem que o Vision devolve (já é a de leitura).
    /// ponytail: sem reordenação por coluna; ordenar por midY/minX se texto em
    /// colunas vier embaralhado.
    static func linhas(em imagem: CGImage) throws -> [String] {
        let pedido = VNRecognizeTextRequest()
        pedido.recognitionLevel = .accurate
        pedido.usesLanguageCorrection = true
        pedido.recognitionLanguages = ["pt-BR", "en-US"]
        try VNImageRequestHandler(cgImage: imagem, options: [:]).perform([pedido])
        return (pedido.results ?? []).compactMap { $0.topCandidates(1).first?.string }
    }

    /// Primeira linha não vazia, cortada com "…" pra caber no card.
    static func resumo(_ texto: String, limite: Int = 60) -> String {
        let linha = texto.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty } ?? ""
        return linha.count > limite ? String(linha.prefix(limite - 1)) + "…" : linha
    }
}
```

- [ ] **Step 4: Rodar e ver passar**

Run: `xcrun swiftc -parse-as-library -swift-version 5 Knobler/TextoDaTela.swift tools/textodatelacheck.swift -o /tmp/textodatelacheck && /tmp/textodatelacheck`
Expected: `textodatelacheck ok`. Se o OCR divergir só em caixa/acentuação, ajuste o texto de teste — não afrouxe a asserção para `contains`.

- [ ] **Step 5: Registrar no gate**

Em `tools/check.sh`, logo abaixo da linha do `permissioncheck`:

```bash
swift_check textodatelacheck    Knobler/TextoDaTela.swift tools/textodatelacheck.swift
```

Run: `./tools/check.sh` — Expected: todos os checks passam, incluindo `textodatelacheck`.

- [ ] **Step 6: Commit**

```bash
git add Knobler/TextoDaTela.swift tools/textodatelacheck.swift tools/check.sh
git commit -m "feat(texto-da-tela): núcleo puro de recorte, OCR e resumo"
```

---

### Task 2: Permissão de Gravação de Tela

**Files:**
- Modify: `Knobler/Permissions.swift` (enum :29, `title` :35, `why` :50, `settingsURL` :78, `status` :98, `canRequest` :171, `request` :~182; comentário do topo que conta os casos)
- Modify: `tools/permissioncheck.swift`

**Interfaces:**
- Produces: `Permission.gravacaoTela` (rawValue `"gravacaoTela"` — é a string usada em `Plugin.permissao` na Task 4).

- [ ] **Step 1: Teste que falha** — em `PermissionCheck.main()`, depois das asserções de `lembretes`:

```swift
        assert(Permission.gravacaoTela.settingsURL.absoluteString.hasSuffix("Privacy_ScreenCapture"))
        assert(Permission.gravacaoTela.title == "Gravação de tela")
```

Run: `xcrun swiftc -parse-as-library -swift-version 5 Knobler/Permissions.swift tools/permissioncheck.swift -o /tmp/permissioncheck`
Expected: erro "type 'Permission' has no member 'gravacaoTela'".

- [ ] **Step 2: Implementar** — adicionar o caso e cada ramo:

```swift
    case acessibilidade, microfone, camera, calendario, lembretes, bluetooth, redeLocal, arquivos,
         audioSistema, gravacaoTela
```

`title`: `case .gravacaoTela: return "Gravação de tela"`
`why`: `case .gravacaoTela: return "Fotografar a tela pra extrair texto da região que você selecionar."`
`settingsURL`: `case .gravacaoTela: anchor = "Privacy_ScreenCapture"`
`status`:

```swift
        case .gravacaoTela:
            // Sem API que distinga negada de nunca pedida, igual à Acessibilidade.
            return CGPreflightScreenCaptureAccess() ? .concedida : .naoPedida
```

`canRequest`: incluir `.gravacaoTela` na lista que retorna `true`.
`request`:

```swift
        case .gravacaoTela:
            // O balão aparece uma vez só; a concessão vale depois de relançar
            // (o "Sair e Reabrir" do próprio macOS cobre isso).
            _ = CGRequestScreenCaptureAccess()
            done()
```

Atualize o comentário do topo do arquivo que conta os estados/casos.

- [ ] **Step 3: Rodar e ver passar**

Run: `xcrun swiftc -parse-as-library -swift-version 5 Knobler/Permissions.swift tools/permissioncheck.swift -o /tmp/permissioncheck && /tmp/permissioncheck`
Expected: passa. Compile também o app (`xcodebuild -project Knobler.xcodeproj -scheme Knobler -configuration Debug build`) — `switch` exaustivo em outros arquivos que iterem `Permission` vai acusar ramo faltando; preencha cada um.

- [ ] **Step 4: Commit**

```bash
git add Knobler/Permissions.swift tools/permissioncheck.swift
git commit -m "feat(permissões): Gravação de tela"
```

---

### Task 3: Atalhos por nome no vendor + Monitores

**Files:**
- Modify: `Vendor/MonitorControl/KeyboardShortcuts.swift:166` (novo método ao lado de `removeAllHandlers`)
- Modify: `Vendor/PROVENANCE.md` (anotar a modificação)
- Modify: `Knobler/Monitores.swift:107`

**Interfaces:**
- Produces: `KeyboardShortcuts.removeHandlers(for name: KeyboardShortcuts.Name)`

- [ ] **Step 1: Implementar no vendor**, logo após `removeAllHandlers()`:

```swift
  /// Knobler: remove só os handlers de um nome. `removeAllHandlers` derrubava
  /// o atalho de outras peças quando os Monitores paravam.
  static func removeHandlers(for name: Name) {
    self.keyDownHandlers[name] = nil
    self.keyUpHandlers[name] = nil
    if let shortcut = getShortcut(for: name) {
      self.unregisterIfUnused(shortcut)
    }
  }
```

Confirme lendo `unregisterIfUnused` que ele desregistra quando nenhum nome com handler usa o atalho; se ele olhar `disabledNames` em vez dos handlers, ajuste a condição dentro do novo método para `unregister(shortcut)` quando nenhum outro nome com handler tiver o mesmo `shortcut`.

- [ ] **Step 2: Monitores removem só os seus** — em `Monitores.stop()` troque `KeyboardShortcuts.removeAllHandlers()` por:

```swift
        Self.shortcutNames.forEach { KeyboardShortcuts.removeHandlers(for: $0.name) }
```

- [ ] **Step 3: PROVENANCE** — acrescente em `Vendor/PROVENANCE.md`, na seção do `KeyboardShortcuts.swift`: "2026-09-23 — `removeHandlers(for:)` adicionado pelo Knobler; Monitores deixou de usar `removeAllHandlers`."

- [ ] **Step 4: Verificar** — `xcodebuild -project Knobler.xcodeproj -scheme Knobler -configuration Debug build` compila. Validação do comportamento fica na Task 8 (desligar Monitores com a peça ligada e o ⌃⇧T segue funcionando).

- [ ] **Step 5: Commit**

```bash
git add Vendor/MonitorControl/KeyboardShortcuts.swift Vendor/PROVENANCE.md Knobler/Monitores.swift
git commit -m "fix(atalhos): Monitores param só os próprios atalhos"
```

---

### Task 4: Ficha da peça

**Files:**
- Modify: `Knobler/Plugin.swift` (`PluginID` :21, struct de efeitos junto das outras ~:195, `PluginDeps` :200, `PluginRegistry.todos` ~:300-345, `PluginHost` :470-495, `montar…` ~:770, `migrarSePreciso` :402)
- Modify: `Knobler/PluginsSettingsPane.swift:35-41` (cor)
- Modify: `tools/plugincheck.swift:121-127`

**Interfaces:**
- Produces: `PluginID.textoDaTela`; `struct TextoDaTelaEfeitos { var nascer: () -> PluginServico? }`; `PluginHost.textoDaTelaEfeitos`; `func montarTextoDaTela(_:)`.

- [ ] **Step 1: Teste que falha** — em `testDefaultsVazioViraOsOnze`, troque o conjunto esperado e acrescente a asserção:

```swift
        assert(PluginsInstalados.ler(d) == Set(PluginID.allCases).subtracting([.monitores, .textoDaTela]),
               "migração alterou as peças legadas: \(PluginsInstalados.ler(d))")
        assert(!PluginsInstalados.ler(d).contains(.textoDaTela), "Texto da tela precisa começar desinstalada")
```

Run: `./tools/check.sh` — Expected: `plugincheck` falha ("has no member 'textoDaTela'").

- [ ] **Step 2: Implementar**

`PluginID`: `case espelho, anotacao, notaRapida, previewLink, conversao, monitores, agentes, textoDaTela`

Efeitos (junto de `EspelhoEfeitos`):

```swift
/// Os efeitos que a montagem do Texto da tela precisa do app. Mesmo desenho do
/// `EspelhoEfeitos`: o serviço importa AppKit/ScreenCaptureKit, então `nascer`
/// é a peça inteira e mora no `AppDelegate`.
struct TextoDaTelaEfeitos {
    var nascer: () -> PluginServico? = { nil }
}
```

`PluginDeps`: `var textoDaTela = TextoDaTelaEfeitos()`
`PluginHost`: `var textoDaTelaEfeitos = TextoDaTelaEfeitos()` e `textoDaTela: textoDaTelaEfeitos` na chamada de `PluginDeps(...)` em `deps()`.
Registro (fim de `todos`):

```swift
        Plugin(id: .textoDaTela, nome: "Texto da tela",
               descricao: "Selecione uma área e copie o texto dela.",
               simbolo: "text.viewfinder", secao: nil, painel: nil,
               rotas: [], permissao: "gravacaoTela", pronta: true,
               nascer: montarTextoDaTela),
```

Montagem (junto de `montarEspelho`):

```swift
func montarTextoDaTela(_ deps: PluginDeps) -> PluginServico? {
    deps.textoDaTela.nascer()
}
```

`migrarSePreciso`: `PluginID.allCases.filter { $0 != .monitores && $0 != .textoDaTela }`
Cor: `case .textoDaTela: return .orange` em `PluginsSettingsPane.swift`.

- [ ] **Step 3: Rodar** — `./tools/check.sh` passa (atualize outras asserções do `plugincheck` que contem peças, lendo a mensagem de falha).

- [ ] **Step 4: Commit**

```bash
git add Knobler/Plugin.swift Knobler/PluginsSettingsPane.swift tools/plugincheck.swift
git commit -m "feat(texto-da-tela): ficha da peça, desinstalada por padrão"
```

---

### Task 5: Camada de seleção

**Files:**
- Create: `Knobler/SelecaoDeTela.swift`

**Interfaces:**
- Consumes: `TextoDaTela.selecaoValida(_:)`
- Produces:
  - `final class SelecaoDeTela`
  - `init(fotos: [(tela: NSScreen, foto: CGImage)], concluir: @escaping (NSScreen, CGRect)? -> Void)` — `CGRect` em pontos globais AppKit; `nil` = cancelado. `concluir` roda uma vez só, na main, depois dos painéis fechados.
  - `func mostrar()`, `func cancelar()`

- [ ] **Step 1: Implementar**

```swift
//
//  SelecaoDeTela.swift
//  Knobler
//
//  A camada do Texto da tela: um painel por monitor, acima do notch e de app
//  em tela cheia, mostrando a foto congelada escurecida. Arrastar desenha o
//  retângulo (a foto aparece clara dentro dele); soltar conclui, Esc ou clique
//  direito cancela. A seleção fica presa ao monitor onde o arraste começou —
//  o arraste pertence à view que recebeu o mouseDown.
//

import AppKit

final class SelecaoDeTela {
    private var paineis: [NSPanel] = []
    private var concluir: (((NSScreen, CGRect)?) -> Void)?
    private var observador: NSObjectProtocol?

    init(fotos: [(tela: NSScreen, foto: CGImage)], concluir: @escaping ((NSScreen, CGRect)?) -> Void) {
        self.concluir = concluir
        paineis = fotos.map { item in
            let painel = PainelChave(contentRect: item.tela.frame,
                                     styleMask: [.borderless, .nonactivatingPanel],
                                     backing: .buffered, defer: false)
            // acima do NotchWindow (.mainMenu + 3), como o Descanso
            painel.level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()))
            painel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
            painel.isOpaque = false
            painel.backgroundColor = .clear
            painel.hasShadow = false
            painel.setFrame(item.tela.frame, display: false)
            painel.contentView = VistaSelecao(foto: item.foto) { [weak self] local in
                guard let self else { return }
                guard let local, TextoDaTela.selecaoValida(local) else { return self.fechar(nil) }
                let global = local.offsetBy(dx: item.tela.frame.minX, dy: item.tela.frame.minY)
                self.fechar((item.tela, global))
            }
            return painel
        }
    }

    func mostrar() {
        // monitor entrou/saiu no meio: as fotos não batem mais com as telas
        observador = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.cancelar() }
        paineis.forEach { $0.orderFrontRegardless() }
        // o painel sob o cursor recebe o teclado (Esc)
        let mouse = NSEvent.mouseLocation
        (paineis.first { $0.frame.contains(mouse) } ?? paineis.first)?.makeKey()
        NSCursor.crosshair.push()
    }

    func cancelar() { fechar(nil) }

    private func fechar(_ resultado: (NSScreen, CGRect)?) {
        guard let concluir else { return }
        self.concluir = nil
        if let observador { NotificationCenter.default.removeObserver(observador) }
        NSCursor.pop()
        paineis.forEach { $0.orderOut(nil) }
        paineis = []
        DispatchQueue.main.async { concluir(resultado) }
    }
}

/// Painel sem borda que aceita teclado sem ativar o app.
private final class PainelChave: NSPanel {
    override var canBecomeKey: Bool { true }
}

private final class VistaSelecao: NSView {
    private let foto: CGImage
    private let fim: (CGRect?) -> Void
    private var inicio: NSPoint?
    private var atual: NSRect?

    init(foto: CGImage, fim: @escaping (CGRect?) -> Void) {
        self.foto = foto
        self.fim = fim
        super.init(frame: .zero)
    }
    required init?(coder: NSCoder) { fatalError() }

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .crosshair) }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.draw(foto, in: bounds)
        ctx.setFillColor(NSColor.black.withAlphaComponent(0.35).cgColor)
        ctx.fill(bounds)
        guard let r = atual else { return }
        // dentro da seleção a foto aparece sem o véu
        ctx.saveGState()
        ctx.clip(to: r)
        ctx.draw(foto, in: bounds)
        ctx.restoreGState()
        ctx.setStrokeColor(NSColor.white.cgColor)
        ctx.setLineWidth(1)
        ctx.stroke(r.insetBy(dx: 0.5, dy: 0.5))
        let medida = "\(Int(r.width)) × \(Int(r.height))" as NSString
        medida.draw(at: NSPoint(x: r.maxX + 6, y: r.minY - 18),
                    withAttributes: [.font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium),
                                     .foregroundColor: NSColor.white])
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeKey()
        inicio = convert(event.locationInWindow, from: nil)
    }

    override func mouseDragged(with event: NSEvent) {
        guard let inicio else { return }
        let p = convert(event.locationInWindow, from: nil)
        atual = NSRect(x: min(inicio.x, p.x), y: min(inicio.y, p.y),
                       width: abs(p.x - inicio.x), height: abs(p.y - inicio.y))
            .intersection(bounds)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) { fim(atual) }
    override func rightMouseDown(with event: NSEvent) { fim(nil) }
    override func cancelOperation(_ sender: Any?) { fim(nil) }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { fim(nil) } else { super.keyDown(with: event) }
    }
}
```

- [ ] **Step 2: Gerar projeto e compilar**

Run: `xcodegen generate && xcodebuild -project Knobler.xcodeproj -scheme Knobler -configuration Debug build`
Expected: BUILD SUCCEEDED.

- [ ] **Step 3: Commit**

```bash
git add Knobler/SelecaoDeTela.swift
git commit -m "feat(texto-da-tela): camada de seleção sobre a tela congelada"
```

---

### Task 6: Serviço, atalho e ligação no app

**Files:**
- Create: `Knobler/TextoDaTelaServico.swift`
- Modify: `Knobler/KnoblerApp.swift` (efeitos junto do `plugins.espelhoEfeitos` ~:575; menu Ferramentas :1487; propriedade `textoDaTela`)

**Interfaces:**
- Consumes: `TextoDaTela.*` (Task 1), `Permission.gravacaoTela` (Task 2), `KeyboardShortcuts.removeHandlers(for:)` (Task 3), `TextoDaTelaEfeitos` (Task 4), `SelecaoDeTela` (Task 5).
- Produces:
  - `final class TextoDaTelaServico: PluginServico`
  - `init(avisar: @escaping (NotchNotification) -> Void)`
  - `func acionar()`
  - `static let atalho: KeyboardShortcuts.Name` — `"textoDaTela"`, padrão ⌃⇧T.

- [ ] **Step 1: Implementar o serviço**

```swift
//
//  TextoDaTelaServico.swift
//  Knobler
//
//  O coordenador do Texto da tela: permissão, foto de cada monitor, camada de
//  seleção, OCR, clipboard e aviso no notch. É o PluginServico da peça —
//  nascer registra o ⌃⇧T, parar() o remove.
//

import AppKit
import Carbon.HIToolbox
import ScreenCaptureKit
import os

private let log = Logger(subsystem: "com.zoi.knobler", category: "TextoDaTela")

final class TextoDaTelaServico: PluginServico {
    static let atalho = KeyboardShortcuts.Name(
        "textoDaTela",
        default: .init(carbonKeyCode: kVK_ANSI_T, carbonModifiers: controlKey | shiftKey))

    private let avisar: (NotchNotification) -> Void
    private var selecao: SelecaoDeTela?
    private var ocupado = false

    init(avisar: @escaping (NotchNotification) -> Void) {
        self.avisar = avisar
        KeyboardShortcuts.enable(Self.atalho)
        KeyboardShortcuts.onKeyDown(for: Self.atalho) { [weak self] in self?.acionar() }
    }

    func parar() {
        KeyboardShortcuts.removeHandlers(for: Self.atalho)
        selecao?.cancelar()
    }

    /// Atalho, ícone do notch ou menu. Segundo toque com a seleção aberta é ignorado.
    func acionar() {
        guard !ocupado else { return }
        guard CGPreflightScreenCaptureAccess() else {
            // primeiro pedido mostra o balão; depois de negado, só os Ajustes resolvem
            if Permission.gravacaoTela.canRequest {
                Permission.gravacaoTela.request {}
            } else {
                NSWorkspace.shared.open(Permission.gravacaoTela.settingsURL)
            }
            return
        }
        ocupado = true
        Task { @MainActor in
            do {
                let fotos = try await Self.fotografar()
                let camada = SelecaoDeTela(fotos: fotos) { [weak self] resultado in
                    self?.selecao = nil
                    guard let self else { return }
                    guard let escolha = resultado,
                          let foto = fotos.first(where: { $0.tela == escolha.0 })?.foto else {
                        self.ocupado = false
                        return
                    }
                    self.ler(foto: foto, tela: escolha.0, rect: escolha.1)
                }
                selecao = camada
                camada.mostrar()
            } catch {
                log.error("captura falhou: \(error.localizedDescription, privacy: .public)")
                falhou()
            }
        }
    }

    private func ler(foto: CGImage, tela: NSScreen, rect: CGRect) {
        let escala = CGFloat(foto.width) / tela.frame.width
        let pixels = TextoDaTela.recortePixels(selecao: rect, tela: tela.frame, escala: escala)
        guard let recorte = foto.cropping(to: pixels) else { return falhou() }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let resultado = Result { try TextoDaTela.linhas(em: recorte) }
            DispatchQueue.main.async {
                guard let self else { return }
                self.ocupado = false
                switch resultado {
                case .failure(let error):
                    log.error("OCR falhou: \(error.localizedDescription, privacy: .public)")
                    self.falhou()
                case .success(let linhas) where linhas.isEmpty:
                    self.avisar(NotchNotification(appName: "Knobler", title: "Nenhum texto encontrado", body: ""))
                case .success(let linhas):
                    let texto = linhas.joined(separator: "\n")
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(texto, forType: .string)
                    self.avisar(NotchNotification(appName: "Knobler", title: "Texto copiado",
                                                  body: TextoDaTela.resumo(texto)))
                }
            }
        }
    }

    private func falhou() {
        ocupado = false
        avisar(NotchNotification(appName: "Knobler", title: "Não consegui ler a tela", body: ""))
    }

    /// Uma foto por monitor, na resolução nativa, sem o cursor.
    @MainActor
    private static func fotografar() async throws -> [(tela: NSScreen, foto: CGImage)] {
        let conteudo = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        var fotos: [(tela: NSScreen, foto: CGImage)] = []
        for tela in NSScreen.screens {
            let id = tela.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
            guard let display = conteudo.displays.first(where: { $0.displayID == id }) else { continue }
            let filtro = SCContentFilter(display: display, excludingWindows: [])
            let config = SCStreamConfiguration()
            config.width = Int(tela.frame.width * tela.backingScaleFactor)
            config.height = Int(tela.frame.height * tela.backingScaleFactor)
            config.showsCursor = false
            let foto = try await SCScreenshotManager.captureImage(contentFilter: filtro, configuration: config)
            fotos.append((tela, foto))
        }
        return fotos
    }
}
```

Antes de compilar, confirme no DocumentationSearch do MCP `xcode` (ou nos headers do SDK) as assinaturas async de `SCShareableContent.excludingDesktopWindows(_:onScreenWindowsOnly:)` e `SCScreenshotManager.captureImage(contentFilter:configuration:)`.

- [ ] **Step 2: Ligar no AppDelegate** — propriedade na classe:

```swift
    /// Texto da tela (peça). `nil` com a peça desinstalada.
    private weak var textoDaTela: TextoDaTelaServico?
```

Junto do `plugins.espelhoEfeitos = …`:

```swift
        // Texto da tela: o serviço inteiro nasce aqui; o aviso vai pra todas as
        // telas, igual ao conta-gotas (notificação construída uma vez, fora do laço).
        plugins.textoDaTelaEfeitos = TextoDaTelaEfeitos(nascer: { [weak self] in
            let servico = TextoDaTelaServico { aviso in
                self?.notches.values.forEach { $0.viewModel.enqueue(aviso) }
            }
            self?.textoDaTela = servico
            return servico
        })
```

Menu Ferramentas, logo após "Selecionar cor…":

```swift
        if textoDaTela != nil {
            addItem(menu, "Extrair texto da tela…", "text.viewfinder", #selector(extrairTexto))
        }
```

E o seletor, junto de `pickColor()`:

```swift
    @objc private func extrairTexto() { textoDaTela?.acionar() }
```

- [ ] **Step 3: Compilar** — `xcodegen generate && xcodebuild -project Knobler.xcodeproj -scheme Knobler -configuration Debug build` → BUILD SUCCEEDED; `./tools/check.sh` verde.

- [ ] **Step 4: Commit**

```bash
git add Knobler/TextoDaTelaServico.swift Knobler/KnoblerApp.swift
git commit -m "feat(texto-da-tela): serviço, atalho ⌃⇧T e item no menu Ferramentas"
```

---

### Task 7: Ícone no notch e gravador do atalho nos Ajustes

**Files:**
- Modify: `Knobler/NotchViewModel.swift:~725` (closure + flag)
- Modify: `Knobler/NotchView.swift:895-915` (`sectionStrip`)
- Modify: `Knobler/KnoblerApp.swift:~1231` (ligar a closure por vm) e o `nascer`/`parar` da Task 6
- Modify: `Knobler/SettingsView.swift:173` (`GeneralSettingsPane`)
- Modify: `Knobler/MonitoresView.swift:217` (tornar o `MonitorShortcutRecorder` reutilizável: renomear para `ShortcutRecorder` e tirar o `private`)

**Interfaces:**
- Produces: `NotchViewModel.textoDaTelaLigado: Bool` (`@Published`), `NotchViewModel.onExtrairTexto: (() -> Void)?`

- [ ] **Step 1: ViewModel** — junto de `onPomodoroSettings`:

```swift
    /// Texto da tela: o ícone na faixa só existe com a peça ligada.
    @Published var textoDaTelaLigado = false
    var onExtrairTexto: (() -> Void)?
```

- [ ] **Step 2: Ícone na faixa** — no `sectionStrip`, depois do `ForEach`:

```swift
            if vm.textoDaTelaLigado {
                Divider().frame(height: 10).overlay(.white.opacity(0.2))
                Button {
                    vm.setExpandedDirect(false)
                    vm.onExtrairTexto?()
                } label: {
                    Image(systemName: "text.viewfinder")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.35))
                        .padding(4)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Extrair texto da tela")
            }
```

Confirme o nome do método que recolhe o card (`setExpandedDirect(false)` é o usado em `KnoblerApp.swift:1570`).

- [ ] **Step 3: Ligar por tela** — em `KnoblerApp.swift`, junto de `viewModel.onPomodoroPause`:

```swift
                viewModel.onExtrairTexto = { [weak self] in self?.textoDaTela?.acionar() }
                viewModel.textoDaTelaLigado = self.textoDaTela != nil
```

E no `nascer` da Task 6, depois de `self?.textoDaTela = servico`:

```swift
            self?.notches.values.forEach { $0.viewModel.textoDaTelaLigado = true }
```

Para desligar, o `TextoDaTelaServico` ganha um `var aoParar: (() -> Void)?` chamado no fim de `parar()`, e o `nascer` define:

```swift
            servico.aoParar = { self?.notches.values.forEach { $0.viewModel.textoDaTelaLigado = false } }
```

- [ ] **Step 4: Gravador nos Ajustes** — em `MonitoresView.swift` renomeie `private struct MonitorShortcutRecorder` para `struct ShortcutRecorder` (e o uso). Em `GeneralSettingsPane`, numa seção nova:

```swift
            if host.estaInstalado(.textoDaTela) {
                Section("Texto da tela") {
                    LabeledContent("Atalho") {
                        ShortcutRecorder(name: TextoDaTelaServico.atalho)
                            .frame(width: 140)
                    }
                }
            }
```

(se `GeneralSettingsPane` não tiver `host`, acrescente `@ObservedObject private var host = PluginHost.shared`, como em `SettingsView.swift:262`).

- [ ] **Step 5: Snapshot e build**

Run: `./tools/snapshot.sh` — nenhum PNG muda (a flag nasce `false` no harness), exceto os quatro não determinísticos já conhecidos. Se `NotchView` passou a exigir arquivo novo, acrescente em `tools/notchview-fontes.txt` — não deveria: o ícone usa só a closure e a flag.
Run: `xcodebuild -project Knobler.xcodeproj -scheme Knobler -configuration Debug build` → BUILD SUCCEEDED; `./tools/check.sh` verde.

- [ ] **Step 6: Commit**

```bash
git add Knobler/NotchViewModel.swift Knobler/NotchView.swift Knobler/KnoblerApp.swift Knobler/SettingsView.swift Knobler/MonitoresView.swift Knobler/TextoDaTelaServico.swift
git commit -m "feat(texto-da-tela): ícone na faixa do notch e atalho nos Ajustes"
```

---

### Task 8: Documentação, novidade e validação ao vivo

**Files:**
- Create: `docs/texto-da-tela.md`
- Create: `Knobler/Novidades/0.34.0.html` (mesmo formato de `Knobler/Novidades/0.33.0.html`)
- Modify: `Knobler/NovidadesCatalogo.swift:20` (acrescentar `"0.34.0"`)
- Modify: `CHANGELOG.md` (`## [Unreleased]` → `### Added`)
- Modify: `docs/plugins.md` (peça nova na lista)

- [ ] **Step 1: Doc do recurso** — `docs/texto-da-tela.md`: o que faz, como acionar (⌃⇧T, ícone na faixa, menu Ferramentas), que a tela congela no acionamento, que a seleção fica presa ao monitor onde começou, permissão de Gravação de tela (concessão só vale após "Sair e Reabrir"), **limitação:** no macOS 15+ o sistema pode pedir reconfirmação periódica da permissão e não há como evitar sem entitlement da Apple; referência de mecanismo: Vorssaint, só leitura (GPL-3.0).

- [ ] **Step 2: CHANGELOG** — em `## [Unreleased]`:

```markdown
### Added
- Texto da tela (peça): ⌃⇧T congela a tela, você seleciona uma área e o texto dela vai pro clipboard.
```

- [ ] **Step 3: Novidade** — copie a estrutura de `Knobler/Novidades/0.33.0.html`, texto sobre o Texto da tela; acrescente `"0.34.0"` ao fim de `NovidadesCatalogo.versoes`. Rode `./tools/check.sh` (o check de novidades valida o catálogo).

- [ ] **Step 4: Validação ao vivo** (app instalado em `/Applications`, assinado `Knobler Local Signing`):
  1. `tccutil reset ScreenCapture com.zoi.knobler`, abrir o app, instalar a peça na vitrine.
  2. ⌃⇧T: aparece o balão do sistema; conceder; aceitar "Sair e Reabrir".
  3. ⌃⇧T: tela congela em todos os monitores, mira, medida aparece; selecionar texto de um PDF/imagem → "Texto copiado", `pbpaste` mostra o texto.
  4. Esc e clique direito cancelam sem aviso; clique sem arrasto cancela.
  5. Selecionar área sem texto → "Nenhum texto encontrado", clipboard intacto.
  6. Com dois monitores: selecionar no secundário → texto correto.
  7. Ícone na faixa do notch aciona; item do menu Ferramentas aciona.
  8. Instalar Monitores, desinstalar Monitores → ⌃⇧T segue funcionando.
  9. Desinstalar a peça → ⌃⇧T não faz nada, ícone e item de menu somem.

- [ ] **Step 5: Commit**

```bash
git add docs/texto-da-tela.md docs/plugins.md Knobler/Novidades/0.34.0.html Knobler/NovidadesCatalogo.swift CHANGELOG.md
git commit -m "docs(texto-da-tela): doc, changelog e novidades da 0.34.0"
```
