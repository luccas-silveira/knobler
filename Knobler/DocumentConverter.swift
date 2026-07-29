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

    /// `directory` nil = ao lado do original. O preview passa uma pasta temporária.
    static func pdf(fromImage url: URL, in directory: URL? = nil) throws -> URL {
        guard let image = NSImage(contentsOf: url), let page = PDFPage(image: image) else {
            throw Failure.unreadable
        }
        let doc = PDFDocument()
        doc.insert(page, at: 0)
        let out = FileConverter.uniqueURL(for: url, ext: "pdf", in: directory)
        guard doc.write(to: out) else { throw Failure.unwritable }
        return out
    }

    // MARK: - PDF → PNG

    /// Base da rasterização: 2x fica legível numa tela Retina. O preset de
    /// tamanho multiplica isto (2x / 1x / 0,5x).
    static let baseRasterScale: CGFloat = 2

    /// Uma imagem por página. Devolve todas, na ordem; quem chama decide o que
    /// vai pro shelf. `directory` nil = ao lado do original.
    @discardableResult
    static func pngPages(
        fromPDF url: URL,
        scale: CGFloat = baseRasterScale,
        in directory: URL? = nil
    ) throws -> [URL] {
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
                directory: directory ?? url.deletingLastPathComponent(),
                name: name, ext: "png")
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

    static func pdf(fromMarkdown url: URL, in directory: URL? = nil) throws -> URL {
        guard let text = try? String(contentsOf: url, encoding: .utf8), !text.isEmpty else {
            throw Failure.unreadable
        }
        // baseURL: as imagens do markdown vêm em caminho relativo ao próprio arquivo
        let attributed = styled(markdown: text, baseURL: url.deletingLastPathComponent())
        guard attributed.length > 0 else { throw Failure.empty }
        let out = FileConverter.uniqueURL(for: url, ext: "pdf", in: directory)
        try writePDF(attributed, to: out)
        return out
    }

    /// Letter em pontos, com 54pt (0,75") de margem — o padrão de impressão.
    private static let pageSize = CGSize(width: 612, height: 792)
    private static let margin: CGFloat = 54

    /// Pagina com TextKit, não com CoreText: `NSLayoutManager` desenha anexo de
    /// imagem e tab stop de tabela, que o `CTFramesetter` ignorava.
    /// ponytail: TextKit fora da main thread (a conversão roda em background) —
    /// o layout manager é local e não encosta em view nenhuma. Se um dia
    /// reclamar, empurre a chamada pra main queue.
    static func writePDF(_ text: NSAttributedString, to url: URL) throws {
        var mediaBox = CGRect(origin: .zero, size: pageSize)
        guard let ctx = CGContext(url as CFURL, mediaBox: &mediaBox, nil) else {
            throw Failure.unwritable
        }
        let box = mediaBox.insetBy(dx: margin, dy: margin)
        let storage = NSTextStorage(attributedString: text)
        let layout = NSLayoutManager()
        storage.addLayoutManager(layout)

        // um container por página; o layout manager derrama o texto de um pro outro
        var pages: [NSRange] = []
        while true {
            let container = NSTextContainer(size: box.size)
            container.lineFragmentPadding = 0
            layout.addTextContainer(container)
            let range = layout.glyphRange(for: container)
            // nada coube (linha maior que a caixa): sai em vez de girar pra sempre
            guard range.length > 0 else { break }
            pages.append(range)
            if NSMaxRange(range) >= layout.numberOfGlyphs { break }
        }

        for range in pages {
            ctx.beginPDFPage(nil)
            ctx.saveGState()
            ctx.translateBy(x: box.minX, y: box.maxY)   // TextKit desenha de cima pra baixo
            ctx.scaleBy(x: 1, y: -1)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)
            layout.drawBackground(forGlyphRange: range, at: .zero)
            layout.drawGlyphs(forGlyphRange: range, at: .zero)
            NSGraphicsContext.restoreGraphicsState()
            ctx.restoreGState()
            ctx.endPDFPage()
        }
        ctx.closePDF()
    }

    // MARK: - Markdown → NSAttributedString

    private static let body = NSFont.systemFont(ofSize: 11)
    private static let mono = NSFont.monospacedSystemFont(ofSize: 10, weight: .regular)

    /// Interpreta o markdown com o parser do Foundation e traduz cada intenção
    /// de apresentação (cabeçalho, lista, citação, código, tabela) em fonte e recuo.
    /// `baseURL` resolve as imagens em caminho relativo; sem ele, imagem vira o alt.
    static func styled(markdown: String, baseURL: URL? = nil) -> NSAttributedString {
        guard let parsed = try? AttributedString(
            markdown: markdown,
            options: .init(interpretedSyntax: .full,
                           failurePolicy: .returnPartiallyParsedIfPossible))
        else { return NSAttributedString(string: markdown, attributes: [.font: body]) }

        let out = NSMutableAttributedString()
        var currentIntent: PresentationIntent?
        var isFirstBlock = true
        var lastColumn = 0

        for run in parsed.runs {
            let intent = run.presentationIntent
            if intent != currentIntent {
                // célula da mesma linha continua no parágrafo, separada por tab —
                // e o tab conta a coluna, senão célula vazia (que o parser omite)
                // empurraria o resto da linha pra esquerda
                let column = tableCell(intent)
                let sameRow = tableRow(intent) != nil && tableRow(intent) == tableRow(currentIntent)
                if sameRow, let column {
                    out.append(NSAttributedString(string: String(repeating: "\t", count: max(1, column - lastColumn))))
                } else {
                    if !isFirstBlock { out.append(NSAttributedString(string: "\n")) }
                    if let column, column > 0 {
                        out.append(NSAttributedString(string: String(repeating: "\t", count: column)))
                    }
                }
                lastColumn = column ?? 0
                isFirstBlock = false
                currentIntent = intent
                if let prefix = listPrefix(intent) {
                    out.append(NSAttributedString(
                        string: prefix, attributes: [.font: body, .paragraphStyle: style(intent)]))
                }
            }
            // o parser entrega um "⸻" solto pra regra horizontal; repete até a
            // largura da caixa pra virar régua de ponta a ponta
            if isBreak(intent) {
                out.append(NSAttributedString(string: rule, attributes: [
                    .font: body,
                    .paragraphStyle: style(intent),
                    .foregroundColor: quoteGray,
                    .kern: ruleKern,
                ]))
                continue
            }
            // imagem embutida: o parser entrega a URL e o alt como texto do run
            if let src = run.imageURL, let image = loadImage(src, relativeTo: baseURL) {
                out.append(attachment(image))
                continue
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

    private static func isBreak(_ intent: PresentationIntent?) -> Bool {
        kinds(intent).contains {
            if case .thematicBreak = $0 { return true }
            return false
        }
    }

    // MARK: - Tabela

    /// Identidade da linha (header ou corpo) — células com a mesma identidade
    /// pertencem à mesma linha e são separadas por tab, não por quebra.
    private static func tableRow(_ intent: PresentationIntent?) -> Int? {
        intent?.components.first {
            switch $0.kind {
            case .tableRow, .tableHeaderRow: return true
            default: return false
            }
        }?.identity
    }

    private static func isTableHeader(_ intent: PresentationIntent?) -> Bool {
        kinds(intent).contains {
            if case .tableHeaderRow = $0 { return true }
            return false
        }
    }

    /// Índice da coluna desta célula (0-based).
    private static func tableCell(_ intent: PresentationIntent?) -> Int? {
        for kind in kinds(intent) {
            if case .tableCell(let column) = kind { return column }
        }
        return nil
    }

    private static func tableColumns(_ intent: PresentationIntent?) -> [PresentationIntent.TableColumn]? {
        for kind in kinds(intent) {
            if case .table(let columns) = kind { return columns }
        }
        return nil
    }

    /// Tab stop por coluna, dividindo a caixa em partes iguais.
    /// ponytail: largura igual e coluna 0 sempre à esquerda — sem medir conteúdo.
    /// Se tabela desalinhada incomodar, meça a célula mais larga por coluna aqui.
    private static func tableTabs(_ columns: [PresentationIntent.TableColumn]) -> [NSTextTab] {
        let width = (pageSize.width - margin * 2) / CGFloat(max(1, columns.count))
        return columns.indices.dropFirst().map { index in
            let alignment: NSTextAlignment
            switch columns[index].alignment {
            case .center: alignment = .center
            case .right: alignment = .right
            default: alignment = .left
            }
            return NSTextTab(textAlignment: alignment, location: width * CGFloat(index))
        }
    }

    // MARK: - Imagem embutida

    private static func loadImage(_ src: URL, relativeTo base: URL?) -> NSImage? {
        // relativa (o caso comum num .md) resolve contra a pasta do arquivo
        if src.scheme == nil || src.isFileURL {
            let path = src.isFileURL ? src.path : src.relativePath
            let url = path.hasPrefix("/")
                ? URL(fileURLWithPath: path)
                : (base ?? URL(fileURLWithPath: ".")).appendingPathComponent(path)
            return NSImage(contentsOf: url)
        }
        return nil   // ponytail: sem baixar imagem remota — conversão não faz rede
    }

    /// Anexo limitado à largura da caixa, preservando proporção.
    private static func attachment(_ image: NSImage) -> NSAttributedString {
        let maxWidth = pageSize.width - margin * 2
        var size = image.size
        if size.width > maxWidth, size.width > 0 {
            size = CGSize(width: maxWidth, height: size.height * maxWidth / size.width)
        }
        let cell = NSTextAttachment()
        cell.image = image
        cell.bounds = CGRect(origin: .zero, size: size)
        return NSAttributedString(attachment: cell)
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
        if isTableHeader(intent) { return .systemFont(ofSize: 11, weight: .semibold) }
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

    /// Cinza fixo, não `.secondaryLabelColor`: cor dinâmica resolve pela aparência
    /// do sistema e, no modo escuro, a citação saía branca — invisível no PDF.
    private static let quoteGray = NSColor(white: 0.35, alpha: 1)

    /// "⸻" (o traço que o parser usa na regra horizontal) repetido até a caixa.
    /// O `kern` fecha a folga entre um traço e o seguinte — sem ele a régua sai
    /// pontilhada.
    private static let ruleKern: CGFloat = -1
    private static let rule: String = {
        let unit = ("⸻" as NSString).size(withAttributes: [.font: body]).width + ruleKern
        return String(repeating: "⸻", count: max(1, Int((pageSize.width - margin * 2) / unit)))
    }()

    private static func color(_ intent: PresentationIntent?) -> NSColor {
        isQuote(intent) || isBreak(intent) ? quoteGray : .black
    }

    private static func style(_ intent: PresentationIntent?) -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.lineHeightMultiple = 1.18
        style.paragraphSpacing = headerLevel(intent) != nil ? 6 : 10
        if headerLevel(intent) != nil { style.paragraphSpacingBefore = 8 }
        if isBreak(intent) {                      // régua com ar em volta
            style.paragraphSpacing = 14
            style.paragraphSpacingBefore = 8
        }
        if let columns = tableColumns(intent) {   // célula: tab stop por coluna
            style.tabStops = tableTabs(columns)
            style.defaultTabInterval = (pageSize.width - margin * 2) / CGFloat(max(1, columns.count))
            style.paragraphSpacing = isTableHeader(intent) ? 4 : 2
            style.lineBreakMode = .byTruncatingTail   // célula longa não empurra a coluna
        }
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
