import AppKit
import Combine
import SwiftUI

@MainActor
final class AnnotationOverlayState: ObservableObject {
    let displayID: CGDirectDisplayID
    @Published var document: AnnotationDocument {
        didSet { AnnotationPersistence.save(document, displayID: displayID) }
    }
    @Published var tool: AnnotationTool = .freehand
    @Published var style = AnnotationStyle()
    @Published var draft: AnnotationElement?
    @Published var textPoint: AnnotationPoint?
    @Published var text = ""

    init(displayID: CGDirectDisplayID) {
        self.displayID = displayID
        self.document = AnnotationPersistence.load(displayID: displayID)
    }

    func begin(at point: AnnotationPoint) {
        guard tool != .eraser, tool != .text else { return }
        draft = AnnotationElement(tool: tool, points: [point], style: style)
    }

    func update(to point: AnnotationPoint) {
        guard var draft else { return }
        if tool == .freehand { draft.points.append(point) }
        else { draft.points = [draft.points[0], point] }
        self.draft = draft
    }

    func commitDraft() {
        guard let draft else { return }
        if draft.points.count > 1 {
            document.append(draft)
            if draft.tool == .laser || draft.tool == .spotlight || AppSettings.shared.annotationAutoFade {
                let id = draft.id
                let delay = AppSettings.shared.annotationFadeSeconds
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                    self?.document.remove(id)
                }
            }
        }
        self.draft = nil
    }

    func beginText(at point: AnnotationPoint) {
        textPoint = point
        text = ""
    }

    func commitText() {
        guard let textPoint, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            cancelText()
            return
        }
        document.append(AnnotationElement(
            tool: .text, points: [textPoint], text: text, style: style))
        cancelText()
    }

    func cancelText() {
        textPoint = nil
        text = ""
    }

    func erase(near point: AnnotationPoint) {
        let nearest = document.elements.min { distance($0, point) < distance($1, point) }
        guard let nearest, distance(nearest, point) < 28 else { return }
        document.remove(nearest.id)
    }

    func undo() { _ = document.undo() }
    func redo() { _ = document.redo() }
    func clear() { document.clear() }

    private func distance(_ element: AnnotationElement, _ point: AnnotationPoint) -> Double {
        element.points.map { hypot($0.x - point.x, $0.y - point.y) }.min() ?? .infinity
    }
}

private enum AnnotationPersistence {
    private static var directory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Knobler/annotations", isDirectory: true)
    }

    private static func url(_ displayID: CGDirectDisplayID) -> URL {
        directory.appendingPathComponent("display-\(displayID).json")
    }

    static func load(displayID: CGDirectDisplayID) -> AnnotationDocument {
        guard let data = try? Data(contentsOf: url(displayID)),
              let elements = try? JSONDecoder().decode([AnnotationElement].self, from: data)
        else { return AnnotationDocument() }
        return AnnotationDocument(elements: elements)
    }

    static func save(_ document: AnnotationDocument, displayID: CGDirectDisplayID) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        guard let data = try? JSONEncoder().encode(document.elements) else { return }
        try? data.write(to: url(displayID), options: .atomic)
    }
}

private final class AnnotationPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class AnnotationController: NSObject, ObservableObject {
    /// Uma instância só, como AskStore/QuickNote: a seção Anotação do card é
    /// desenhada em toda janela de notch e precisa falar com o mesmo overlay.
    static let shared = AnnotationController()

    private var panels: [CGDirectDisplayID: AnnotationPanel] = [:]
    private var states: [CGDirectDisplayID: AnnotationOverlayState] = [:]
    private var screenObserver: Any?
    private var eventTap: CFMachPort?
    private var eventSource: CFRunLoopSource?
    private var healthTimer: Timer?
    private var trustedAtCreation = false
    private var keyMonitor: Any?
    @Published private(set) var isActive = false
    var mode: AnnotationActivationMode { AppSettings.shared.annotationActivationMode }
    @Published private(set) var selectedTool = AppSettings.shared.annotationDefaultTool
    @Published private(set) var background: AnnotationBackground = AnnotationBackground(
        rawValue: UserDefaults.standard.string(forKey: "annotationBackground") ?? "") ?? .transparent
    /// Cor corrente dos botões da seção — o `style` real mora em cada state.
    @Published private(set) var selectedColor = AppSettings.shared.annotationDefaultColor
    /// Espessura corrente do traço, idem.
    @Published private(set) var lineWidth = AppSettings.shared.annotationLineWidth
    /// Tem tinta em alguma tela? O card usa isto pra abrir no deck: enquanto há
    /// desenho na tela, a anotação é o contexto — mesmo com o Control solto.
    /// ponytail: recalculado nas transições (ligar/desligar/apagar), não
    /// observado. O auto-fade pode deixá-lo `true` por um card; ninguém morre.
    @Published private(set) var temTinta = false

