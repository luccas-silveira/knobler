//
//  Sonda do ticket 001 — o que os destinos devolvem quando aceitam o arraste.
//
//  Compila o ARQUIVO REAL da miniatura do shelf (`ShelfThumbnailDragView.swift`)
//  em vez de copiar o código: o que um destino responde depende inteiramente da
//  forma do pasteboard que `startDrag` escreve, então uma cópia à mão mediria
//  outra coisa. A instrumentação é uma subclasse daqui, pra o app não carregar
//  log de arraste nenhum.
//
//    xcrun swiftc -swift-version 5 \
//      Knobler/ShelfOrdem.swift Knobler/ShelfThumbnailDragView.swift \
//      tools/sondaarraste/main.swift \
//      -o /tmp/sondaarraste && /tmp/sondaarraste <arquivo> <x> <y> [rótulo]
//
//  <x> <y> são coordenadas de TELA no referencial do CGEvent (origem no topo
//  esquerdo). O log sai em /tmp/knobler-arraste-001.log.
//
//  Descartável: some quando a medição 001 fechar.
//

import AppKit

/// A instrumentação vive AQUI, não no app.
///
/// `DragThumbView` fica intocado: a subclasse herda o `startDrag` de verdade —
/// que é o que determina a forma do pasteboard, e portanto o que os destinos
/// respondem — e só acrescenta o registro. Assim a sonda mede o código real sem
/// deixar log de arraste no app que o usuário roda.
final class ThumbSondado: DragThumbView {
    override func draggingSession(
        _ session: NSDraggingSession,
        sourceOperationMaskFor context: NSDraggingContext
    ) -> NSDragOperation {
        // o AppKit chama isto a cada consulta de destino; só a mudança de
        // contexto é informação
        let nome = SondaDoArraste.nome(context)
        if SondaDoArraste.ultimoContexto != nome {
            SondaDoArraste.ultimoContexto = nome
            SondaDoArraste.registrar("pedido  \(url.lastPathComponent)  contexto=\(nome)")
        }
        return super.draggingSession(session, sourceOperationMaskFor: context)
    }

    override func draggingSession(
        _ session: NSDraggingSession,
        endedAt screenPoint: NSPoint,
        operation: NSDragOperation
    ) {
        SondaDoArraste.registrar(
            "fim     \(url.lastPathComponent)  operação=\(SondaDoArraste.nome(operation))"
                + "  raw=\(operation.rawValue)  ponto=\(Int(screenPoint.x)),\(Int(screenPoint.y))")
    }
}

/// Escreve uma linha por evento de arraste em `/tmp/knobler-arraste-001.log`.
/// Arquivo e não `NSLog` porque a leitura é feita depois, de uma vez, e o log
/// unificado do macOS mistura tudo.
enum SondaDoArraste {
    static let caminho = "/tmp/knobler-arraste-001.log"
    static var ultimoContexto = ""

    static func nome(_ op: NSDragOperation) -> String {
        if op.isEmpty { return "none" }
        var partes: [String] = []
        if op.contains(.copy) { partes.append("copy") }
        if op.contains(.move) { partes.append("move") }
        if op.contains(.link) { partes.append("link") }
        if op.contains(.delete) { partes.append("delete") }
        if op.contains(.generic) { partes.append("generic") }
        if op.contains(.private) { partes.append("private") }
        return partes.isEmpty ? "desconhecida(\(op.rawValue))" : partes.joined(separator: "+")
    }

    static func nome(_ contexto: NSDraggingContext) -> String {
        switch contexto {
        case .outsideApplication: return "fora-do-app"
        case .withinApplication: return "dentro-do-app"
        @unknown default: return "desconhecido"
        }
    }

    static func registrar(_ linha: String) {
        let hora = ISO8601DateFormatter().string(from: Date())
        guard let dados = "\(hora)  \(linha)\n".data(using: .utf8) else { return }
        if let handle = FileHandle(forWritingAtPath: caminho) {
            handle.seekToEndOfFile()
            handle.write(dados)
            try? handle.close()
        } else {
            try? dados.write(to: URL(fileURLWithPath: caminho))
        }
    }
}

let args = CommandLine.arguments
guard args.count >= 4,
      let alvoX = Double(args[2]), let alvoY = Double(args[3])
else {
    FileHandle.standardError.write("uso: sondaarraste <arquivo> <x> <y> [rótulo]\n".data(using: .utf8)!)
    exit(2)
}
let arquivo = URL(fileURLWithPath: args[1])
let rotulo = args.count > 4 ? args[4] : "sem-rótulo"

final class Delegate: NSObject, NSApplicationDelegate {
    let arquivo: URL
    let alvo: CGPoint
    let rotulo: String
    var janela: NSWindow!
    var thumb: ThumbSondado!

    init(arquivo: URL, alvo: CGPoint, rotulo: String) {
        self.arquivo = arquivo
        self.alvo = alvo
        self.rotulo = rotulo
    }

