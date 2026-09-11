//
//  NotchWindow.swift
//  Knobler
//
//  Painel transparente sobre o notch. Cliques em áreas 100% transparentes
//  passam direto pras janelas de baixo (comportamento padrão do AppKit para
//  janelas não-opacas), então só o desenho do notch intercepta o mouse.
//

import AppKit
import SwiftUI

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

    /// Habilitado pela apresentação apenas para conteúdo que aceita teclado.
    /// Fora disso o notch nunca rouba o foco do teclado —
    /// clicar no campo de texto do card torna a janela key sem ativar o app
    /// (nonactivatingPanel), então o terminal continua frontmost.
    var allowsKeyboard = false

    override var canBecomeKey: Bool { allowsKeyboard }
    override var canBecomeMain: Bool { false }
}

/// Host fixo, ancorado no painel. A sonda SwiftUI vê apenas seu próprio espaço;
/// esta medida também enxerga deslocamento do host e alteração de seus bounds.
final class NotchHostingView<Content: View>: NSHostingView<Content> {
    var diagnosticContext: (() -> ContextoDoCorte)?
    private let hostMonitor = VigiaDoCorte()

    var topDisplacement: CGFloat {
        guard let window else { return 0 }
        let inWindow = convert(bounds, to: nil)
        let frameGap = window.contentLayoutRect.maxY - inWindow.maxY
        return abs(frameGap) > abs(bounds.minY) ? frameGap : bounds.minY
    }

    override func layout() {
        super.layout()
        guard let diagnosticContext else { return }
        hostMonitor.avaliar(moldura: CGRect(x: frame.minX, y: topDisplacement,
                                            width: bounds.width, height: bounds.height),
                            contexto: diagnosticContext())
    }
}
