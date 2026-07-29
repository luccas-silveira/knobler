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

    /// Único preset usado fora do passthrough. Os `…MediumQuality` e
    /// `…LowQuality` ficaram de fora de propósito: cada um impõe um teto de
    /// resolução próprio, que se multiplica com o `renderSize` da composição e
    /// faria o preset de tamanho mentir (medido: um 1080x1920 pedido em 50%
    /// saía 320x568 no Medium, e não 540x960). Só este respeita o `renderSize`.
    static let qualityPreset = AVAssetExportPresetHighestQuality

    /// Exporta em background. `progress` é chamado no main enquanto roda
    /// (0…1) e `completion` no main no fim. Devolve a sessão pra quem quiser
    /// cancelar (o preview cancela ao trocar de preset).
    @discardableResult
    static func convert(
        _ url: URL,
        to type: UTType,
        options: ConversionOptions = .padrao,
        in directory: URL? = nil,
        progress: @escaping (Double) -> Void,
        completion: @escaping (Result<URL, Error>) -> Void
    ) -> AVAssetExportSession? {
        let asset = AVURLAsset(url: url)
        let target = fileType(for: type)
        // passthrough só serve se o contêiner de destino aceitar as trilhas como
        // estão — e se nada for reescrito. Reescalar reescreve, então o remux
        // instantâneo só sobra em 100%.
        let session: AVAssetExportSession?
        if options.scale == .full,
           let pass = AVAssetExportSession(
            asset: asset, presetName: AVAssetExportPresetPassthrough),
            pass.supportedFileTypes.contains(target) {
            session = pass
        } else {
            session = AVAssetExportSession(asset: asset, presetName: qualityPreset)
        }
        guard let session, session.supportedFileTypes.contains(target) else {
            completion(.failure(Failure.unsupported))
            return nil
        }

        let ext = type.preferredFilenameExtension ?? "mp4"
        let out = FileConverter.uniqueURL(for: url, ext: ext, in: directory)
        session.outputURL = out
        session.outputFileType = target
        if options.scale != .full {
            // AVAssetExportSession não aceita resolução por parâmetro: os presets
            // de dimensão (…1280x720) amarram bitrate junto e colidiriam com o
            // eixo de qualidade. A composição é o único jeito de mexer só no
            // tamanho.
            session.videoComposition = scaledComposition(asset, by: options.scale.factor)
        }

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
        return session
    }

    /// Composição que só reescala: mesma duração, mesmas trilhas, `renderSize`
    /// menor e a transformação da trilha multiplicada pelo fator.
    /// ponytail: API síncrona de `tracks`/`duration` (deprecada no macOS 15, viva
    /// no 14.2 que é o target). A assíncrona obrigaria a espalhar `await` por
    /// todo o caminho de conversão pra ganhar nada aqui.
    static func scaledComposition(_ asset: AVAsset, by factor: CGFloat) -> AVVideoComposition? {
        guard let track = asset.tracks(withMediaType: .video).first else { return nil }
        // a trilha guarda a rotação no preferredTransform: o tamanho que o
        // usuário vê é o natural já girado, e é esse que a escala multiplica
        let rotated = track.naturalSize.applying(track.preferredTransform)
        let size = ConversionOptions.evenSize(CGSize(
            width: abs(rotated.width) * factor,
            height: abs(rotated.height) * factor))

        let composition = AVMutableVideoComposition()
        composition.renderSize = size
        // sem frameDuration o export não sai; 30 fps é o palpite quando a trilha
        // não declara taxa (vídeo de taxa variável)
        let fps = track.nominalFrameRate > 0 ? track.nominalFrameRate.rounded() : 30
        composition.frameDuration = CMTime(value: 1, timescale: CMTimeScale(fps))

        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = CMTimeRange(start: .zero, duration: asset.duration)
        let layer = AVMutableVideoCompositionLayerInstruction(assetTrack: track)
        // a escala vem depois da rotação: girar o quadro já encolhido colocaria
        // a imagem fora do renderSize
        layer.setTransform(
            track.preferredTransform.concatenating(
                CGAffineTransform(scaleX: factor, y: factor)),
            at: .zero)
        instruction.layerInstructions = [layer]
        composition.instructions = [instruction]
        return composition
    }
}
