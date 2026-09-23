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