    func applicationDidFinishLaunching(_ note: Notification) {
        // a tela PRIMÁRIA (origem 0,0), não `NSScreen.main` — que no lançamento
        // pode ser qualquer uma e jogaria a janela pra fora do referencial
        let tela = (NSScreen.screens.first { $0.frame.origin == .zero } ?? NSScreen.screens[0]).frame
        // canto inferior esquerdo da tela principal, longe de qualquer alvo
        let frame = NSRect(x: tela.minX + 60, y: tela.minY + 60, width: 220, height: 120)
        janela = NSWindow(contentRect: frame, styleMask: [.titled], backing: .buffered, defer: false)
        janela.title = "sonda"
        janela.level = .floating

        thumb = ThumbSondado(urls: [arquivo])
        thumb.frame = NSRect(x: 30, y: 30, width: 60, height: 60)
        janela.contentView?.addSubview(thumb)

        let alvoInterno = AlvoInterno(frame: NSRect(x: 130, y: 30, width: 60, height: 60))
        janela.contentView?.addSubview(alvoInterno)
        janela.makeKeyAndOrderFront(nil)

        ShelfDragMonitor.shared.start()

        // espião: confirma que os eventos sintéticos chegam a ESTE app
        NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp]) {
            evento in
            if evento.type == .leftMouseDown {
                SondaDoArraste.registrar(
                    "espião  down em \(NSEvent.mouseLocation)"
                        + "  thumb=\(String(describing: self.thumb.currentScreenFrame))"
                        + "  janelaVisível=\(self.janela.isVisible)")
            }
            return evento
        }

        // O arrasto tem que ser dirigido de FORA da main: beginDraggingSession
        // roda um laço de eventos aninhado na main, e de lá não dá pra postar.
        // sem isto o monitor local não vê evento nenhum: `addLocalMonitorForEvents`
        // só recebe o que é entregue a ESTE app, e o app precisa estar na frente
        NSApp.activate(ignoringOtherApps: true)

        Thread.detachNewThread { [self] in
            Thread.sleep(forTimeInterval: 1.5)
            arrastar()
            Thread.sleep(forTimeInterval: 2.0)
            SondaDoArraste.registrar("--- fim do arraste \(rotulo) ---")
            exit(0)
        }
    }

    /// Converte um ponto Cocoa (origem embaixo) pro referencial do CGEvent
    /// (origem no topo).
    private func paraCG(_ ponto: NSPoint) -> CGPoint {
        // o referencial do CGEvent tem origem no topo da tela PRIMÁRIA, não no
        // topo do retângulo que une todas: usar o maior maxY de todas as telas
        // jogava o ponto pra fora por centenas de pontos
        let topo = NSScreen.screens[0].frame.maxY
        return CGPoint(x: ponto.x, y: topo - ponto.y)
    }

    private func arrastar() {
        let origemCocoa = janela.convertToScreen(thumb.convert(thumb.bounds, to: nil)).center
        let origem = paraCG(origemCocoa)
        SondaDoArraste.registrar(
            "início  \(rotulo)  \(arquivo.lastPathComponent)"
                + "  de \(Int(origem.x)),\(Int(origem.y)) para \(Int(alvo.x)),\(Int(alvo.y))")

        postar(.mouseMoved, em: origem)
        Thread.sleep(forTimeInterval: 0.15)
        postar(.leftMouseDown, em: origem)
        Thread.sleep(forTimeInterval: 0.15)

        // passos pequenos: o hit-testing do destino só acorda com movimento
        // contínuo, e o monitor da miniatura precisa passar do limiar de 3 pt
        let passos = 40
        for i in 1...passos {
            let t = Double(i) / Double(passos)
            let p = CGPoint(x: origem.x + (alvo.x - origem.x) * t,
                            y: origem.y + (alvo.y - origem.y) * t)
            postar(.leftMouseDragged, em: p)
            Thread.sleep(forTimeInterval: 0.02)
        }
        // parado em cima do alvo por um tempo: destino precisa aceitar o hover
        for _ in 1...15 {
            postar(.leftMouseDragged, em: alvo)
            Thread.sleep(forTimeInterval: 0.04)
        }
        postar(.leftMouseUp, em: alvo)
    }

    private func postar(_ tipo: CGEventType, em ponto: CGPoint) {
        let botao: CGMouseButton = .left
        guard let evento = CGEvent(mouseEventSource: nil, mouseType: tipo,
                                   mouseCursorPosition: ponto, mouseButton: botao)
        else { return }
        evento.post(tap: .cghidEventTap)
    }
}

/// Alvo de soltura DENTRO do próprio app, pra medir o caso do ticket 007:
/// arrastar uma miniatura do shelf sobre outra. Se o `endedAt` do arraste
/// devolver `copy` aqui, a remoção do 005 dispararia num arraste que nunca saiu
/// da prateleira.
final class AlvoInterno: NSView {
    override init(frame: NSRect) {
        super.init(frame: frame)
        registerForDraggedTypes([.fileURL])
    }
    required init?(coder: NSCoder) { fatalError() }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { .copy }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        SondaDoArraste.registrar("alvo interno recebeu a soltura")
        return true
    }
}

extension NSRect {
    var center: NSPoint { NSPoint(x: midX, y: midY) }
}

let app = NSApplication.shared
let delegate = Delegate(arquivo: arquivo, alvo: CGPoint(x: alvoX, y: alvoY), rotulo: rotulo)
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
