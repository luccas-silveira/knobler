//
//  ImageConverter.swift
//  Knobler
//
//  Converte imagem do shelf pra outro formato via ImageIO. O arquivo novo nasce
//  ao lado do original (nunca sobrescreve) e volta pro shelf.
//  ponytail: só imagem — vídeo/PDF pediriam AVFoundation/PDFKit e outro fluxo.
//

import Foundation
import ImageIO
import UniformTypeIdentifiers

enum ImageConverter {
    /// Destinos oferecidos no menu. Ordem = ordem do menu.
    static let targets: [UTType] = [.png, .jpeg, .heic]

    enum Failure: Error {
        case unreadable      // não é imagem que o ImageIO abra
        case unwritable      // destino não suportado ou disco recusou
    }

    /// A extensão do arquivo mente às vezes (`.jpg` num PNG), mas pro menu ela
    /// basta: quem decide de verdade é o CGImageSource na hora de converter.
    static func isImage(_ url: URL) -> Bool {
        UTType(filenameExtension: url.pathExtension)?.conforms(to: .image) ?? false
    }

    static func label(for type: UTType) -> String {
        switch type {
        case .png: return "PNG"
        case .jpeg: return "JPEG"
        case .heic: return "HEIC"
        default: return type.preferredFilenameExtension?.uppercased() ?? "?"
        }
    }

    /// Já está nesse formato? Some do menu — converter PNG pra PNG é ruído.
    static func isAlready(_ url: URL, _ type: UTType) -> Bool {
        UTType(filenameExtension: url.pathExtension) == type
    }

    @discardableResult
    static func convert(_ url: URL, to type: UTType) throws -> URL {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else { throw Failure.unreadable }

        guard let ext = type.preferredFilenameExtension else { throw Failure.unwritable }
        let out = FileConverter.uniqueURL(for: url, ext: ext)

        guard let dest = CGImageDestinationCreateWithURL(
            out as CFURL, type.identifier as CFString, 1, nil)
        else { throw Failure.unwritable }
        // 0.9 é o joelho da curva tamanho/qualidade; PNG ignora (lossless)
        CGImageDestinationAddImage(dest, image, [
            kCGImageDestinationLossyCompressionQuality: 0.9,
        ] as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { throw Failure.unwritable }
        return out
    }
}
