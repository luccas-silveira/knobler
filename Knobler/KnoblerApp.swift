//
//  KnoblerApp.swift
//  Knobler — Dynamic Island para o notch do MacBook
//

import AppKit
import Combine
import SwiftUI

@main
enum KnoblerMain {
    static let delegate = AppDelegate()

    static func main() {
        let app = NSApplication.shared
        app.delegate = delegate
        app.run()
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private struct ScreenNotch {
        let window: NotchWindow
        let viewModel: NotchViewModel
    }

    private var notches: [CGDirectDisplayID: ScreenNotch] = [:]
    private var statusItem: NSStatusItem?
    private let media = MediaController()
    private var interceptor: NotificationInterceptor?
    private let volumeHUD = VolumeHUDController()
    private let audioLevels = SystemAudioLevels()
    private let battery = BatteryMonitor()
    private let micMonitor = MicMonitor()
    private let apiServer = NotchAPIServer()
    private let dictation = DictationController()
    private let calendar = CalendarCountdown()
    private let shelf = ShelfStore()
    private let screenshots = ScreenshotWatcher()
    private var screenshotPeekWork: DispatchWorkItem?
    private var apiCancellable: AnyCancellable?
    private var askKeyCancellables = Set<AnyCancellable>()
    /// Evita reabrir o espelho a cada tick se o usuário fechou antes da call.
    private var mirrorAutoOpened = false

    // duas fontes de atividade: API (explícita) vence o calendário (ambiente)
    private var apiActivity: NotchActivity?
    private var calendarActivity: NotchActivity?
    private var currentActivity: NotchActivity? { apiActivity ?? calendarActivity }

    private func pushActivity() {
        let display = currentActivity
        notches.values.forEach { $0.viewModel.activity = display }
    }
    private var levelsCancellable: AnyCancellable?
    private var pausedCancellable: AnyCancellable?

    // gesto de swipe no notch (monitor local de scroll)
    private var scrollMonitor: Any?
    private var scrollAccumX: CGFloat = 0
    private var scrollAccumY: CGFloat = 0
    private var scrollActed = false

    // ilha simulada nos monitores sem notch físico
    private static let simulatedNotchSize = CGSize(width: 190, height: 30)

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusItem()
        placeWindows()

        // notificações aparecem em TODAS as telas, como os HUDs
        let interceptor = NotificationInterceptor { [weak self] notch in
            self?.notches.values.forEach { $0.viewModel.enqueue(notch) }
        }
        interceptor.start()
        self.interceptor = interceptor

        // HUDs são estado global do sistema: aparecem em TODAS as telas
        volumeHUD.onHUD = { [weak self] state in
            self?.notches.values.forEach { $0.viewModel.showHUD(state) }
        }
        volumeHUD.start()

        // ditado: pílula em TODAS as telas, como os HUDs
        dictation.onState = { [weak self] phase in
            self?.notches.values.forEach { $0.viewModel.dictation = phase }
        }
        volumeHUD.onRightOption = { [weak self] pressed in
            self?.dictation.rightOptionChanged(pressed)
        }
        dictation.start()

        // ditado durante uma pergunta alimenta o campo do card, não o app ativo
        dictation.transcriptSink = { [weak self] text in
            guard let self else { return false }
            let asking = self.notches.values.filter { $0.viewModel.ask != nil }
            guard !asking.isEmpty else { return false }
            asking.forEach {
                let vm = $0.viewModel
                vm.askText = vm.askText.isEmpty ? text : vm.askText + " " + text
            }
            return true
        }

        // capturas de tela entram na prateleira e o notch dá um peek
        screenshots.onScreenshot = { [weak self] url in
            guard let self else { return }
            self.shelf.add(url)
            self.peekShelf()
        }

        battery.onEvent = { [weak self] level, charging in
            guard AppSettings.shared.batteryAlerts else { return }
            self?.notches.values.forEach {
                $0.viewModel.showHUD(
                    .init(kind: .battery, level: level, charging: charging),
                    duration: 2.5
                )
            }
        }
        battery.start()

        // pontinho laranja enquanto algum app usa o microfone
        micMonitor.onChange = { [weak self] inUse in
            let show = inUse && AppSettings.shared.micIndicator
            self?.notches.values.forEach { $0.viewModel.micInUse = show }
        }
        micMonitor.start()

        // tap de áudio só enquanto o player ativo toca (visualizador reativo real);
        // reavaliado quando o player muda e quando o toggle muda nos Ajustes
        levelsCancellable = media.$state
            .map { _ in () }
            .merge(with: AppSettings.shared.objectWillChange.map { _ in () })
            .sink { [weak self] in
                DispatchQueue.main.async { self?.updateAudioTap() }
            }

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screensChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )

