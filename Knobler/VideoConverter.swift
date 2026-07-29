//
//  VideoConverter.swift
//  Knobler
//
//  Vídeo pra MP4/M4V via AVAssetExportSession. Tenta passthrough primeiro
//  (remux instantâneo, sem perder qualidade); se o codec não couber no
//  contêiner, recodifica.
//

import AVFoundation
import Foundation
import UniformTypeIdentifiers

enum VideoConverter {
    /// Destinos oferecidos no menu.
    static let targets: [UTType] = [.mpeg4Movie, .quickTimeMovie]

    enum Failure: Error {
        case unsupported          // nenhum preset consegue escrever esse destino
        case export(String)       // o export falhou (mensagem do AVFoundation)
    }

    static func isVideo(_ url: URL) -> Bool {
        UTType(filenameExtension: url.pathExtension)?.conforms(to: .movie) ?? false
    }

    static func label(for type: UTType) -> String {
        type == .quickTimeMovie ? "MOV" : "MP4"
    }

    static func isAlready(_ url: URL, _ type: UTType) -> Bool {
        UTType(filenameExtension: url.pathExtension) == type
    }

    private static func fileType(for type: UTType) -> AVFileType {
        type == .quickTimeMovie ? .mov : .mp4
    }

    /// Exporta em background. `progress` é chamado no main enquanto roda
    /// (0…1) e `completion` no main no fim.
    static func convert(
        _ url: URL,
        to type: UTType,
        progress: @escaping (Double) -> Void,
        completion: @escaping (Result<URL, Error>) -> Void
    ) {
        let asset = AVURLAsset(url: url)
        let target = fileType(for: type)
        // passthrough só serve se o contêiner de destino aceitar as trilhas como
        // estão; senão volta pro preset que recodifica.
        let session: AVAssetExportSession?
        if let pass = AVAssetExportSession(
            asset: asset, presetName: AVAssetExportPresetPassthrough),
            pass.supportedFileTypes.contains(target) {
            session = pass
        } else {
            session = AVAssetExportSession(
                asset: asset, presetName: AVAssetExportPresetHighestQuality)
        }
        guard let session, session.supportedFileTypes.contains(target) else {
            completion(.failure(Failure.unsupported))
            return
        }

        let ext = type.preferredFilenameExtension ?? "mp4"
        let out = FileConverter.uniqueURL(for: url, ext: ext)
        session.outputURL = out
        session.outputFileType = target

        // AVAssetExportSession não avisa progresso — o jeito é perguntar.
        let ticker = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: true) { _ in
            progress(Double(session.progress))
        }
        session.exportAsynchronously {
            DispatchQueue.main.async {
                ticker.invalidate()
                switch session.status {
                case .completed:
                    completion(.success(out))
                case .cancelled:
                    try? FileManager.default.removeItem(at: out)
                    completion(.failure(Failure.export("cancelado")))
                default:
                    // export abortado deixa arquivo pela metade — não pode ir pro shelf
                    try? FileManager.default.removeItem(at: out)
                    completion(.failure(Failure.export(
                        session.error?.localizedDescription ?? "falha desconhecida")))
                }
            }
        }
    }
}
