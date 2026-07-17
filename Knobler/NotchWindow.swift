//
//  NotchWindow.swift
//  Knobler
//
//  Painel transparente sobre o notch. Cliques em áreas 100% transparentes
//  passam direto pras janelas de baixo (comportamento padrão do AppKit para
//  janelas não-opacas), então só o desenho do notch intercepta o mouse.
//

import AppKit

final class NotchWindow: NSPanel {
    override init(
        contentRect: NSRect,
        styleMask: NSWindow.StyleMask,
        backing: NSWindow.BackingStoreType,
        defer flag: Bool
    ) {
        super.init(contentRect: contentRect, styleMask: styleMask, backing: backing, defer: flag)

        isFloatingPanel = true
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isMovable = false
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        isReleasedWhenClosed = false
        level = .mainMenu + 3
        collectionBehavior = [
            .fullScreenAuxiliary,
            .stationary,
            .canJoinAllSpaces,
            .ignoresCycle,
        ]
    }

    /// true SÓ enquanto um card de pergunta está na tela (setado por Combine
    /// no AppDelegate). Fora disso o notch nunca rouba o foco do teclado —
    /// clicar no campo de texto do card torna a janela key sem ativar o app
    /// (nonactivatingPanel), então o terminal continua frontmost.
    var allowsKeyboard = false

    override var canBecomeKey: Bool { allowsKeyboard }
    override var canBecomeMain: Bool { false }
}