        // pausado, a música se esconde do notch (peek no hover)
        pausedCancellable = media.$state
            .map { $0 != nil && $0?.isPlaying != true }
            .removeDuplicates()
            .sink { [weak self] paused in
                self?.notches.values.forEach { $0.viewModel.musicPaused = paused }
            }

        setupSwipeGestures()

        // API local: scripts publicam cards no notch (diferencial do Knobler)
        apiServer.onNotification = { [weak self] notification in
            self?.notches.values.forEach { $0.viewModel.enqueue(notification) }
        }
        // atividade é global: aparece em todos os monitores
        apiServer.onActivity = { [weak self] activity in
            self?.apiActivity = activity
            self?.pushActivity()
        }
        calendar.onActivity = { [weak self] activity in
            self?.calendarActivity = activity
            self?.pushActivity()
        }
        // espelho automático: abre 2min antes da call, fecha quando ela começa
        calendar.onMirrorMoment = { [weak self] imminent in
            guard let self else { return }
            if imminent, AppSettings.shared.mirrorBeforeMeetings, !self.mirrorAutoOpened {
                self.mirrorAutoOpened = true
                if let vm = self.viewModelUnderMouse() {
                    MirrorController.activate(on: vm, expand: true)
                }
            } else if !imminent, self.mirrorAutoOpened {
                self.mirrorAutoOpened = false
                self.notches.values.forEach {
                    guard $0.viewModel.mirrorOn else { return }
                    $0.viewModel.mirrorOn = false
                    $0.viewModel.setExpandedDirect(false)
                }
            }
        }
        calendar.start()

        apiServer.onMirror = { [weak self] on in
            guard let self else { return }
            if on {
                if let vm = self.viewModelUnderMouse() {
                    MirrorController.activate(on: vm, expand: true)
                }
            } else {
                self.notches.values.forEach {
                    guard $0.viewModel.mirrorOn else { return }
                    $0.viewModel.mirrorOn = false
                    $0.viewModel.setExpandedDirect(false)
                }
            }
        }

        // perguntas do Claude Code: card em TODAS as telas; primeira resposta vence
        apiServer.onAsk = { [weak self] request in
            NSSound(named: "Pop")?.play()  // uma vez, na chegada — sem lembretes
            self?.notches.values.forEach { $0.viewModel.enqueueAsk(request) }
        }
        apiServer.onAskDismiss = { [weak self] id in
            self?.notches.values.forEach { $0.viewModel.clearAsk(id: id) }
        }

