//
//  textodatelacheck.swift
//  Cobre a parte pura do Texto da tela (TextoDaTela.swift): resumo do aviso e
//  o OCR de verdade numa imagem gerada.
//
//  xcrun swiftc -parse-as-library -swift-version 5 \
//    Knobler/TextoDaTela.swift tools/textodatelacheck.swift \
//    -o /tmp/textodatelacheck && /tmp/textodatelacheck
//

import AppKit

@main
enum TextoDaTelaCheck {
    static func main() {
        testResumo()
        testOCR()
        testOCRDepoisDeApagarOArquivo()
        print("textodatelacheck ok")
    }

    static func testResumo() {
        assert(TextoDaTela.resumo("  Olá mundo \nsegunda linha") == "Olá mundo")
        let longo = String(repeating: "a", count: 80)
        let r = TextoDaTela.resumo(longo, limite: 60)
        assert(r.count == 60 && r.hasSuffix("…"), "resumo: \(r)")
    }

    /// OCR pelo mesmo caminho do app, sobre uma imagem com texto conhecido.
    static func testOCR() {
        let w = 800, h = 120
        let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(.white); ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
        ("Knobler extrai texto" as NSString).draw(
            at: NSPoint(x: 20, y: 35),
            withAttributes: [.font: NSFont.systemFont(ofSize: 48), .foregroundColor: NSColor.black])
        NSGraphicsContext.current = nil
        let linhas = try! TextoDaTela.linhas(em: ctx.makeImage()!)
        assert(linhas.joined(separator: " ") == "Knobler extrai texto", "ocr: \(linhas)")
    }

    /// O app apaga o PNG do screencapture logo depois de abrir; o OCR roda
    /// depois, noutra fila. A imagem não pode depender do arquivo ainda existir
    /// (o CGImage da URL decodifica preguiçoso e voltava sem texto nenhum).
    static func testOCRDepoisDeApagarOArquivo() {
        let w = 800, h = 120
        let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(.white); ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
        ("Knobler extrai texto" as NSString).draw(
            at: NSPoint(x: 20, y: 35),
            withAttributes: [.font: NSFont.systemFont(ofSize: 48), .foregroundColor: NSColor.black])
        NSGraphicsContext.current = nil
        let arquivo = FileManager.default.temporaryDirectory.appendingPathComponent("textodatelacheck.png")
        let png = NSBitmapImageRep(cgImage: ctx.makeImage()!).representation(using: .png, properties: [:])!
        try! png.write(to: arquivo)
        let imagem = TextoDaTela.imagem(de: arquivo)!
        try! FileManager.default.removeItem(at: arquivo)
        let linhas = (try? TextoDaTela.linhas(em: imagem)) ?? []
        assert(linhas.joined(separator: " ") == "Knobler extrai texto", "depois de apagar: \(linhas)")
    }
}
