//
//  NotchViewModel.swift
//  Knobler
//

import Foundation
import SwiftUI

/// Atividade persistente publicada via API local (deploy, download, métrica…).
struct NotchActivity: Equatable {
    var id: String
    var title: String
    var detail: String
    /// 0…1; nil = indeterminada (arco girando)
    var progress: Double?
    var updatedAt: Date
}

final class NotchViewModel: ObservableObject {
    @Published var expanded = false {
        // recolher o notch desliga o espelho — a câmera nunca fica ligada escondida
        didSet { if !expanded { mirrorOn = false } }
    }
    @Published var mirrorOn = false
    /// Algum app está capturando o microfone (pontinho laranja no notch).
    @Published var micInUse = false
    /// Música pausada some do notch; hover "espia" (peeking) antes de expandir.
    @Published var musicPaused = false
    @Published var peeking = false
    @Published var notchSize = CGSize(width: 200, height: 32)
    /// true = notch físico (câmera no meio); false = ilha simulada em monitor externo
    @Published var hasRealNotch = false
    @Published var activeNotification: NotchNotification?
    @Published var hud: HUDState?
    @Published var activity: NotchActivity?

    struct HUDState: Equatable {
        enum Kind: Equatable { case volume, brightness, battery }
        var kind: Kind = .volume
        var level: Float
        var muted: Bool = false
        var charging: Bool = false
    }

    enum Mode: Equatable {
        case closed, music, notification, hud
    }

    /// Prioridade: notificação > HUD > música (hover).
    var mode: Mode {
        if activeNotification != nil { return .notification }
        if hud != nil { return .hud }
        return expanded ? .music : .closed
    }

    // ponytail: delays fixos anti-flicker; virar preferência se incomodar
    private let openDelay: TimeInterval = 0.18
    private let closeDelay: TimeInterval = 0.30
    /// Janela pós-fechar em que enter é ignorado: o frame encolhendo debaixo
    /// do mouse dispara enter de novo e reabre em loop sem isso.
    private let reopenCooldown: TimeInterval = 0.45
    private var lastCollapseAt = Date.distantPast
    private let notificationDuration: TimeInterval = 5.0
    private let hudDuration: TimeInterval = 1.5
    private var pendingWork: DispatchWorkItem?
    private var queue: [NotchNotification] = []
    private var dismissWork: DispatchWorkItem?
    private var hudWork: DispatchWorkItem?

    private var hovering = false
    /// Pausado: tempo de espiada antes de abrir o card completo.
    private let peekDwell: TimeInterval = 0.8

    func setHover(_ inside: Bool) {
        hovering = inside
        pendingWork?.cancel()

        guard inside else {
            let work = DispatchWorkItem { [weak self] in
                guard let self else { return }
                if self.expanded || self.peeking { self.lastCollapseAt = Date() }
                self.expanded = false
                self.peeking = false
            }
            pendingWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + closeDelay, execute: work)
            return
        }

        guard !expanded else { return }
        guard Date().timeIntervalSince(lastCollapseAt) >= reopenCooldown else { return }

        let work = DispatchWorkItem { [weak self] in
            guard let self, self.hovering else { return }
            if self.musicPaused, !self.peeking {
                // etapa 1: espia as asinhas; mouse parado em cima abre o completo
                self.peeking = true
                self.scheduleExpandAfterPeek()
            } else {
                self.expanded = true
            }
        }
        pendingWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + openDelay, execute: work)
    }

    private func scheduleExpandAfterPeek() {
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.hovering else { return }
            self.expanded = true
        }
        pendingWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + peekDwell, execute: work)
    }

    /// Abre/fecha por gesto (swipe): imediato, sem os delays do hover.
    func setExpandedDirect(_ value: Bool) {
        pendingWork?.cancel()
        expanded = value
    }

    // MARK: - Notificações

    func enqueue(_ notification: NotchNotification) {
        if activeNotification == nil {
            show(notification)
        } else {
            queue.append(notification)
        }
    }

    func dismissActiveNotification() {
        dismissWork?.cancel()
        activeNotification = nil
        if !queue.isEmpty {
            let next = queue.removeFirst()
            // respiro entre uma e outra pra animação de fechar/abrir ler bem
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
                self?.show(next)
            }
        }
    }

    /// Segurar o mouse em cima pausa o auto-dismiss.
    func holdNotification(_ hovering: Bool) {
        guard activeNotification != nil else { return }
        if hovering {
            dismissWork?.cancel()
        } else {
            scheduleDismiss()
        }
    }

    private func show(_ notification: NotchNotification) {
        activeNotification = notification
        scheduleDismiss()
    }

    private func scheduleDismiss() {
        dismissWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.dismissActiveNotification()
        }
        dismissWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + notificationDuration, execute: work)
    }

    // MARK: - HUD de som

    func showHUD(_ state: HUDState, duration: TimeInterval? = nil) {
        hud = state
        hudWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.hud = nil
        }
        hudWork = work
        DispatchQueue.main.asyncAfter(
            deadline: .now() + (duration ?? hudDuration), execute: work)
    }
}