    func start() {
        refreshScreens()
        installScreenObserver()
        setupEventTap()
        healthTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) {
            [weak self] _ in
            Task { @MainActor in self?.checkEventTapHealth() }
        }
    }

    var diagnostics: [String: Any] {
        [
            "axTrusted": AXIsProcessTrusted(),
            "tapExists": eventTap != nil,
            "tapEnabled": eventTap.map { CGEvent.tapIsEnabled(tap: $0) } ?? false,
            "isActive": isActive,
            "tool": selectedTool.rawValue,
            "background": background.rawValue,
            "lineWidth": lineWidth,
        ]
    }

    func toggle() {
        isActive ? end() : begin()
    }

    func begin() {
        guard !isActive else { return }
        isActive = true
        refreshScreens()
        panels.values.forEach {
            $0.ignoresMouseEvents = false
            $0.orderFrontRegardless()
        }
        panels.values.first?.makeKeyAndOrderFront(nil)
        installKeyMonitor()
        atualizarTinta()
    }

    func end() {
        guard isActive else { return }
        isActive = false
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
        states.values.forEach { $0.commitDraft() }
        // soltar o Control só desliga o desenho: a tinta continua na tela até
        // o "Apagar tudo". O painel some apenas quando não sobrou nada nele.
        panels.forEach { displayID, panel in
            panel.ignoresMouseEvents = true
            if states[displayID]?.document.elements.isEmpty ?? true { panel.orderOut(nil) }
        }
        atualizarTinta()
    }

    private func atualizarTinta() {
        temTinta = states.values.contains { !$0.document.elements.isEmpty }
    }

    func state(for displayID: CGDirectDisplayID) -> AnnotationOverlayState? {
        states[displayID]
    }

    func select(tool: AnnotationTool) {
        selectedTool = tool
        states.values.forEach { $0.tool = tool }
    }

    func undo() { states.values.forEach { $0.undo() } }
    func redo() { states.values.forEach { $0.redo() } }
    func clear() {
        states.values.forEach { $0.clear() }
        if !isActive { panels.values.forEach { $0.orderOut(nil) } }
        atualizarTinta()
    }

    func setColor(_ color: NSColor) {
        guard let rgb = color.usingColorSpace(.deviceRGB) else { return }
        setColor(AnnotationColor(red: Double(rgb.redComponent),
                                 green: Double(rgb.greenComponent),
                                 blue: Double(rgb.blueComponent),
                                 alpha: Double(rgb.alphaComponent)))
    }

    func setColor(_ color: AnnotationColor) {
        selectedColor = color
        states.values.forEach { $0.style.color = color }
    }

    func setLineWidth(_ width: Double) {
        lineWidth = width
        states.values.forEach { $0.style.lineWidth = width }
    }

    func setBackground(_ background: AnnotationBackground) {
        self.background = background
        UserDefaults.standard.set(background.rawValue, forKey: "annotationBackground")
        panels.values.forEach { $0.backgroundColor = Self.nsColor(background) }
    }

    private func installKeyMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.isActive else { return event }
            if event.keyCode == 53 { self.end(); return nil } // Esc
            if event.keyCode == 6, event.modifierFlags.contains(.command) {
                if event.modifierFlags.contains(.shift) { self.redo() } else { self.undo() }
                return nil
            }
            if event.keyCode == 51 { self.clear(); return nil } // Delete
            // atalhos de ferramenta/ação, no mapa do DemoPro. Com Command a
            // tecla é do sistema (⌘Q, ⌘Z…) e não vira ferramenta.
            guard !event.modifierFlags.contains(.command),
                  let letra = event.charactersIgnoringModifiers?.lowercased().first
            else { return event }
            if let tool = AnnotationTool.allCases.first(where: { $0.key == letra }) {
                self.select(tool: tool)
                return nil
            }
            switch letra {
            case "u": self.undo()
            case "r": self.redo()
            case "x": self.clear()
            case "w": self.setBackground(self.background == .white ? .transparent : .white)
            case "k": self.setBackground(self.background == .black ? .transparent : .black)
            default: return event
            }
            return nil
        }
    }

    private func rightControlChanged(_ pressed: Bool) {
        switch mode {
        case .pressAndHold:
            pressed ? begin() : end()
        case .toggle:
            if pressed { toggle() }
        }
    }

    private func setupEventTap() {
        guard eventTap == nil else { return }
        trustedAtCreation = AXIsProcessTrusted()
        let flagsMask = CGEventMask(1 << CGEventType.flagsChanged.rawValue)
        let refcon = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        eventTap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: flagsMask,
            callback: { _, _, event, refcon in
                guard let refcon else { return Unmanaged.passRetained(event) }
                let controller = Unmanaged<AnnotationController>
                    .fromOpaque(refcon).takeUnretainedValue()
                if event.type == .tapDisabledByTimeout || event.type == .tapDisabledByUserInput {
                    DispatchQueue.main.async { controller.enableEventTap() }
                    return Unmanaged.passRetained(event)
                }
                if event.getIntegerValueField(.keyboardEventKeycode) == AnnotationShortcut.defaultKeyCode {
                    // o keycode já identifica a tecla; a flag só diz se desceu ou subiu.
                    let pressed = event.flags.contains(.maskControl)
                    DispatchQueue.main.async { controller.rightControlChanged(pressed) }
                }
                return Unmanaged.passRetained(event)
            },
            userInfo: refcon)
        guard let eventTap else {
            NSLog("knobler: annotation CGEventTap indisponível (Acessibilidade?)")
            return
        }
        eventSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
        if let eventSource { CFRunLoopAddSource(CFRunLoopGetMain(), eventSource, .commonModes) }
        CGEvent.tapEnable(tap: eventTap, enable: true)
    }

    private func enableEventTap() {
        guard let eventTap else {
            if AXIsProcessTrusted() { setupEventTap() }
            return
        }
        CGEvent.tapEnable(tap: eventTap, enable: true)
    }

    private func checkEventTapHealth() {
        let trusted = AXIsProcessTrusted()
        guard trusted else {
            if eventTap != nil { teardownEventTap() }
            return
        }
        guard let eventTap else {
            setupEventTap()
            return
        }
        if trusted != trustedAtCreation {
            teardownEventTap()
            setupEventTap()
        } else if !CGEvent.tapIsEnabled(tap: eventTap) {
            enableEventTap()
        }
    }

    private func teardownEventTap() {
        if let eventSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), eventSource, .commonModes)
        }
        eventSource = nil
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
            CFMachPortInvalidate(eventTap)
        }
        eventTap = nil
    }

    private func installScreenObserver() {
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main) { [weak self] _ in
                Task { @MainActor in self?.refreshScreens() }
            }
    }

    private func refreshScreens() {
        let current = Set(NSScreen.screens.map(Self.displayID))
        for (id, panel) in panels where !current.contains(id) {
            panel.orderOut(nil)
            panels.removeValue(forKey: id)
            states.removeValue(forKey: id)
        }
        for screen in NSScreen.screens {
            let id = Self.displayID(screen)
            let state = states[id] ?? AnnotationOverlayState(displayID: id)
            state.tool = selectedTool
            state.style.color = selectedColor
            state.style.lineWidth = lineWidth
            states[id] = state
            let panel = panels[id] ?? makePanel(state: state)
            panel.setFrame(screen.frame, display: true)
            panel.ignoresMouseEvents = !isActive
            panels[id] = panel
            if isActive { panel.orderFrontRegardless() }
        }
    }

    private func makePanel(state: AnnotationOverlayState) -> AnnotationPanel {
        let panel = AnnotationPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false)
        panel.isOpaque = false
        panel.backgroundColor = Self.nsColor(background)
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        // logo ABAIXO da NotchWindow (.mainMenu + 3): o card do notch é o painel
        // de controle da anotação e precisa continuar clicável por cima da tinta.
        panel.level = .mainMenu + 2
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.acceptsMouseMovedEvents = true
        panel.contentView = NSHostingView(rootView: AnnotationCanvasView(state: state))
        return panel
    }

    private static func nsColor(_ background: AnnotationBackground) -> NSColor {
        switch background {
        case .transparent: return .clear
        case .white: return .white
        case .black: return .black
        }
    }

    private static func displayID(_ screen: NSScreen) -> CGDirectDisplayID {
        screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID ?? 0
    }
}

