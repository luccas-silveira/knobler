//
//  ShelfThumbnailDragView.swift
//  Knobler
//
//  Miniatura do shelf como view AppKit + um monitor de mouse que inicia o drag.
//  Precisa ser AppKit (não .onDrag do SwiftUI) porque só uma sessão de drag
//  AppKit põe os BYTES da imagem sincronamente no pasteboard — o que o terminal
//  Electron anexa; o .onDrag só entrega file-url e o alvo cola o caminho.
//
//  Por que um monitor de mouse (e não mouseDown/mouseDragged na NSView): dentro
//  do NSHostingView do notch (NSPanel nonactivating), NSViews embutidas NÃO
//  recebem eventos de mouse — o hit-testing do SwiftUI os blinda. O
//  NSEvent.addLocalMonitorForEvents recebe o evento ANTES desse hit-testing
//  (mesmo truque do swipe do notch). É a técnica que o Dropover/Dropshit usa.
//

import AppKit
import QuickLookThumbnailing
import SwiftUI
import UniformTypeIdentifiers

struct ShelfThumbnailDragView: NSViewRepresentable {
    /// Os arquivos da entrada. A miniatura desenha o [0]; o arraste leva todos
    /// (ticket 006).
    let urls: [URL]
    /// Fim do arraste: `aceitou` = o destino levou, `dentroDoNotch` = terminou
    /// na própria prateleira. Quem decide o que fazer é o `Shelf.swift`, que tem
    /// a entrada e o Ajustes na mão — aqui só saem os fatos (ticket 005).
    /// O arraste terminou em cima de OUTRA miniatura: os arquivos da entrada
    /// alvo vêm aqui (ticket 007).
    var onSoltouSobre: ((_ alvo: [URL]) -> Void)?
    var onArrasteTerminou: ((_ aceitou: Bool, _ dentroDoNotch: Bool) -> Void)?

    func makeNSView(context: Context) -> NSView {
        let view = DragThumbView(urls: urls)
        view.onArrasteTerminou = onArrasteTerminou
        view.onSoltouSobre = onSoltouSobre
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard let view = nsView as? DragThumbView else { return }
        view.urls = urls
        // reatribuir é obrigatório: o SwiftUI recicla a mesma NSView pra outra
        // entrada, e o closure antigo removeria a entrada errada
        view.onArrasteTerminou = onArrasteTerminou
        view.onSoltouSobre = onSoltouSobre
    }
}

// não é `final` para a sonda de arraste (`tools/sondaarraste/`) poder herdar e
// instrumentar os callbacks sem que o app carregue a instrumentação junto
class DragThumbView: NSView, NSDraggingSource {
    var urls: [URL] {
        didSet { if urls.first != oldValue.first { loadThumbnail() } }
    }

    /// A capa: o que a miniatura mostra.
    var url: URL { urls[0] }

    private let imageView = NSImageView()

    var onArrasteTerminou: ((Bool, Bool) -> Void)?
    var onSoltouSobre: (([URL]) -> Void)?

    init(urls: [URL]) {
        self.urls = urls
        super.init(frame: .zero)
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(imageView)
        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: topAnchor),
            imageView.bottomAnchor.constraint(equalTo: bottomAnchor),
            imageView.leadingAnchor.constraint(equalTo: leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
        loadThumbnail()
    }

