//
//  DocumentConverter.swift
//  Knobler
//
//  Documento: imagem → PDF, PDF → PNG (uma por página) e Markdown → PDF.
//  O Markdown é interpretado pelo parser do Foundation e desenhado com CoreText
//  — sem WebView, sem dependência externa.
//

import AppKit
import CoreText
import Foundation
import ImageIO
import PDFKit
import UniformTypeIdentifiers

enum DocumentConverter {
    enum Failure: Error {
        case unreadable      // arquivo não abre (não é PDF/markdown/imagem válida)
        case unwritable      // disco recusou ou destino não suportado
        case empty           // PDF sem páginas / markdown vazio
    }

    static func isMarkdown(_ url: URL) -> Bool {
        ["md", "markdown", "mdown"].contains(url.pathExtension.lowercased())
    }

    static func isPDF(_ url: URL) -> Bool {
        UTType(filenameExtension: url.pathExtension) == .pdf
    }

    // MARK: - Imagem → PDF

    static func pdf(fromImage url: URL) throws -> URL {
        guard let image = NSImage(contentsOf: url), let page = PDFPage(image: image) else {
            throw Failure.unreadable
        }
        let doc = PDFDocument()
        doc.insert(page, at: 0)
        let out = FileConverter.uniqueURL(for: url, ext: "pdf")
        guard doc.write(to: out) else { throw Failure.unwritable }
        return out
    }

    // MARK: - PDF → PNG

