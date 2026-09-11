// Janela real e captura do compositor; somente dados sintéticos, sem instalar o app.
import AppKit
import ScreenCaptureKit
import SwiftUI

@MainActor
enum KnoblerMain {
    struct Delegate {
        func viewModelPrincipal() -> NotchViewModel? { nil }
        func ligarDesligarNota(em screen: NSScreen?) {}
    }
    static let delegate = Delegate()
}

@main
@MainActor
enum PresentationWindowCheck {
    static func wait(_ seconds: Double) {
        RunLoop.main.run(until: Date().addingTimeInterval(seconds))
    }

    static func capture(_ window: NSWindow, to url: URL) -> NSBitmapImageRep {
        var finished = false
        var result: NSBitmapImageRep?
        var failure: Error?
        let windowID = CGWindowID(window.windowNumber)
        let width = Int(window.frame.width * 2)
        let height = Int(window.frame.height * 2)
        SCShareableContent.getExcludingDesktopWindows(true, onScreenWindowsOnly: true) { content, error in
            guard let match = content?.windows.first(where: { $0.windowID == windowID }) else {
                RunLoop.main.perform { failure = error; finished = true }
                return
            }
            let config = SCStreamConfiguration()
            config.width = width
            config.height = height
            config.showsCursor = false
            SCScreenshotManager.captureImage(contentFilter: SCContentFilter(desktopIndependentWindow: match),
                                              configuration: config) { image, error in
                RunLoop.main.perform {
                    if let image { result = NSBitmapImageRep(cgImage: image) }
                    failure = error
                    finished = true
                }
            }
        }
        let deadline = Date().addingTimeInterval(15)
        while !finished && Date() < deadline { wait(0.01) }
        guard let result else { fatalError("Captura do compositor falhou: \(String(describing: failure))") }
        try! result.representation(using: .png, properties: [:])!.write(to: url)
        return result
    }

