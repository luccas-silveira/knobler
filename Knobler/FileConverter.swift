//
//  FileConverter.swift
//  Knobler
//
//  Ponto único do menu de contexto do shelf: o que dá pra converter neste
//  arquivo e como. Imagem/documento rodam numa fila de fundo; vídeo tem export
//  próprio (assíncrono) com progresso.
//

import Foundation
import UniformTypeIdentifiers

/// Os dois eixos que o card de preview oferece. Cada conversor traduz os presets
/// pro que eles significam no seu formato — só ele sabe.
struct ConversionOptions: Equatable {
    enum Quality: CaseIterable {
        case alta, media, baixa

        var label: String {
            switch self {
            case .alta: return "Alta"
            case .media: return "Média"
            case .baixa: return "Baixa"
            }
        }

        /// `kCGImageDestinationLossyCompressionQuality`. PNG ignora (lossless).
        var lossyCompression: Double {
            switch self {
            case .alta: return 0.9
            case .media: return 0.7
            case .baixa: return 0.5
            }
        }
    }

    enum Scale: CaseIterable {
        case full, half, quarter

        var label: String {
            switch self {
            case .full: return "100%"
            case .half: return "50%"
            case .quarter: return "25%"
            }
        }

        var factor: CGFloat {
            switch self {
            case .full: return 1
            case .half: return 0.5
            case .quarter: return 0.25
            }
        }
    }

    var quality: Quality = .alta
    var scale: Scale = .full

    static let padrao = ConversionOptions()

    /// Dimensão ímpar quebra o encoder H.264 — e uma dimensão zero não existe.
    static func evenSize(_ size: CGSize) -> CGSize {
        func even(_ value: CGFloat) -> CGFloat {
            max(2, (value / 2).rounded() * 2)
        }
        return CGSize(width: even(size.width), height: even(size.height))
    }
}

enum ConversionTarget: Hashable {
    case image(UTType)     // imagem → PNG / JPEG / HEIC
    case pdf               // imagem ou markdown → PDF
    case pngPages          // PDF → PNG, uma por página
    case video(UTType)     // vídeo → MP4 / M4V

    var label: String {
        switch self {
        case .image(let type): return ImageConverter.label(for: type)
        case .pdf: return "PDF"
        case .pngPages: return "PNG (páginas)"
        case .video(let type): return VideoConverter.label(for: type)
        }
    }

    /// Só o vídeo demora a ponto de valer barra de progresso.
    var isSlow: Bool {
        if case .video = self { return true }
        return false
    }

    /// PNG e PDF são lossless — o card esconde a linha de qualidade neles.
    /// Vídeo também não a oferece, por um motivo diferente: `AVAssetExportSession`
    /// não expõe bitrate, e os presets Medium/Low que o exporiam carregam teto de
    /// resolução próprio — o "50%" do outro eixo passaria a mentir. Só o
    /// HighestQuality respeita o `renderSize` na vírgula, então é o que fica.
    var usaQualidade: Bool {
        switch self {
        case .image(let type): return type != .png
        case .pdf, .pngPages, .video: return false
        }
    }

    /// PDF sai vetorial (de markdown) ou no tamanho da imagem de origem: escalar
    /// não muda nada. Nos outros muda.
    var usaEscala: Bool {
        switch self {
        case .image, .pngPages, .video: return true
        case .pdf: return false
        }
    }
}

enum FileConverter {
    /// O menu de contexto pergunta isto. Vazio = arquivo sem conversão útil.
    static func targets(for url: URL) -> [ConversionTarget] {
        if DocumentConverter.isPDF(url) { return [.pngPages] }
        if DocumentConverter.isMarkdown(url) { return [.pdf] }
        if VideoConverter.isVideo(url) {
            return VideoConverter.targets
                .filter { !VideoConverter.isAlready(url, $0) }
                .map { .video($0) }
        }
        if ImageConverter.isImage(url) {
            return ImageConverter.targets
                .filter { !ImageConverter.isAlready(url, $0) }
                .map { ConversionTarget.image($0) } + [.pdf]
        }
        return []
    }

    /// Converte fora da main e responde na main. `progress` só é chamado no
    /// caminho de vídeo.
    /// O resultado traz **todos** os arquivos escritos, na ordem: só o PDF→PNG
    /// passa de um. Quem chama decide o que vai pro shelf.
    /// `cancel` só é devolvido no caminho de vídeo — os outros terminam rápido
    /// demais pra valer a pena interromper.
    @discardableResult
    static func convert(
        _ url: URL,
        to target: ConversionTarget,
        options: ConversionOptions = .padrao,
        in directory: URL? = nil,
        progress: @escaping (Double) -> Void = { _ in },
        completion: @escaping (Result<[URL], Error>) -> Void
    ) -> (() -> Void)? {
        if case .video(let type) = target {
            let session = VideoConverter.convert(
                url, to: type, options: options, in: directory, progress: progress
            ) { completion($0.map { [$0] }) }
            return session.map { session in { session.cancelExport() } }
        }
        DispatchQueue.global(qos: .userInitiated).async {
            let result = Result {
                switch target {
                case .image(let type):
                    return [try ImageConverter.convert(
                        url, to: type, options: options, in: directory)]
                case .pdf:
                    return [DocumentConverter.isMarkdown(url)
                        ? try DocumentConverter.pdf(fromMarkdown: url, in: directory)
                        : try DocumentConverter.pdf(fromImage: url, in: directory)]
                case .pngPages:
                    return try DocumentConverter.pngPages(
                        fromPDF: url,
                        scale: DocumentConverter.baseRasterScale * options.scale.factor,
                        in: directory)
                case .video:
                    fatalError("vídeo já foi tratado acima")
                }
            }
            DispatchQueue.main.async { completion(result) }
        }
        return nil
    }

    // MARK: - Nome do arquivo de saída

    /// `foto.png`, senão `foto-1.png`, `foto-2.png`… Nunca sobrescreve o
    /// vizinho: converter JPEG→PNG numa pasta que já tem `foto.png` apagaria o
    /// outro arquivo.
    static func uniqueURL(
        directory: URL, name: String, ext: String,
        exists: (URL) -> Bool = { FileManager.default.fileExists(atPath: $0.path) }
    ) -> URL {
        let candidate = directory.appendingPathComponent("\(name).\(ext)")
        guard exists(candidate) else { return candidate }
        for n in 1... {
            let next = directory.appendingPathComponent("\(name)-\(n).\(ext)")
            if !exists(next) { return next }
        }
        return candidate  // inalcançável: o laço só sai retornando
    }

    /// Mesmo nome do original, extensão nova. `directory` nil = mesma pasta do
    /// original; o preview passa a pasta temporária dele.
    static func uniqueURL(for url: URL, ext: String, in directory: URL? = nil) -> URL {
        uniqueURL(
            directory: directory ?? url.deletingLastPathComponent(),
            name: url.deletingPathExtension().lastPathComponent,
            ext: ext)
    }
}