struct AnnotationCanvasView: View {
    @ObservedObject var state: AnnotationOverlayState
    @FocusState private var textFocused: Bool

    var body: some View {
        ZStack(alignment: .topLeading) {
            Canvas { context, _ in
                for element in state.document.elements { draw(element, in: &context) }
                if let draft = state.draft { draw(draft, in: &context) }
            }

            AnnotationInputRepresentable(state: state)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            if let point = state.textPoint {
                TextField("Texto", text: $state.text)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 240)
                    .position(x: point.x + 120, y: point.y + 16)
                    .focused($textFocused)
                    .onSubmit { state.commitText() }
                    .onAppear { textFocused = true }
            }
        }
        .ignoresSafeArea()
    }

    private func draw(_ element: AnnotationElement, in context: inout GraphicsContext) {
        let color = Color(.sRGB, red: element.style.color.red,
                          green: element.style.color.green,
                          blue: element.style.color.blue,
                          opacity: element.style.opacity * element.style.color.alpha)
        guard let first = element.points.first else { return }
        switch element.tool {
        case .text:
            if let text = element.text {
                context.draw(Text(text).font(.system(size: element.style.lineWidth * 3, weight: .medium)),
                             at: CGPoint(x: first.x, y: first.y), anchor: .topLeading)
            }
        case .rectangle:
            guard let last = element.points.last else { return }
            context.stroke(Path(CGRect(x: min(first.x, last.x), y: min(first.y, last.y),
                                      width: abs(last.x - first.x), height: abs(last.y - first.y))),
                           with: .color(color), style: StrokeStyle(lineWidth: element.style.lineWidth))
        case .ellipse:
            guard let last = element.points.last else { return }
            context.stroke(Path(ellipseIn: CGRect(x: min(first.x, last.x), y: min(first.y, last.y),
                                                   width: abs(last.x - first.x), height: abs(last.y - first.y))),
                           with: .color(color), style: StrokeStyle(lineWidth: element.style.lineWidth))
        case .spotlight:
            let radius = max(24, element.style.lineWidth * 8)
            let circle = Path(ellipseIn: CGRect(x: first.x - radius, y: first.y - radius,
                                                width: radius * 2, height: radius * 2))
            context.fill(circle, with: .color(color.opacity(0.12)))
            context.stroke(circle, with: .color(color), style: StrokeStyle(lineWidth: element.style.lineWidth))
        default:
            var path = Path()
            path.move(to: CGPoint(x: first.x, y: first.y))
            for point in element.points.dropFirst() { path.addLine(to: CGPoint(x: point.x, y: point.y)) }
            context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: element.style.lineWidth, lineCap: .round, lineJoin: .round))
            if element.tool == .arrow, let last = element.points.last, element.points.count > 1 {
                let dx = last.x - first.x
                let dy = last.y - first.y
                let angle = atan2(dy, dx)
                let size = max(10, element.style.lineWidth * 3)
                var head = Path()
                head.move(to: CGPoint(x: last.x - cos(angle - .pi / 6) * size,
                                      y: last.y - sin(angle - .pi / 6) * size))
                head.addLine(to: CGPoint(x: last.x, y: last.y))
                head.addLine(to: CGPoint(x: last.x - cos(angle + .pi / 6) * size,
                                         y: last.y - sin(angle + .pi / 6) * size))
                context.stroke(head, with: .color(color), style: StrokeStyle(lineWidth: element.style.lineWidth))
            }
        }
    }
}

