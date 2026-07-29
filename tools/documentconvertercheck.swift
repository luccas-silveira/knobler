//
//  tools/documentconvertercheck.swift — self-check das conversões de documento
//  (imagem → PDF, PDF → PNG, Markdown → PDF) e do despachante do menu.
//  NÃO faz parte do alvo do app.
//
//  Rodar:
//  xcrun swiftc -parse-as-library -swift-version 5 \
//    Knobler/FileConverter.swift Knobler/ImageConverter.swift \
//    Knobler/DocumentConverter.swift Knobler/VideoConverter.swift \
//    tools/documentconvertercheck.swift -o /tmp/documentconvertercheck \
//    && /tmp/documentconvertercheck
//

import AppKit
import Foundation
import ImageIO
import PDFKit
import UniformTypeIdentifiers

@main
struct DocumentConverterCheck {
    static var dir = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("documentconvertercheck-\(getpid())")

    static func main() {
        try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        testMenuTargets()
        testUniqueURL()
        testImageToPDF()
        testPDFToPNG()
        testMarkdownStyling()
        testMarkdownToPDF()
        print("✅ documentconvertercheck ok")
    }

    // MARK: - Menu

    /// O menu é o contrato: cada tipo de arquivo oferece o que faz sentido e
    /// nada além. Um destino errado aqui vira crash ou arquivo lixo lá.
    static func testMenuTargets() {
        func labels(_ name: String) -> [String] {
            FileConverter.targets(for: URL(fileURLWithPath: "/tmp/\(name)")).map(\.label)
        }
        assert(labels("a.png") == ["JPEG", "HEIC", "PDF"], "PNG não se oferece: \(labels("a.png"))")
        assert(labels("a.jpg") == ["PNG", "HEIC", "PDF"])
        assert(labels("a.pdf") == ["PNG (páginas)"], "PDF só rasteriza")
        assert(labels("a.md") == ["PDF"], "markdown só vira PDF")
        assert(labels("a.markdown") == ["PDF"])
        assert(labels("a.mov") == ["MP4"], "MOV não se oferece: \(labels("a.mov"))")
        assert(labels("a.mp4") == ["MOV"])
        assert(labels("a.txt").isEmpty, "texto puro não tem conversão")
        assert(labels("a.zip").isEmpty)
    }

    static func testUniqueURL() {
        let taken: Set<String> = ["/tmp/foto.png", "/tmp/foto-1.png"]
        let free = FileConverter.uniqueURL(
            directory: URL(fileURLWithPath: "/tmp"), name: "foto", ext: "png") {
            taken.contains($0.path)
        }
        assert(free.lastPathComponent == "foto-2.png", "pula os ocupados: \(free)")
    }

    // MARK: - Imagem ⇄ PDF

    static func testImageToPDF() {
        let png = dir.appendingPathComponent("figura.png")
        writePNG(at: png, width: 40, height: 20)
        let pdf = try! DocumentConverter.pdf(fromImage: png)
        assert(pdf.lastPathComponent == "figura.pdf")
        let doc = PDFDocument(url: pdf)!
        assert(doc.pageCount == 1, "uma imagem = uma página")
        assert(FileManager.default.fileExists(atPath: png.path), "original preservado")
    }

    static func testPDFToPNG() {
        // PDF de 2 páginas montado a partir de duas imagens
        let doc = PDFDocument()
        for i in 0..<2 {
            let img = dir.appendingPathComponent("p\(i).png")
            writePNG(at: img, width: 30, height: 30)
            doc.insert(PDFPage(image: NSImage(contentsOf: img)!)!, at: i)
        }
        let pdf = dir.appendingPathComponent("duas.pdf")
        assert(doc.write(to: pdf))

        let pages = try! DocumentConverter.pngPages(fromPDF: pdf, scale: 1)
        assert(pages.count == 2, "uma imagem por página, veio \(pages.count)")
        assert(pages[0].lastPathComponent == "duas-p1.png", "sufixo de página: \(pages[0])")
        assert(pages[1].lastPathComponent == "duas-p2.png")
        for page in pages {
            let src = CGImageSourceCreateWithURL(page as CFURL, nil)!
            assert(CGImageSourceGetType(src) as String? == UTType.png.identifier)
            assert(CGImageSourceCreateImageAtIndex(src, 0, nil)!.width > 0)
        }

        // arquivo que não é PDF falha limpo
        let fake = dir.appendingPathComponent("mentira.pdf")
        try! Data("nada".utf8).write(to: fake)
        do {
            _ = try DocumentConverter.pngPages(fromPDF: fake)
            assertionFailure("deveria ter lançado")
        } catch {
            assert(error as? DocumentConverter.Failure == .unreadable)
        }
    }

