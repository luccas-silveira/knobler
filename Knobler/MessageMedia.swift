//
//  MessageMedia.swift
//  Knobler
//
//  Anexos (foto/GIF) das Mensagens LAN: preparar um arquivo local pro fio
//  e exibir o recebido — GIF animado, que SwiftUI.Image não faz.
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers

enum MessageMedia {
    /// Abaixo disso vai cru; acima recomprime. Foto de celular passa dos 1,5 MB
    /// e não precisa de resolução cheia num balão de 180 pt.
    private static let rawLimit = 1_500_000

    static let openTypes: [UTType] = [.jpeg, .png, .gif]

    /// Lê o arquivo e devolve o par pronto pro fio. `nil` = não é imagem
    /// suportada ou não coube nem depois de recomprimir.
    static func prepare(_ url: URL) -> (Data, MediaKind)? {
        guard let raw = try? Data(contentsOf: url), let kind = MediaKind.detect(raw) else { return nil }
        // GIF passa cru se couber; senão reamostra os quadros (mantém a animação).
        if kind == .gif {
            if raw.count <= Frame.maxMedia { return (raw, .gif) }
            return shrunkGIF(raw).map { ($0, .gif) }
        }
        if raw.count <= rawLimit { return (raw, kind) }
        return downscaledJPEG(raw).map { ($0, .jpeg) }
    }

    /// Reencoda o GIF menor até caber: primeiro reduz o lado maior, depois
    /// começa a pular quadros (somando o tempo do quadro pulado no que fica,
    /// pra a animação não acelerar). `nil` = não coube nem no passo mais duro.
    private static func shrunkGIF(_ data: Data) -> Data? {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let n = CGImageSourceGetCount(src)
        guard n > 0 else { return nil }
        for (maxSide, step) in [(480, 1), (360, 2), (280, 3), (200, 4)] {
            let out = NSMutableData()
            guard let dest = CGImageDestinationCreateWithData(
                out, UTType.gif.identifier as CFString, (n + step - 1) / step, nil) else { return nil }
            CGImageDestinationSetProperties(dest, [kCGImagePropertyGIFDictionary: [
                kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
            for i in stride(from: 0, to: n, by: step) {
                guard let frame = CGImageSourceCreateThumbnailAtIndex(src, i, [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceThumbnailMaxPixelSize: maxSide] as CFDictionary) else { continue }
                let delay = (i..<min(i + step, n)).reduce(0.0) { $0 + frameDelay(src, $1) }
                CGImageDestinationAddImage(dest, frame, [kCGImagePropertyGIFDictionary: [
                    kCGImagePropertyGIFDelayTime: delay]] as CFDictionary)
            }
            guard CGImageDestinationFinalize(dest) else { return nil }
            if out.length <= Frame.maxMedia { return out as Data }
        }
        return nil
    }

    private static func frameDelay(_ src: CGImageSource, _ i: Int) -> Double {
        let p = CGImageSourceCopyPropertiesAtIndex(src, i, nil) as? [CFString: Any]
        let gif = p?[kCGImagePropertyGIFDictionary] as? [CFString: Any]
        let d = (gif?[kCGImagePropertyGIFUnclampedDelayTime] as? Double)
            ?? (gif?[kCGImagePropertyGIFDelayTime] as? Double) ?? 0.1
        return d > 0 ? d : 0.1
    }

    /// ponytail: reamostra pro lado maior = 1600 px e joga em JPEG 0.7.
    /// Perde alpha de PNG grande (vira fundo preto) — troca aceitável pra um
    /// balão de conversa; se incomodar, gravar PNG quando `hasAlpha`.
    private static func downscaledJPEG(_ data: Data) -> Data? {
        guard let src = NSImage(data: data), src.size.width > 0, src.size.height > 0 else { return nil }
        let scale = min(1, 1600 / max(src.size.width, src.size.height))
        let w = Int((src.size.width * scale).rounded()), h = Int((src.size.height * scale).rounded())
        guard w > 0, h > 0, let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h, bitsPerSample: 8,
            samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        src.draw(in: NSRect(x: 0, y: 0, width: w, height: h))
        NSGraphicsContext.restoreGraphicsState()
        guard let out = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.7]),
              out.count <= Frame.maxMedia else { return nil }
        return out
    }

    // ponytail: cache do formato — o SwiftUI pergunta a cada render e ler o
    // header do arquivo toda vez seria desperdício. Arquivo nunca muda de tamanho.
    private static var aspectCache: [String: CGFloat] = [:]

    /// Proporção largura/altura da imagem (1 se não der pra ler o header).
    static func aspect(_ url: URL) -> CGFloat {
        if let cached = aspectCache[url.path] { return cached }
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let p = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
              let w = p[kCGImagePropertyPixelWidth] as? CGFloat,
              let h = p[kCGImagePropertyPixelHeight] as? CGFloat, h > 0 else { return 1 }
        aspectCache[url.path] = w / h
        return w / h
    }

    /// Altura que a imagem ocupa no card de entrada ao tomar a largura toda.
    /// Vive aqui porque quem calcula o tamanho do notch (NotchView) e quem
    /// desenha (IncomingMessageView) precisam do mesmo número.
    static func cardHeight(_ url: URL, width: CGFloat = 344, cap: CGFloat = 190) -> CGFloat {
        min(width / aspect(url), cap)
    }

    /// Painel de escolha de arquivo (o notch não tem menu próprio pra isso).
    static func pick(completion: @escaping ((Data, MediaKind)?) -> Void) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = openTypes
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        // app roda como agente (LSUIElement): sem ativar, o painel abre sem foco
        // atrás de tudo e parece que o botão não fez nada. O nível acompanha o
        // notch, que fica acima das janelas normais.
        NSApp.activate(ignoringOtherApps: true)
        panel.level = .modalPanel
        panel.makeKeyAndOrderFront(nil)
        panel.begin { response in
            guard response == .OK, let url = panel.url else { completion(nil); return }
            // GIF grande leva segundos pra reamostrar — fora da main, senão trava o notch
            DispatchQueue.global(qos: .userInitiated).async {
                let prepared = prepare(url)
                DispatchQueue.main.async { completion(prepared) }
            }
        }
    }
}

/// Imagem de arquivo local — GIF anima (SwiftUI.Image mostra só o 1º quadro).
struct MediaThumb: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> NSImageView {
        let v = NSImageView()
        v.animates = true
        v.imageScaling = .scaleProportionallyUpOrDown
        v.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        v.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        return v
    }

    func updateNSView(_ v: NSImageView, context: Context) {
        // ponytail: identifier guarda o caminho já carregado — sem isso, todo
        // update do SwiftUI relê o arquivo do disco e reinicia o GIF.
        guard v.identifier?.rawValue != url.path else { return }
        v.identifier = NSUserInterfaceItemIdentifier(url.path)
        v.image = NSImage(contentsOf: url)
    }
}