private struct AnnotationInputRepresentable: NSViewRepresentable {
    @ObservedObject var state: AnnotationOverlayState

    func makeNSView(context: Context) -> AnnotationInputView {
        AnnotationInputView(state: state)
    }

    func updateNSView(_ nsView: AnnotationInputView, context: Context) {
        nsView.state = state
    }
}

private final class AnnotationInputView: NSView {
    var state: AnnotationOverlayState
    private var drawing = false

    init(state: AnnotationOverlayState) {
        self.state = state
        super.init(frame: .zero)
        wantsLayer = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var isFlipped: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        let point = annotationPoint(for: event)
        if state.tool == .eraser {
            state.erase(near: point)
        } else if state.tool == .text {
            if state.textPoint == nil { state.beginText(at: point) }
        } else {
            drawing = true
            state.begin(at: point)
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard drawing else { return }
        state.update(to: annotationPoint(for: event))
    }

    override func mouseUp(with event: NSEvent) {
        guard drawing else { return }
        state.update(to: annotationPoint(for: event))
        state.commitDraft()
        drawing = false
    }

    private func annotationPoint(for event: NSEvent) -> AnnotationPoint {
        let point = convert(event.locationInWindow, from: nil)
        return AnnotationPoint(x: point.x, y: point.y)
    }
}