    /// Miniatura real do conteúdo via QuickLook, com o ícone genérico do tipo
    /// como placeholder enquanto gera (ou se o arquivo não tiver preview). Async:
    /// o QL mantém cache e chama de volta fora da main.
    private func loadThumbnail() {
        let url = self.url
        imageView.image = NSWorkspace.shared.icon(forFile: url.path)
        let scale = window?.backingScaleFactor ?? 2
        let request = QLThumbnailGenerator.Request(
            fileAt: url, size: CGSize(width: 30, height: 30),
            scale: scale, representationTypes: .thumbnail)
        QLThumbnailGenerator.shared.generateBestRepresentation(for: request) {
            [weak self] rep, _ in
            guard let rep else { return }
            DispatchQueue.main.async {
                // a view pode ter sido reciclada pra outro arquivo enquanto gerava
                guard let self, self.url == url else { return }
                self.imageView.image = rep.nsImage
            }
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) não usado") }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil {
            ShelfDragMonitor.shared.register(self)
        } else {
            ShelfDragMonitor.shared.unregister(self)
        }
    }

    /// Frame da miniatura em coordenadas de tela (mesmo referencial do
    /// NSEvent.mouseLocation), pra o monitor saber se o arrasto começou aqui.
    var currentScreenFrame: NSRect? {
        guard let window else { return nil }
        return window.convertToScreen(convert(bounds, to: nil))
    }

    /// Inicia a sessão de drag AppKit. Chamado pelo monitor, não por mouseDragged
    /// (que não dispara neste contexto).
    func startDrag(with event: NSEvent) {
        // Pilha: um NSPasteboardItem por arquivo — um item só não carrega N
        // file-urls. O caminho de um arquivo fica idêntico ao de sempre, com o
        // combo bytes+url que o Electron precisa.
        let itens: [NSPasteboardItem] = urls.count == 1
            ? [Self.itemDeArquivo(url)]
            : urls.map { u in
                let i = NSPasteboardItem()
                i.setString(u.absoluteString, forType: .fileURL)
                return i
            }

        let dragImage = NSImage(contentsOf: url) ?? NSWorkspace.shared.icon(forFile: url.path)
        let dragItems = itens.map { item -> NSDraggingItem in
            let d = NSDraggingItem(pasteboardWriter: item)
            d.setDraggingFrame(bounds, contents: dragImage)
            return d
        }
        // limpa a marca de um arraste anterior que nunca foi consumida: um drop
        // vindo do Finder liga `pendente` no `performDrop` e não tem sessão de
        // arraste pra consumir. Sem isto, o primeiro arquivo arrastado PRA
        // DENTRO deixaria a marca armada e o próximo arraste pra fora passaria
        // por interno — a saída nunca aconteceria.
        ShelfArrasteInterno.pendente = false
        beginDraggingSession(with: dragItems, event: event, source: self)
    }

    /// O item de pasteboard de um arquivo: bytes da imagem + file-url no MESMO
    /// item — combo que browsers/Electron aceitam (imagem) e o Finder também
    /// (arquivo). Os bytes primeiro, pra o alvo preferir a imagem à URL textual.
    private static func itemDeArquivo(_ url: URL) -> NSPasteboardItem {
        let item = NSPasteboardItem()
        let type = UTType(filenameExtension: url.pathExtension)
        if let type, type.conforms(to: .image), let data = try? Data(contentsOf: url) {
            item.setData(data, forType: NSPasteboard.PasteboardType(type.identifier))
        }
        item.setString(url.absoluteString, forType: .fileURL)
        return item
    }

    func draggingSession(
        _ session: NSDraggingSession,
        sourceOperationMaskFor context: NSDraggingContext
    ) -> NSDragOperation {
        .copy
    }

    /// `contains` e não `==`: `NSDragOperation` é OptionSet, e um destino pode
    /// devolver `[.copy, .generic]`.
    func draggingSession(
        _ session: NSDraggingSession,
        endedAt screenPoint: NSPoint,
        operation: NSDragOperation
    ) {
        // O empilhamento à mão é resolvido AQUI, no fim da sessão de arraste, e
        // não por um alvo de drop do SwiftUI na miniatura vizinha: um arraste
        // AppKit iniciado dentro do NSHostingView não tem garantia de alcançar
        // esse alvo, nem de que ele rode antes deste método. Se a ordem
        // invertesse, a regra do 005 apagaria a pilha recém-formada.
        //
        // Aqui a geometria é legítima — o alvo é a miniatura de 30x30 sob o
        // cursor, não o painel de 700pt que cobre meia tela e por isso não
        // serve de sinal (ver `ShelfArrasteInterno`).
        let alvo = ShelfDragMonitor.shared.view(at: screenPoint)
        let sobreIrma = alvo != nil && alvo !== self
        if let alvo, alvo !== self { onSoltouSobre?(alvo.urls) }
        onArrasteTerminou?(operation.contains(.copy),
                           ShelfArrasteInterno.consumir() || sobreIrma)
    }
}

/// Monitor local de mouse que inicia o drag de uma miniatura do shelf. Roda
/// antes do hit-testing do SwiftUI, que engoliria o evento numa NSView embutida.
final class ShelfDragMonitor {
    static let shared = ShelfDragMonitor()

    private let views = NSHashTable<DragThumbView>.weakObjects()
    private var downMonitor: Any?
    private var draggedMonitor: Any?
    private var upMonitor: Any?

    private weak var pending: DragThumbView?
    private var startLocation: NSPoint = .zero
    private var dragging = false
    private static let threshold: CGFloat = 3

    func register(_ view: DragThumbView) { views.add(view) }
    func unregister(_ view: DragThumbView) { views.remove(view) }

    func start() {
        guard downMonitor == nil else { return }

        downMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) {
            [weak self] event in
            guard let self else { return event }
            self.pending = self.view(at: NSEvent.mouseLocation)
            self.startLocation = NSEvent.mouseLocation
            self.dragging = false
            return event // não consome: cliques normais seguem pro SwiftUI
        }

        draggedMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDragged) {
            [weak self] event in
            guard let self, let view = self.pending, !self.dragging else { return event }
            let loc = NSEvent.mouseLocation
            guard hypot(loc.x - self.startLocation.x, loc.y - self.startLocation.y)
                > Self.threshold else { return event }
            self.dragging = true
            self.pending = nil
            view.startDrag(with: event)
            return nil // consome: o SwiftUI não arrasta junto
        }

        upMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseUp) {
            [weak self] event in
            self?.pending = nil
            self?.dragging = false
            return event
        }
    }

    /// A miniatura sob um ponto da tela. Serve tanto pra começar o arraste
    /// quanto pra saber, no fim dele, se ele parou sobre uma vizinha.
    func view(at screenPoint: NSPoint) -> DragThumbView? {
        for view in views.allObjects where view.currentScreenFrame?.contains(screenPoint) == true {
            return view
        }
        return nil
    }
}