    static func main() {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.accessory)
        DispatchQueue.main.async {
            runChecks()
            exit(0)
        }
        NSApp.run()
    }

    static func runChecks() {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("knobler-presentation-\(UUID().uuidString)")
        try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        print("Artefatos: \(dir.path)")
        QuickNote.shared.pasteboard = NSPasteboard(name: .init("knobler.presentationcheck"))
        NotificationHistory.shared.arquivo = nil
        NotificationHistory.shared.limpar()
        let screen = NSScreen.screens.first!
        var records: [[String: Any]] = []
        for real in [true, false] {
            for delay in [0.05, 0.12, 0.24] {
                for kind in 0..<3 {
                    QuickNote.shared.active = false
                    let vm = NotchViewModel()
                    vm.displayID = 1
                    vm.hasRealNotch = real
                    vm.notchSize = CGSize(width: 200, height: real ? 32 : 30)
                    let frame = NotchPresentation.hostFrame(screen: screen.frame, visible: screen.visibleFrame)
                    vm.availableSize = frame.size
                    let panel = NotchWindow(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel],
                                            backing: .buffered, defer: false)
                    let ask = AskStore(dependencies: .init(resolve: { _, _ in }, cancel: { _ in }))
                    let agents = AgentRequestStore()
                    vm.questionIsActive = { ask.state.active != nil || agents.state.active != nil }
                    let media = MediaController()
                    media.injectPreview(state: nil, artwork: nil)
                    let suite = "presentationcheck.\(UUID().uuidString)"
                    let defaults = UserDefaults(suiteName: suite)!
                    defer { defaults.removePersistentDomain(forName: suite) }
                    let shelf = ShelfStore(defaults: defaults)
                    let host = NotchHostingView(rootView:
                        NotchView(vm: vm, askStore: ask, agentRequestStore: agents,
                            media: media, levels: SystemAudioLevels(), shelf: shelf,
                            onKeyboardEligibilityChanged: { [weak panel] allowed in
                                panel?.allowsKeyboard = allowed
                                // O harness simula o clique ao reapresentar um editor.
                                if allowed { panel?.makeKey() }
                                if !allowed, panel?.isKeyWindow == true { panel?.resignKey() }
                            })
                            .environmentObject(LANMessaging())
                            .environmentObject(MessageStore(carregando: false))
                            .environmentObject(AppSettings.shared))
                    panel.contentView = host
                    panel.orderFrontRegardless()
                    wait(0.25)
                    QuickNote.shared.adotar(1)
                    QuickNote.shared.text = "Rascunho sintético preservado"
                    vm.setExpandedDirect(true)
                    vm.secoes = [.nota, .historico, .shelf, .musica]
                    vm.focar(.nota)
                    wait(0.6)
                    panel.makeKey()
                    wait(0.1)
                    let name = "\(real ? "notch" : "externo")-\(kind)-\(delay)"
                    let initialHost = ObjectIdentifier(host)
                    let start = ProcessInfo.processInfo.systemUptime
                    for step in 0..<4 {
                        DispatchQueue.main.asyncAfter(deadline: .now() + delay * Double(step)) {
                            switch kind {
                            case 0: vm.setExpandedDirect(step % 2 == 1)
                            case 1: vm.focar(step % 2 == 0 ? .historico : .nota)
                            default: vm.dictation = step % 2 == 0 ? .transcribing : nil
                            }
                            if step == 3 {
                                vm.setExpandedDirect(true)
                                vm.secoes = [.nota, .historico, .shelf, .musica]
                                vm.focar(.nota)
                            }
                        }
                    }
                    wait(delay / 2)
                    _ = capture(panel, to: dir.appendingPathComponent(name + "-transicao.png"))
                    // Mede sem cacheDisplay: redesenhar na CPU alterava a cadência das ações.
                    while ProcessInfo.processInfo.systemUptime - start < delay * 3 + 0.8 {
                        wait(0.016)
                        assert(abs(host.topDisplacement) < 2, "host deslocado durante \(name)")
                    }
                    assert(ObjectIdentifier(panel.contentView!) == initialHost)
                    assert(vm.expanded && vm.mode == .music && vm.focus == .nota)
                    assert(panel.allowsKeyboard && QuickNote.shared.text == "Rascunho sintético preservado")
                    // Equivale à retomada pelo clique no painel não ativante.
                    panel.makeKey()
                    wait(0.1)
                    assert(panel.isKeyWindow && panel.firstResponder is NSTextView,
                           "editor sem foco: \(name), key=\(panel.isKeyWindow), allowed=\(panel.allowsKeyboard), expanded=\(vm.expanded), mode=\(vm.mode), responder=\(String(describing: panel.firstResponder))")
                    let bitmap = capture(panel, to: dir.appendingPathComponent(name + ".png"))
                    // Centro da moldura: alpha separa o corpo preto da sombra e da transparência.
                    var black: [Int] = []
                    for y in 0..<bitmap.pixelsHigh {
                        guard let c = bitmap.colorAt(x: bitmap.pixelsWide / 2, y: y)?.usingColorSpace(.deviceRGB) else { continue }
                        if c.alphaComponent > 0.98 && max(c.redComponent, c.greenComponent, c.blueComponent) < 0.08 {
                            black.append(y)
                        }
                    }
                    let scale = Double(bitmap.pixelsHigh) / panel.frame.height
                    let top = Double(black.first ?? -100) / scale
                    let bottom = Double((black.last ?? -100) + 1) / scale
                    assert(abs(top) < 3, "topo visual deslocado: \(name), \(top)")
                    assert(abs(bottom - vm.alturaAtual) < 4, "moldura visual diverge: \(name), \(bottom) vs \(vm.alturaAtual)")
                    records.append(["cenario": name, "topo": top, "fim": bottom,
                                    "altura": vm.alturaAtual, "host": host.topDisplacement,
                                    "key": panel.isKeyWindow, "editor": String(describing: type(of: panel.firstResponder!))])
                    // Ocultar cancela pedidos atrasados; reexibir conserva a mesma árvore.
                    vm.setExpandedDirect(false)
                    vm.setHover(true)
                    vm.suspendPresentation()
                    panel.orderOut(nil)
                    wait(0.25)
                    assert(!vm.expanded)
                    panel.orderFrontRegardless()
                    wait(0.1)
                    assert(ObjectIdentifier(panel.contentView!) == initialHost)
                    // Reposicionamento com coordenadas da segunda tela quando disponível.
                    if let other = NSScreen.screens.dropFirst().first {
                        let moved = NotchPresentation.hostFrame(screen: other.frame, visible: other.visibleFrame)
                        vm.availableSize = moved.size
                        panel.setFrame(moved, display: true)
                        wait(0.1)
                        assert(abs(host.topDisplacement) < 2)
                    }
                    panel.orderOut(nil)
                    panel.contentView = nil
                    print("ok \(name)")
                }
            }
        }
        // A moldura de 780 pt deve caber no host inclusive com Reduzir Movimento.
        for reduced in [false, true] {
            var layout = NotchPresentation.Layout()
            let frame = NotchPresentation.hostFrame(screen: screen.frame, visible: screen.visibleFrame)
            layout.available = frame.size
            layout.sectionWidth = NotchMetrics.linkCardWidth
            layout.sectionHeight = 438
            let presentation = NotchPresentation(content: .init(expanded: true, focus: .link), layout: layout)
            let panel = NotchWindow(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel],
                                    backing: .buffered, defer: false)
            panel.contentView = NotchHostingView(rootView: VStack(spacing: 0) {
                NotchShell(presentation: presentation, reduceMotion: reduced) {
                    Text("Conteúdo sintético de 736 pt")
                        .frame(width: 736, height: 100)
                        .background(.white)
                        .padding(.top, 40)
                }
                Spacer(minLength: 0)
            }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top))
            panel.orderFrontRegardless()
            wait(0.3)
            let bitmap = capture(panel, to: dir.appendingPathComponent("largo-\(reduced).png"))
            let scale = Double(bitmap.pixelsWide) / frame.width
            let y = Int(60 * scale)
            let white = (0..<bitmap.pixelsWide).filter { x in
                guard let c = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { return false }
                return c.alphaComponent > 0.98 && min(c.redComponent, c.greenComponent, c.blueComponent) > 0.95
            }
            assert(abs(Double(white.count) / scale - 736) < 2, "conteúdo largo cortado")
            panel.orderOut(nil)
        }
        QuickNote.shared.active = false
        try! JSONSerialization.data(withJSONObject: records, options: [.prettyPrinted, .sortedKeys])
            .write(to: dir.appendingPathComponent("geometry.json"))
        print("presentation-windowcheck: \(records.count) cenários ok")
    }
}