        apiServer.statusProvider = { [weak self] in
            var status = self?.volumeHUD.diagnostics ?? [:]
            status["visualizerTapped"] = self?.tappedBundleID ?? "none"
            status["player"] = self?.media.activeBundleID ?? "none"
            status.merge(MirrorController.shared.diagnostics) { _, new in new }
            status["micInUse"] = self?.micMonitor.isRunning ?? false
            status["notches"] = (self?.notches ?? [:]).map { id, notch in
                [
                    "display": Int(id),
                    "mode": "\(notch.viewModel.mode)",
                    "hasNotification": notch.viewModel.activeNotification != nil,
                    "visible": notch.window.isVisible,
                    "frame": "\(notch.window.frame)",
                ] as [String: Any]
            }
            status["dictation"] = self?.dictation.diagnostics ?? [:]
            status["ask"] = self?.apiServer.askDiagnostics ?? [:]
            return status
        }
        apiCancellable = AppSettings.shared.objectWillChange
            .prepend(())
            .sink { [weak self] in
                DispatchQueue.main.async {
                    if AppSettings.shared.localAPI {
                        self?.apiServer.start()
                    } else {
                        self?.apiServer.stop()
                    }
                    if AppSettings.shared.screenshotsToShelf {
                        self?.screenshots.start()
                    } else {
                        self?.screenshots.stop()
                    }
                    // indicador de mic é persistente: re-publica quando o toggle muda
                    self?.micMonitor.publish()
                    // OSD nativo suprimido enquanto algum HUD nosso estiver ativo
                    let hudsOn = AppSettings.shared.volumeHUD || AppSettings.shared.brightnessHUD
                    // preview do print some só se o shelf captura E o toggle está on
                    let hidePreview = AppSettings.shared.screenshotsToShelf
                        && AppSettings.shared.hideScreenshotPreview
                    DispatchQueue.global(qos: .utility).async {
                        hudsOn ? OSDSuppressor.suppress() : OSDSuppressor.restore()
                        hidePreview ? ScreenshotPreviewSuppressor.suppress()
                                    : ScreenshotPreviewSuppressor.restore()
                    }
                }
            }
    }

    /// Liga/desliga o tap conforme o estado atual — idempotente, barato.
    private var tappedBundleID: String?
    private func updateAudioTap() {
        let wanted: String? = (AppSettings.shared.liveAudioVisualizer
            && media.state?.isPlaying == true) ? media.activeBundleID : nil
        guard wanted != tappedBundleID else { return }
        tappedBundleID = wanted
        audioLevels.stop()
        if let wanted,
           let app = NSRunningApplication.runningApplications(
               withBundleIdentifier: wanted).first {
            audioLevels.start(pid: app.processIdentifier)
        }
    }

    // MARK: - Swipe no notch

    /// Dois dedos sobre o notch: pra baixo abre a música, pra cima fecha,
    /// horizontal pula/volta faixa (como o Dynamic Island).
    private func setupSwipeGestures() {
        scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) {
            [weak self] event in
            self?.handleScroll(event) ?? event
        }
        // drag das miniaturas do shelf via monitor (o hit-testing do SwiftUI
        // engole eventos de mouse nas NSViews embutidas do notch)
        ShelfDragMonitor.shared.start()
    }

    private func handleScroll(_ event: NSEvent) -> NSEvent? {
        let mouse = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) }),
              let vm = notches[Self.displayID(of: screen)]?.viewModel
        else { return event }

        // zona do gesto: o notch fechado (ou o card aberto, se expandido)
        let expanded = vm.mode == .music
        let zoneWidth: CGFloat = expanded ? 460 : 400
        let zoneHeight: CGFloat = expanded ? 200 : vm.notchSize.height + 10
        let inZone = abs(mouse.x - screen.frame.midX) <= zoneWidth / 2
            && mouse.y >= screen.frame.maxY - zoneHeight
        guard inZone else { return event }

        // inércia não conta como gesto; ainda assim é engolida na zona
        guard event.momentumPhase.isEmpty else { return nil }

        if event.phase == .began {
            scrollAccumX = 0
            scrollAccumY = 0
            scrollActed = false
        }
        scrollAccumX += event.scrollingDeltaX
        scrollAccumY += event.scrollingDeltaY

        if !scrollActed {
            if abs(scrollAccumY) > 24, abs(scrollAccumY) > abs(scrollAccumX) * 1.5 {
                scrollActed = true
                // natural scrolling: dedos pra baixo → deltaY positivo
                vm.setExpandedDirect(scrollAccumY > 0)
            } else if abs(scrollAccumX) > 50, media.state != nil {
                scrollActed = true
                if scrollAccumX < 0 { media.nextTrack() } else { media.previousTrack() }
            }
        }
        return nil // engole o scroll na zona — a janela de trás não rola junto
    }

    @objc private func screensChanged() {
        placeWindows()
    }

    /// Expande o card mostrando a prateleira por 1,5s e fecha. Pergunta ou
    /// ditado na tela têm prioridade → só adiciona, sem peek. Nova captura
    /// renova o timer; mouse em cima segura: o fechamento pula quem está sob o cursor.
    private func peekShelf() {
        let busy = notches.values.contains {
            $0.viewModel.ask != nil || $0.viewModel.dictation != nil
        }
        guard !busy else { return }

        notches.values.forEach { $0.viewModel.setExpandedDirect(true) }
        screenshotPeekWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            // não fecha o que o usuário está usando: mouse sobre o notch mantém
            // aberto; o hover-exit fecha depois, pela via normal do setHover
            self?.notches.values.forEach {
                guard !$0.viewModel.isHovering else { return }
                $0.viewModel.setExpandedDirect(false)
            }
        }
        screenshotPeekWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: work)
    }

    /// Notificações e HUD vão pro monitor onde o mouse está (onde está a atenção).
    private func viewModelUnderMouse() -> NotchViewModel? {
        let mouse = NSEvent.mouseLocation
        let target = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) }
            ?? NSScreen.main
        return target.flatMap { notches[Self.displayID(of: $0)]?.viewModel }
            ?? notches.values.first?.viewModel
    }

    // ponytail: janela sempre no tamanho expandido máximo; o SwiftUI desenha só o
    // necessário. Redimensionar NSWindow durante animação é fonte de jank.
    private func placeWindows() {
        var seen = Set<CGDirectDisplayID>()

        for screen in NSScreen.screens {
            let id = Self.displayID(of: screen)
            seen.insert(id)

            let notch: ScreenNotch
            if let existing = notches[id] {
                notch = existing
            } else {
                let viewModel = NotchViewModel()
                let panel = NotchWindow(
                    contentRect: .zero,
                    styleMask: [.borderless, .nonactivatingPanel],
                    backing: .buffered,
                    defer: false
                )
                panel.contentView = NSHostingView(
                    rootView: NotchView(
                        vm: viewModel, media: media, levels: audioLevels, shelf: shelf))
                notch = ScreenNotch(window: panel, viewModel: viewModel)
                notches[id] = notch

                // resposta/cancelamento de QUALQUER monitor volta pro servidor
                // e limpa os demais (primeira resposta vence)
                viewModel.onAskAnswered = { [weak self] id, answers in
                    self?.apiServer.resolveAsk(id: id, answers: answers)
                    self?.notches.values.forEach { $0.viewModel.clearAsk(id: id) }
                }
                viewModel.onAskCancelled = { [weak self] id in
                    self?.apiServer.cancelAsk(id: id)
                    self?.notches.values.forEach { $0.viewModel.clearAsk(id: id) }
                }
                // janela só aceita teclado enquanto o card existe — CRÍTICO
                // reverter, senão o notch rouba foco pra sempre
                viewModel.$ask
                    .map { $0 != nil }
                    .removeDuplicates()
                    .sink { [weak panel] active in
                        panel?.allowsKeyboard = active
                        if !active, panel?.isKeyWindow == true { panel?.resignKey() }
                    }
                    .store(in: &askKeyCancellables)
            }

            notch.viewModel.notchSize = Self.notchSize(of: screen)
            notch.viewModel.hasRealNotch = screen.safeAreaInsets.top > 0
            notch.viewModel.musicPaused =
                media.state != nil && media.state?.isPlaying != true
            notch.viewModel.activity = currentActivity

            // altura comporta o card com espelho; área transparente não intercepta cliques
            let size = NSSize(width: 700, height: 520)
            let frame = NSRect(
                x: screen.frame.midX - size.width / 2,
                y: screen.frame.maxY - size.height,
                width: size.width,
                height: size.height
            )
            notch.window.setFrame(frame, display: true)
            notch.window.orderFrontRegardless()
        }

        // remove janelas de monitores desconectados
        for (id, notch) in notches where !seen.contains(id) {
            notch.window.orderOut(nil)
            notches.removeValue(forKey: id)
        }
    }

    private static func displayID(of screen: NSScreen) -> CGDirectDisplayID {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        return screen.deviceDescription[key] as? CGDirectDisplayID ?? 0
    }

    private static func notchSize(of screen: NSScreen) -> CGSize {
        let height = screen.safeAreaInsets.top
        guard height > 0 else { return simulatedNotchSize }
        if let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea {
            return CGSize(width: right.minX - left.maxX, height: height)
        }
        return CGSize(width: 200, height: max(height, 32))
    }

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.title = "◐"
        let menu = NSMenu()
        let settings = menu.addItem(
            withTitle: "Ajustes…", action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Knobler", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.menu = menu
        statusItem = item
    }

    func applicationWillTerminate(_ notification: Notification) {
        // devolve o OSD nativo — sem o Knobler o usuário fica sem HUD nenhum
        OSDSuppressor.restore()
        // devolve o preview do print (senão ficaria sem preview E sem shelf)
        ScreenshotPreviewSuppressor.restore()
    }

    private var settingsWindow: NSWindow?

    @objc private func openSettings() {
        if settingsWindow == nil {
            let window = NSWindow(
                contentRect: .zero,
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            window.title = "Ajustes do Knobler"
            window.contentView = NSHostingView(rootView: SettingsView())
            window.isReleasedWhenClosed = false
            window.setContentSize(window.contentView!.fittingSize)
            window.center()
            settingsWindow = window
        }
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
