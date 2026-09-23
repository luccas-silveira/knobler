//
//  textodatelacheck.swift
//  Cobre a parte pura do Texto da tela (TextoDaTela.swift): recorte em pixels
//  com Retina e monitor de origem negativa, descarte de seleção pequena, resumo
//  do aviso e o OCR de verdade numa imagem gerada.
//
//  xcrun swiftc -parse-as-library -swift-version 5 \
//    Knobler/TextoDaTela.swift tools/textodatelacheck.swift \
//    -o /tmp/textodatelacheck && /tmp/textodatelacheck
//

import AppKit

@main
enum TextoDaTelaCheck {
    static func main() {
        testRecorteRetina()
        testRecorteOrigemNegativa()
        testSelecaoValida()
        testResumo()
        testOCR()
        print("textodatelacheck ok")
    }

    /// Principal 1440×900 em 2x: seleção a 100 pt da esquerda e 200 pt do topo.
    static func testRecorteRetina() {
        let tela = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let sel = CGRect(x: 100, y: 900 - 200 - 50, width: 300, height: 50)
        let r = TextoDaTela.recortePixels(selecao: sel, tela: tela, escala: 2)
        assert(r == CGRect(x: 200, y: 400, width: 600, height: 100), "retina: \(r)")
    }

    /// Secundário à esquerda e abaixo do principal, 1x.
    static func testRecorteOrigemNegativa() {
        let tela = CGRect(x: -1920, y: -300, width: 1920, height: 1080)
        let sel = CGRect(x: -1900, y: 700, width: 100, height: 40)
        let r = TextoDaTela.recortePixels(selecao: sel, tela: tela, escala: 1)
        // x: -1900 - (-1920) = 20; y do topo: 780 - (700 + 40) = 40
        assert(r == CGRect(x: 20, y: 40, width: 100, height: 40), "negativa: \(r)")
    }

    static func testSelecaoValida() {
        assert(!TextoDaTela.selecaoValida(CGRect(x: 0, y: 0, width: 3.9, height: 100)))
        assert(!TextoDaTela.selecaoValida(CGRect(x: 0, y: 0, width: 100, height: 0)))
        assert(TextoDaTela.selecaoValida(CGRect(x: 0, y: 0, width: 4, height: 4)))
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
}
