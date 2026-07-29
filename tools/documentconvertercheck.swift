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
        testMarkdownTableAndBreak()
        testMarkdownImage()
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

        // citação em tinta escura fixa: `.secondaryLabelColor` resolvia pela
        // aparência do sistema e, no escuro, saía branca — sumia no PDF
        let quoteIndex = text.range(of: "citação")!.lowerBound.utf16Offset(in: text)
        let quoteColor = attr.attribute(.foregroundColor, at: quoteIndex, effectiveRange: nil)
            as! NSColor
        assert(quoteColor.usingColorSpace(.deviceRGB)!.brightnessComponent < 0.5,
               "citação visível no papel branco")

        // markdown quebrado não pode derrubar nada: entra, sai texto
        assert(DocumentConverter.styled(markdown: "**sem fim").length > 0)
    }

    /// Tabela e regra horizontal: o parser sempre entregou os blocos; o que se
    /// testa aqui é o desenho — célula na mesma linha separada por tab (com tab
    /// stop por coluna) e linhas diferentes separadas por quebra.
    static func testMarkdownTableAndBreak() {
        let md = """
        Antes

        ---

        | Nome | Qtd |
        |:-----|----:|
        | café | 2 |
        | pão | 10 |
        """
        let attr = DocumentConverter.styled(markdown: md)
        let text = attr.string
        assert(text.contains("Nome\tQtd"), "célula da mesma linha usa tab: \(text.debugDescription)")
        assert(text.contains("café\t2"))
        assert(text.contains("\ncafé"), "linha nova da tabela quebra: \(text.debugDescription)")
        assert(!text.contains("|"), "o pipe do markdown não vaza pro PDF")

        // cabeçalho da tabela em semibold, e o tab stop da 2ª coluna à direita
        let head = text.range(of: "Nome")!.lowerBound.utf16Offset(in: text)
        let headFont = attr.attribute(.font, at: head, effectiveRange: nil) as! NSFont
        let cellIndex = text.range(of: "café")!.lowerBound.utf16Offset(in: text)
        let cellFont = attr.attribute(.font, at: cellIndex, effectiveRange: nil) as! NSFont
        assert(headFont.fontDescriptor.symbolicTraits.contains(.bold), "cabeçalho destacado")
        assert(!cellFont.fontDescriptor.symbolicTraits.contains(.bold), "célula comum não")

        let cellStyle = attr.attribute(.paragraphStyle, at: cellIndex, effectiveRange: nil)
            as! NSParagraphStyle
        assert(cellStyle.tabStops.count == 1, "uma coluna sem tab (a 0) + uma com")
        assert(cellStyle.tabStops[0].alignment == .right, "coluna `----:` alinha à direita")
        assert(cellStyle.tabStops[0].location > 0)

        // a regra horizontal: o parser dá um "⸻" solto; o PDF quer a caixa inteira
        let rule = text.split(separator: "\n").first { $0.hasPrefix("⸻") }!
        let ruleIndex = text.range(of: rule)!.lowerBound.utf16Offset(in: text)
        // medida na string atribuída: a régua tem kern próprio pra emendar os traços
        let width = attr.attributedSubstring(
            from: NSRange(location: ruleIndex, length: rule.utf16.count)).size().width
        assert(width > (612 - 54 * 2) * 0.9, "régua atravessa a caixa, veio \(width)pt")
        assert(width <= 612 - 54 * 2, "e não estoura a margem")

        // cor fixa, não dinâmica: `.secondaryLabelColor` resolve pela aparência do
        // sistema e no modo escuro saía branca — invisível no PDF de fundo branco
        let ruleColor = attr.attribute(.foregroundColor, at: ruleIndex, effectiveRange: nil)
            as! NSColor
        assert(ruleColor.usingColorSpace(.deviceRGB)!.brightnessComponent < 0.5, "tinta escura")
    }

    /// Imagem embutida vira anexo de verdade — e caminho quebrado cai no alt.
    static func testMarkdownImage() {
        let foto = dir.appendingPathComponent("gato.png")
        writePNG(at: foto, width: 900, height: 300)   // mais larga que a caixa: encolhe
        let md = dir.appendingPathComponent("com-imagem.md")
        try! "Olha:\n\n![um gato](gato.png)\n".write(to: md, atomically: true, encoding: .utf8)

        let attr = DocumentConverter.styled(
            markdown: try! String(contentsOf: md, encoding: .utf8), baseURL: dir)
        var found: NSTextAttachment?
        attr.enumerateAttribute(.attachment, in: NSRange(location: 0, length: attr.length)) {
            value, _, _ in found = found ?? value as? NSTextAttachment
        }
        let anexo = found!
        assert(anexo.image != nil, "imagem relativa resolvida contra a pasta do .md")
        assert(abs(anexo.bounds.width - (612 - 54 * 2)) < 0.5, "largura limitada à caixa")
        assert(abs(anexo.bounds.height - anexo.bounds.width / 3) < 0.5, "proporção 3:1 preservada")
        assert(!attr.string.contains("um gato"), "alt sai de cena quando a imagem carrega")

        // caminho quebrado: sem anexo, o alt segue como texto (não some conteúdo)
        let quebrado = DocumentConverter.styled(markdown: "![sumiu](nao-existe.png)", baseURL: dir)
        assert(quebrado.string.contains("sumiu"), "imagem faltando cai no alt")

        // e o PDF sai com a imagem dentro
        let pdf = try! DocumentConverter.pdf(fromMarkdown: md)
        let doc = PDFDocument(url: pdf)!
        assert(doc.pageCount == 1)
        assert(doc.page(at: 0)!.string?.contains("Olha") == true, "o texto ao redor sobreviveu")
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
