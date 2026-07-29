//
//  tools/imageconvertercheck.swift — self-check da conversão de imagem do shelf.
//  NÃO faz parte do alvo do app.
//
//  Rodar:
//  xcrun swiftc -parse-as-library -swift-version 5 \
//    Knobler/FileConverter.swift Knobler/ImageConverter.swift \
//    Knobler/DocumentConverter.swift Knobler/VideoConverter.swift \
//    tools/imageconvertercheck.swift \
//    -o /tmp/imageconvertercheck && /tmp/imageconvertercheck
//

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

@main
struct ImageConverterCheck {
    static func main() {
        testIsImage()
        testMenuFiltering()
        testRoundTrip()
        print("✅ imageconvertercheck ok")
    }

    static func testIsImage() {
        assert(ImageConverter.isImage(URL(fileURLWithPath: "/tmp/a.png")))
        assert(ImageConverter.isImage(URL(fileURLWithPath: "/tmp/a.HEIC")), "extensão é case-insensitive")
        assert(!ImageConverter.isImage(URL(fileURLWithPath: "/tmp/a.pdf")), "PDF não é imagem aqui")
        assert(!ImageConverter.isImage(URL(fileURLWithPath: "/tmp/a")), "sem extensão")
    }

    static func testMenuFiltering() {
        let png = URL(fileURLWithPath: "/tmp/a.png")
        assert(ImageConverter.isAlready(png, .png), "PNG→PNG some do menu")
        assert(!ImageConverter.isAlready(png, .jpeg))
        // .jpg e .jpeg são o mesmo UTType — o menu não pode oferecer JPEG pros dois
        assert(ImageConverter.isAlready(URL(fileURLWithPath: "/tmp/a.jpg"), .jpeg))
        assert(ImageConverter.targets.allSatisfy { !ImageConverter.label(for: $0).isEmpty })
    }

    /// Escreve um PNG 4x4 de verdade, converte pra JPEG e confere que o arquivo
    /// saiu com o tipo certo e o mesmo tamanho em pixels.
    static func testRoundTrip() {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("imageconvertercheck-\(getpid())")
        try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let src = dir.appendingPathComponent("origem.png")
        writePNG(at: src, side: 4)

        let out = try! ImageConverter.convert(src, to: .jpeg)
        assert(out.lastPathComponent == "origem.jpeg", "nome herdado: \(out.lastPathComponent)")
        assert(FileManager.default.fileExists(atPath: out.path), "arquivo saiu")
        assert(FileManager.default.fileExists(atPath: src.path), "original preservado")

        let source = CGImageSourceCreateWithURL(out as CFURL, nil)!
        assert(CGImageSourceGetType(source) as String? == UTType.jpeg.identifier, "virou JPEG mesmo")
        let image = CGImageSourceCreateImageAtIndex(source, 0, nil)!
        assert(image.width == 4 && image.height == 4, "dimensões preservadas")

        // segunda conversão não sobrescreve a primeira
        let again = try! ImageConverter.convert(src, to: .jpeg)
        assert(again.lastPathComponent == "origem-1.jpeg", "sufixo: \(again.lastPathComponent)")

        // arquivo que não é imagem falha limpo, sem criar lixo
        let fake = dir.appendingPathComponent("texto.png")
        try! Data("não sou imagem".utf8).write(to: fake)
        do {
            _ = try ImageConverter.convert(fake, to: .jpeg)
            assertionFailure("deveria ter lançado")
        } catch {
            assert(error as? ImageConverter.Failure == .unreadable)
        }
    }

    private static func writePNG(at url: URL, side: Int) {
        let ctx = CGContext(
            data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(red: 0.74, green: 0.45, blue: 0.15, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: side, height: side))
        let dest = CGImageDestinationCreateWithURL(
            url as CFURL, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(dest, ctx.makeImage()!, nil)
        assert(CGImageDestinationFinalize(dest))
    }
}
