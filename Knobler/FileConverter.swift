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
    static func convert(
        _ url: URL,
        to target: ConversionTarget,
        progress: @escaping (Double) -> Void = { _ in },
        completion: @escaping (Result<URL, Error>) -> Void
    ) {
        if case .video(let type) = target {
            VideoConverter.convert(url, to: type, progress: progress, completion: completion)
            return
        }
        DispatchQueue.global(qos: .userInitiated).async {
            let result = Result {
                switch target {
                case .image(let type):
                    return try ImageConverter.convert(url, to: type)
                case .pdf:
                    return DocumentConverter.isMarkdown(url)
                        ? try DocumentConverter.pdf(fromMarkdown: url)
                        : try DocumentConverter.pdf(fromImage: url)
                case .pngPages:
                    // as demais páginas ficam no disco ao lado; só a primeira
                    // volta pro shelf pra não estourar a prateleira
                    return try DocumentConverter.pngPages(fromPDF: url)[0]
                case .video:
                    fatalError("vídeo já foi tratado acima")
                }
            }
            DispatchQueue.main.async { completion(result) }
        }
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

    /// Mesmo nome do original, extensão nova, na mesma pasta.
    static func uniqueURL(for url: URL, ext: String) -> URL {
        uniqueURL(
            directory: url.deletingLastPathComponent(),
            name: url.deletingPathExtension().lastPathComponent,
            ext: ext)
    }
}
