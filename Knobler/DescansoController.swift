//
//  DescansoController.swift
//  Knobler
//
//  Controlador do bloqueio forçado ("Descanso"): monta uma janela de shield por
//  tela (nível CGShieldingWindowLevel, acima de tudo — inclusive do notch), liga o
//  modo quiosque nativo enquanto ativo e captura o teclado pro escape (segurar Esc
//  5s). O contador é sleep-proof (ancorado num endDate). AppKit — fica fora do
//  arquivo de modelo (só-Foundation) e do harness de snapshot.
//
//  Teto honesto (ver SPEC-descanso.md / Achados): bloqueia Force Quit, Cmd-Tab,
//  Dock e menu bar; Cmd+Q é tratado à parte no AppDelegate. Spotlight e o Monitor
//  de Atividade ainda escapam — é empurrão com atrito, não lock de segurança.
//

import AppKit
import SwiftUI

/// Janela borderless que PODE virar key — senão o monitor local de teclado não
/// recebe o Esc (o app fica ativo durante o lock, então monitor global não dispara).
private final class ShieldWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

final class DescansoController {
    private(set) var isActive = false
    /// Chamado quando o bloqueio termina (por tempo ou escape). Roda no main.
    var onEnd: (() -> Void)?

    private let model = BreakOverlayModel()
    private var windows: [NSWindow] = []
    private var timer: Timer?
    private var keyMonitor: Any?
    private var endDate = Date()
    private var escDownSince: Date?

    // Conjunto de quiosque VALIDADO (Kiosk Mode TN + precedente SplashBuddy).
    // hideDock satisfaz a dependência de hideMenuBar e das flags disable*.
    private static let kiosk: NSApplication.PresentationOptions =
        [.hideDock, .hideMenuBar, .disableAppleMenu,
         .disableForceQuit, .disableProcessSwitching, .disableSessionTermination]

    /// Começa um bloqueio de `duration` segundos. Ignora se já houver um ativo.
    func begin(label: String, duration: TimeInterval) {
        guard !isActive else { return }   // ponytail: um lock por vez; sem empilhar
        isActive = true
        endDate = Date().addingTimeInterval(duration)
        model.endDate = endDate
        model.label = label
        model.holdProgress = 0

        for screen in NSScreen.screens {
            let w = ShieldWindow(contentRect: screen.frame, styleMask: [.borderless],
                                 backing: .buffered, defer: false)
            w.isOpaque = false
            w.backgroundColor = .clear
            w.hasShadow = false
            w.level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()))
            w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            w.ignoresMouseEvents = false          // engole cliques (não passa pra trás)
            w.contentView = NSHostingView(rootView: BreakOverlayView(model: model))
            w.alphaValue = 0
            w.setFrame(screen.frame, display: true)
            w.orderFrontRegardless()
            windows.append(w)
        }

        // As flags de quiosque SÓ valem com o app ATIVO e revertem sozinhas quando
        // outro app fica ativo → ativar ANTES de setá-las (ver Achados).
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        windows.first?.makeKeyAndOrderFront(nil)
        NSApp.presentationOptions = Self.kiosk

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.4
            windows.forEach { $0.animator().alphaValue = 1 }
        }

        installEscMonitor()
        let t = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in self?.tickUI() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    /// Fim antecipado pelo escape. Em v1 == fim normal (o oneShot já se auto-desliga
    /// no onFire; recorrente segue armado, sem tocar em `enabled`).
    func abort() { end() }

    // MARK: - Interno

    private func tickUI() {
        if Date() >= endDate { end(); return }
        if let since = escDownSince {
            model.holdProgress = min(1, Date().timeIntervalSince(since) / 5)
            if model.holdProgress >= 1 { abort() }
        }
    }

    private func installEscMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp]) {
            [weak self] event in
            guard let self, event.keyCode == 53 else { return event }   // 53 = Esc
            if event.type == .keyDown {
                if self.escDownSince == nil { self.escDownSince = Date() }  // ignora auto-repeat
            } else {
                self.escDownSince = nil
                self.model.holdProgress = 0
            }
            return nil   // engole o Esc (não vaza pro app de trás)
        }
    }

    private func end() {
        guard isActive else { return }
        timer?.invalidate(); timer = nil
        if let m = keyMonitor { NSEvent.removeMonitor(m); keyMonitor = nil }
        escDownSince = nil

        NSApp.presentationOptions = []
        NSApp.setActivationPolicy(.accessory)   // volta a ser agente de background

        let closing = windows
        windows = []
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.4
            closing.forEach { $0.animator().alphaValue = 0 }
        }, completionHandler: {
            closing.forEach { $0.orderOut(nil) }
        })

        isActive = false
        onEnd?()
    }
}