    /// Uma imagem por página, em 2x (fica legível numa tela Retina). Devolve a
    /// primeira — é ela que volta pro shelf; as outras ficam ao lado no disco.
    @discardableResult
    static func pngPages(fromPDF url: URL, scale: CGFloat = 2) throws -> [URL] {
        guard let doc = PDFDocument(url: url) else { throw Failure.unreadable }
        guard doc.pageCount > 0 else { throw Failure.empty }
        let base = url.deletingPathExtension().lastPathComponent
        var written: [URL] = []
        for index in 0..<doc.pageCount {
            guard let page = doc.page(at: index) else { continue }
            let bounds = page.bounds(for: .mediaBox)
            let width = Int((bounds.width * scale).rounded())
            let height = Int((bounds.height * scale).rounded())
            guard width > 0, height > 0,
                  let ctx = CGContext(
                    data: nil, width: width, height: height, bitsPerComponent: 8,
                    bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { throw Failure.unwritable }
            // página de PDF é transparente: sem o branco o PNG sai com fundo preto
            ctx.setFillColor(.white)
            ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
            ctx.scaleBy(x: scale, y: scale)
            ctx.translateBy(x: -bounds.origin.x, y: -bounds.origin.y)
            page.draw(with: .mediaBox, to: ctx)
            guard let image = ctx.makeImage() else { throw Failure.unwritable }

            // uma página: mantém o nome; várias: sufixo -p1, -p2…
            let name = doc.pageCount == 1 ? base : "\(base)-p\(index + 1)"
            let out = FileConverter.uniqueURL(
                directory: url.deletingLastPathComponent(), name: name, ext: "png")
            guard let dest = CGImageDestinationCreateWithURL(
                out as CFURL, UTType.png.identifier as CFString, 1, nil)
            else { throw Failure.unwritable }
            CGImageDestinationAddImage(dest, image, nil)
            guard CGImageDestinationFinalize(dest) else { throw Failure.unwritable }
            written.append(out)
        }
        guard !written.isEmpty else { throw Failure.empty }
        return written
    }

    // MARK: - Markdown → PDF

    static func pdf(fromMarkdown url: URL) throws -> URL {
        guard let text = try? String(contentsOf: url, encoding: .utf8), !text.isEmpty else {
            throw Failure.unreadable
        }
        let attributed = styled(markdown: text)
        guard attributed.length > 0 else { throw Failure.empty }
        let out = FileConverter.uniqueURL(for: url, ext: "pdf")
        try writePDF(attributed, to: out)
        return out
    }

    /// Letter em pontos, com 54pt (0,75") de margem — o padrão de impressão.
    private static let pageSize = CGSize(width: 612, height: 792)
    private static let margin: CGFloat = 54

    static func writePDF(_ text: NSAttributedString, to url: URL) throws {
        var mediaBox = CGRect(origin: .zero, size: pageSize)
        guard let ctx = CGContext(url as CFURL, mediaBox: &mediaBox, nil) else {
            throw Failure.unwritable
        }
        let framesetter = CTFramesetterCreateWithAttributedString(text)
        let path = CGPath(rect: mediaBox.insetBy(dx: margin, dy: margin), transform: nil)
        var start = 0
        while start < text.length {
            ctx.beginPDFPage(nil)
            let frame = CTFramesetterCreateFrame(
                framesetter, CFRange(location: start, length: 0), path, nil)
            CTFrameDraw(frame, ctx)
            let visible = CTFrameGetVisibleStringRange(frame)
            ctx.endPDFPage()
            // uma página que não coube nada (linha maior que a caixa) encerraria
            // num laço infinito — sai e entrega o que já tem
            guard visible.length > 0 else { break }
            start += visible.length
        }
        ctx.closePDF()
    }

    // MARK: - Markdown → NSAttributedString

    private static let body = NSFont.systemFont(ofSize: 11)
    private static let mono = NSFont.monospacedSystemFont(ofSize: 10, weight: .regular)

    /// Interpreta o markdown com o parser do Foundation e traduz cada intenção
    /// de apresentação (cabeçalho, lista, citação, código) em fonte e recuo.
    /// ponytail: sem tabela, imagem embutida nem regra horizontal — o parser
    /// entrega os blocos, mas desenhá-los é outro projeto.
    static func styled(markdown: String) -> NSAttributedString {
        guard let parsed = try? AttributedString(
            markdown: markdown,
            options: .init(interpretedSyntax: .full,
                           failurePolicy: .returnPartiallyParsedIfPossible))
        else { return NSAttributedString(string: markdown, attributes: [.font: body]) }

        let out = NSMutableAttributedString()
        var currentIntent: PresentationIntent?
        var isFirstBlock = true

        for run in parsed.runs {
            let intent = run.presentationIntent
            if intent != currentIntent {
                if !isFirstBlock { out.append(NSAttributedString(string: "\n")) }
                isFirstBlock = false
                currentIntent = intent
                if let prefix = listPrefix(intent) {
                    out.append(NSAttributedString(
                        string: prefix, attributes: [.font: body, .paragraphStyle: style(intent)]))
                }
            }
            let chunk = String(parsed[run.range].characters)
            guard !chunk.isEmpty else { continue }
            var attributes: [NSAttributedString.Key: Any] = [
                .font: font(intent, inline: run.inlinePresentationIntent),
                .paragraphStyle: style(intent),
                .foregroundColor: color(intent),
            ]
            if run.link != nil {
                attributes[.foregroundColor] = NSColor.systemBlue
                attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue
            }
            // o parser guarda a quebra dentro do bloco de código; fora dele não
            out.append(NSAttributedString(
                string: chunk.trimmingCharacters(in: isCode(intent) ? [] : .newlines),
                attributes: attributes))
        }
        return out
    }

    private static func kinds(_ intent: PresentationIntent?) -> [PresentationIntent.Kind] {
        intent?.components.map(\.kind) ?? []
    }

    private static func headerLevel(_ intent: PresentationIntent?) -> Int? {
        for kind in kinds(intent) {
            if case .header(let level) = kind { return level }
        }
        return nil
    }

    private static func isCode(_ intent: PresentationIntent?) -> Bool {
        kinds(intent).contains {
            if case .codeBlock = $0 { return true }
            return false
        }
    }

    private static func isQuote(_ intent: PresentationIntent?) -> Bool {
        kinds(intent).contains {
            if case .blockQuote = $0 { return true }
            return false
        }
    }

    /// "• " pra lista com marcador, "3. " pra numerada — o texto do item vem sem
    /// o marcador do markdown, então ele é escrito aqui.
    private static func listPrefix(_ intent: PresentationIntent?) -> String? {
        var ordinal: Int?
        var ordered = false
        for kind in kinds(intent) {
            if case .listItem(let n) = kind { ordinal = n }
            if case .orderedList = kind { ordered = true }
            if case .unorderedList = kind { ordered = false }
        }
        guard let ordinal else { return nil }
        return ordered ? "\(ordinal). " : "•  "
    }

    private static func font(
        _ intent: PresentationIntent?, inline: InlinePresentationIntent?
    ) -> NSFont {
        if isCode(intent) { return mono }
        var font: NSFont
        switch headerLevel(intent) {
        case 1: font = .systemFont(ofSize: 22, weight: .bold)
        case 2: font = .systemFont(ofSize: 17, weight: .bold)
        case 3: font = .systemFont(ofSize: 14, weight: .semibold)
        case .some: font = .systemFont(ofSize: 12, weight: .semibold)
        case nil: font = body
        }
        guard let inline else { return font }
        if inline.contains(.code) { return mono }
        let manager = NSFontManager.shared
        if inline.contains(.stronglyEmphasized) {
            font = manager.convert(font, toHaveTrait: .boldFontMask)
        }
        if inline.contains(.emphasized) || isQuote(intent) {
            font = manager.convert(font, toHaveTrait: .italicFontMask)
        }
        return font
    }

    private static func color(_ intent: PresentationIntent?) -> NSColor {
        isQuote(intent) ? .secondaryLabelColor : .black
    }

    private static func style(_ intent: PresentationIntent?) -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.lineHeightMultiple = 1.18
        style.paragraphSpacing = headerLevel(intent) != nil ? 6 : 10
        if headerLevel(intent) != nil { style.paragraphSpacingBefore = 8 }
        if listPrefix(intent) != nil {
            style.headIndent = 16
            style.paragraphSpacing = 3
        }
        if isQuote(intent) || isCode(intent) {
            style.firstLineHeadIndent = 16
            style.headIndent = 16
        }
        return style
    }
}
