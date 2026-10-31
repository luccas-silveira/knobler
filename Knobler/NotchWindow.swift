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
    /// Clicar em outro app tira o teclado do painel.
    var aoPerderTeclado: (() -> Void)?
    override func resignKey() {
        super.resignKey()
        aoPerderTeclado?()
    }
    override var canBecomeMain: Bool { false }

    /// O `NotchHostingView` pendura aqui a medida do corte.
    var aoAparecer: (() -> Void)?
    override func orderFrontRegardless() {
        super.orderFrontRegardless()
        aoAparecer?()
    }
}

/// Host fixo, ancorado no painel. A sonda SwiftUI vê apenas seu próprio espaço;
/// esta medida também enxerga deslocamento do host e alteração de seus bounds.
final class NotchHostingView<Content: View>: NSHostingView<Content> {
    var diagnosticContext: (() -> ContextoDoCorte)?
    /// `var` só pro gate (`tools/cortehostcheck.swift`) trocar o registro e o
    /// relógio; o app usa o padrão.
    var hostMonitor = VigiaDoCorte()

    var topDisplacement: CGFloat {
        guard let window else { return 0 }
        let inWindow = convert(bounds, to: nil)
        let frameGap = window.contentLayoutRect.maxY - inWindow.maxY
        return abs(frameGap) > abs(bounds.minY) ? frameGap : bounds.minY
    }

    override func layout() {
        super.layout()
        medirCorte()
    }

    /// O painel nasce escondido e aparece no `orderFrontRegardless`, que não
    /// garante passada de layout: sem este gancho, um desvio que já estava lá
    /// quando ele apareceu só seria julgado na próxima mudança de geometria.
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        (window as? NotchWindow)?.aoAparecer = { [weak self] in self?.medirCorte() }
    }

    /// Painel escondido (nascendo, ou fora por tela cheia) não mostra corte
    /// nenhum: o vigia descarta a medida e não deixa pendência.
    func medirCorte() {
        guard let diagnosticContext else { return }
        hostMonitor.avaliar(moldura: CGRect(x: frame.minX, y: topDisplacement,
                                            width: bounds.width, height: bounds.height),
                            visivel: window?.isVisible == true,
                            contexto: diagnosticContext())
    }
}
