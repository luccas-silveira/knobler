//
//  ShelfPreview.swift
//  Knobler
//
//  Conversão do shelf com preview: converte pra uma pasta temporária, mostra o
//  resultado no card e só move pro destino final quando o usuário confirma.
//  Antes disso a conversão gravava direto ao lado do original — às cegas e sem
//  volta.
//

import AVFoundation
import AppKit
import Combine
import ImageIO

@MainActor
final class ShelfPreview: ObservableObject {
    let source: URL
    let target: ConversionTarget

    @Published var options: ConversionOptions = .padrao {
        didSet { if options != oldValue { converter() } }
    }
    /// Primeiro arquivo escrito — é ele que a miniatura mostra.
    @Published private(set) var output: URL?
    @Published private(set) var outputBytes: Int64?
    @Published private(set) var outputPixelSize: CGSize?
    /// Páginas além da primeira (só PDF→PNG passa de uma).
    @Published private(set) var extraPages = 0
    @Published private(set) var running = false
    @Published private(set) var progress: Double = 0
    @Published private(set) var failed = false

    let sourceBytes: Int64?

    /// Cada preview tem a própria pasta: descartar é apagar a pasta inteira, sem
    /// caçar arquivo por arquivo (o PDF→PNG escreve N).
    private let workDirectory: URL
    private var written: [URL] = []
    private var cancelCurrent: (() -> Void)?
    /// Reconversão em voo cujo resultado não interessa mais: o cancelamento do
    /// AVAssetExportSession não é instantâneo, e sem isto a resposta atrasada da
    /// conversão anterior sobrescreveria a nova.
    private var generation = 0

    init(source: URL, target: ConversionTarget) {
        self.source = source
        self.target = target
        self.sourceBytes = Self.bytes(of: source)
        self.workDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("knobler-preview-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(
            at: workDirectory, withIntermediateDirectories: true)
        converter()
    }

    // MARK: - Conversão

    private func converter() {
        cancelCurrent?()
        generation += 1
        let mine = generation
        limparEscritos()
        running = true
        failed = false
        progress = 0

        cancelCurrent = FileConverter.convert(
            source, to: target, options: options, in: workDirectory
        ) { [weak self] fraction in
            guard let self, mine == self.generation else { return }
            self.progress = fraction
        } completion: { [weak self] result in
            guard let self, mine == self.generation else { return }
            self.running = false
            self.cancelCurrent = nil
            switch result {
            case .success(let urls):
                self.written = urls
                self.output = urls.first
                self.extraPages = max(0, urls.count - 1)
                self.outputBytes = urls.first.flatMap(Self.bytes(of:))
                self.outputPixelSize = urls.first.flatMap(Self.pixelSize(of:))
            case .failure(let error):
                NSLog("knobler: preview de conversão falhou (\(self.source.lastPathComponent)): \(error)")
                self.failed = true
                self.output = nil
                self.outputBytes = nil
                self.outputPixelSize = nil
                self.extraPages = 0
            }
        }
    }

    // MARK: - Desfecho

    /// Move os arquivos pro lado do original e devolve o primeiro. O original
    /// continua onde estava.
    @discardableResult
    func salvar() -> [URL] {
        guard !written.isEmpty else { return [] }
        var saved: [URL] = []
        for url in written {
            let destination = FileConverter.uniqueURL(
                directory: source.deletingLastPathComponent(),
                name: url.deletingPathExtension().lastPathComponent,
                ext: url.pathExtension)
            do {
                try FileManager.default.moveItem(at: url, to: destination)
                saved.append(destination)
            } catch {
                NSLog("knobler: preview não conseguiu salvar \(url.lastPathComponent): \(error)")
            }
        }
        written = []
        descartar()
        return saved
    }

    /// Cancela o que estiver rodando e apaga a pasta de trabalho inteira.
    func descartar() {
        cancelCurrent?()
        cancelCurrent = nil
        generation += 1
        try? FileManager.default.removeItem(at: workDirectory)
    }

    private func limparEscritos() {
        for url in written {
            try? FileManager.default.removeItem(at: url)
        }
        written = []
        output = nil
        outputBytes = nil
        outputPixelSize = nil
        extraPages = 0
    }

    // MARK: - Leitura de arquivo

    static func bytes(of url: URL) -> Int64? {
        (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).flatMap { $0 }
            .map(Int64.init)
    }

    /// Dimensão em pixels sem decodificar a imagem inteira. Vídeo pergunta à
    /// trilha; PDF não tem resposta em pixel.
    static func pixelSize(of url: URL) -> CGSize? {
        if VideoConverter.isVideo(url) {
            guard let track = AVURLAsset(url: url).tracks(withMediaType: .video).first
            else { return nil }
            let rotated = track.naturalSize.applying(track.preferredTransform)
            return CGSize(width: abs(rotated.width), height: abs(rotated.height))
        }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = props[kCGImagePropertyPixelWidth] as? CGFloat,
              let height = props[kCGImagePropertyPixelHeight] as? CGFloat
        else { return nil }
        return CGSize(width: width, height: height)
    }

    /// Miniatura do resultado. Deliberadamente sem `QLThumbnailGenerator` e sem
    /// `NSWorkspace.icon`: os dois precisam de uma janela viva e viram o ícone de
    /// "proibido" no `ImageRenderer` offscreen do harness de snapshot.
    static func thumbnail(of url: URL) -> NSImage? {
        if VideoConverter.isVideo(url) {
            let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
            generator.appliesPreferredTrackTransform = true
            // primeiro segundo: o frame zero costuma ser preto
            let time = CMTime(seconds: 1, preferredTimescale: 600)
            guard let cg = try? generator.copyCGImage(at: time, actualTime: nil) else {
                return nil
            }
            return NSImage(cgImage: cg, size: .zero)
        }
        return NSImage(contentsOf: url)
    }

    static func formatBytes(_ bytes: Int64?) -> String {
        guard let bytes else { return "—" }
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