    // MARK: - Markdown

    static func testMarkdownStyling() {
        let md = """
        # Título

        Parágrafo com **negrito** e `código`.

        - item um
        - item dois

        1. primeiro

        > citação
        """
        let attr = DocumentConverter.styled(markdown: md)
        let text = attr.string
        assert(text.contains("Título"))
        assert(text.contains("•  item um"), "marcador escrito à mão: \(text.debugDescription)")
        assert(text.contains("1. primeiro"), "lista numerada mantém o ordinal")
        assert(!text.contains("**"), "sintaxe do markdown não vaza pro PDF")
        assert(!text.contains("#"), "cerquilha do cabeçalho não vaza")

        // cabeçalho maior que corpo, e negrito virou traço de fonte de verdade
        let title = attr.attribute(.font, at: 0, effectiveRange: nil) as! NSFont
        let bodyIndex = text.range(of: "Parágrafo")!.lowerBound.utf16Offset(in: text)
        let bodyFont = attr.attribute(.font, at: bodyIndex, effectiveRange: nil) as! NSFont
        assert(title.pointSize > bodyFont.pointSize, "cabeçalho maior que o corpo")

        let boldIndex = text.range(of: "negrito")!.lowerBound.utf16Offset(in: text)
        let boldFont = attr.attribute(.font, at: boldIndex, effectiveRange: nil) as! NSFont
        assert(NSFontManager.shared.traits(of: boldFont).contains(.boldFontMask), "negrito aplicado")

        let codeIndex = text.range(of: "código")!.lowerBound.utf16Offset(in: text)
        let codeFont = attr.attribute(.font, at: codeIndex, effectiveRange: nil) as! NSFont
        assert(codeFont.fontName != bodyFont.fontName, "código em monoespaçada")

        // markdown quebrado não pode derrubar nada: entra, sai texto
        assert(DocumentConverter.styled(markdown: "**sem fim").length > 0)
    }

    static func testMarkdownToPDF() {
        let md = dir.appendingPathComponent("notas.md")
        // texto longo o bastante pra forçar paginação
        let corpo = (1...400).map { "Linha \($0) do documento de teste." }.joined(separator: "\n\n")
        try! "# Relatório\n\n\(corpo)".write(to: md, atomically: true, encoding: .utf8)

        let pdf = try! DocumentConverter.pdf(fromMarkdown: md)
        assert(pdf.lastPathComponent == "notas.pdf")
        let doc = PDFDocument(url: pdf)!
        assert(doc.pageCount > 1, "texto longo pagina: \(doc.pageCount) página(s)")
        let first = doc.page(at: 0)!.string ?? ""
        assert(first.contains("Relatório"), "o conteúdo chegou no PDF")
        assert(doc.page(at: doc.pageCount - 1)!.string?.contains("Linha 400") == true,
               "a última linha não foi perdida na paginação")

        // markdown vazio falha em vez de gerar PDF em branco
        let vazio = dir.appendingPathComponent("vazio.md")
        try! "".write(to: vazio, atomically: true, encoding: .utf8)
        do {
            _ = try DocumentConverter.pdf(fromMarkdown: vazio)
            assertionFailure("deveria ter lançado")
        } catch {
            assert(error as? DocumentConverter.Failure == .unreadable)
        }
    }

    // MARK: - Fixtures

    private static func writePNG(at url: URL, width: Int, height: Int) {
        let ctx = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(red: 0.74, green: 0.45, blue: 0.15, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let dest = CGImageDestinationCreateWithURL(
            url as CFURL, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(dest, ctx.makeImage()!, nil)
        assert(CGImageDestinationFinalize(dest))
    }
}
