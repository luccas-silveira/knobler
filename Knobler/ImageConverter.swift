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

    /// `directory` nil = ao lado do original (o caminho de sempre). O preview
    /// passa uma pasta temporária pra não sujar o disco antes de confirmar.
    @discardableResult
    static func convert(
        _ url: URL, to type: UTType,
        options: ConversionOptions = .padrao,
        in directory: URL? = nil
    ) throws -> URL {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              var image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else { throw Failure.unreadable }

        if options.scale != .full {
            image = try resize(image, by: options.scale.factor)
        }

        guard let ext = type.preferredFilenameExtension else { throw Failure.unwritable }
        let out = directory.map {
            FileConverter.uniqueURL(
                directory: $0,
                name: url.deletingPathExtension().lastPathComponent,
                ext: ext)
        } ?? FileConverter.uniqueURL(for: url, ext: ext)

        guard let dest = CGImageDestinationCreateWithURL(
            out as CFURL, type.identifier as CFString, 1, nil)
        else { throw Failure.unwritable }
        // PNG ignora a compressão (lossless); JPEG/HEIC é onde o preset pesa
        CGImageDestinationAddImage(dest, image, [
            kCGImageDestinationLossyCompressionQuality: options.quality.lossyCompression,
        ] as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { throw Failure.unwritable }
        return out
    }

    /// Redesenha num contexto menor — o ImageIO não reescala na escrita.
    private static func resize(_ image: CGImage, by factor: CGFloat) throws -> CGImage {
        let size = ConversionOptions.evenSize(CGSize(
            width: CGFloat(image.width) * factor,
            height: CGFloat(image.height) * factor))
        // o espaço/bitmap do original pode ser exótico (CMYK, 16 bits): força RGBA
        guard let ctx = CGContext(
            data: nil, width: Int(size.width), height: Int(size.height),
            bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { throw Failure.unwritable }
        ctx.interpolationQuality = .high
        ctx.draw(image, in: CGRect(origin: .zero, size: size))
        guard let scaled = ctx.makeImage() else { throw Failure.unwritable }
        return scaled
    }
}
