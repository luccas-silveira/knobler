//
//  MediaController.swift
//  Knobler
//
//  Now Playing universal (qualquer app que apareça no Control Center) via
//  MediaRemoteSource — push pelo stream do mediaremote-adapter, sem polling.
//

import AppKit
import Combine
import SwiftUI

final class MediaController: ObservableObject {
    struct PlaybackState {
        var isPlaying: Bool
        var title: String
        var artist: String
        var album: String
        var duration: TimeInterval
        var position: TimeInterval
        var fetchedAt: Date
        var artworkURL: String?
        var shuffling = false
        /// Velocidade de reprodução (podcast a 1,5× etc.) — extrapola a posição.
        var rate: Double = 1
        /// A fonte reporta shuffle? (navegador não) — apaga o botão no card.
        var shuffleAvailable = true
    }

    @Published private(set) var state: PlaybackState?
    @Published private(set) var artwork: NSImage? {
        didSet { artworkTint = artwork.flatMap(Self.vibrantTint) }
    }
    /// Cor vibrante dominante da capa — tinge o visualizador como no iPhone.
    @Published private(set) var artworkTint: Color?
    /// Bundle ID do app dono do som (pro tap de áudio saber quem capturar).
    private(set) var activeBundleID: String?

    private let source = MediaRemoteSource()
    private var lastTrackKey: String?
    private var lastArtworkData: String?

    init() {
        source.onUpdate = { [weak self] in self?.apply($0) }
        source.start()
    }

    deinit { source.stop() }

    /// Usado pelo harness de renderização offline (verificação visual pré-entrega).
    func injectPreview(state: PlaybackState?, artwork: NSImage?) {
        self.state = state
        self.artwork = artwork
    }

    // MARK: - Comandos

    func playPause() { source.send(.togglePlayPause) }
    func nextTrack() { source.send(.nextTrack) }
    func previousTrack() { source.send(.previousTrack) }
    func toggleShuffle() { source.send(.toggleShuffle) }

    /// Posição estimada agora, sem refetch: última posição + decorrido × rate.
    func currentPosition(at date: Date = Date()) -> TimeInterval {
        guard let s = state else { return 0 }
        guard s.isPlaying else { return s.position }
        let position = s.position + date.timeIntervalSince(s.fetchedAt) * s.rate
        guard s.duration > 0 else { return position }   // live: duração desconhecida
        return min(s.duration, position)
    }

    // MARK: - Estado

    private func apply(_ now: MediaRemoteSource.NowPlaying?) {
        guard let now, let title = now.title else {
            state = nil
            activeBundleID = nil
            artwork = nil
            lastTrackKey = nil
            lastArtworkData = nil
            return
        }
        // Aba de navegador: o cliente MediaRemote é o processo WebKit; o app
        // visível (e dono do som, pro tap) é o pai.
        activeBundleID = now.parentBundleIdentifier ?? now.bundleIdentifier
        let rate = now.playbackRate ?? 1
        state = PlaybackState(
            isPlaying: now.playing,
            title: title,
            artist: now.artist ?? "",
            album: now.album ?? "",
            duration: now.duration ?? 0,
            position: now.elapsedTime ?? 0,
            fetchedAt: Date(),
            artworkURL: nil,
            shuffling: (now.shuffleMode ?? 1) > 1,
            rate: rate > 0 ? rate : 1,
            shuffleAvailable: now.shuffleMode != nil
        )
        // A capa chega em base64 no próprio stream — às vezes atrasada em
        // relação aos metadados: o card renderiza sem capa e atualiza depois.
        let trackKey = "\(title)|\(now.artist ?? "")|\(now.album ?? "")"
        if trackKey != lastTrackKey {
            lastTrackKey = trackKey
            if now.artworkData == nil {   // capa da faixa anterior não vale mais
                artwork = nil
                lastArtworkData = nil
            }
        }
        if let data = now.artworkData, data != lastArtworkData {
            lastArtworkData = data
            artwork = Data(base64Encoded: data).flatMap(NSImage.init(data:))
        }
    }

    // MARK: - Artwork

    /// Cor vibrante dominante da capa (não a média — média de capa colorida
    /// vira marrom). Histograma de matiz em 12 baldes, cada pixel pesando
    /// saturação×brilho; pixels acinzentados/escuros ficam de fora.
    private static func vibrantTint(_ image: NSImage) -> Color? {
        let side = 16
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: side * 4, bitsPerPixel: 32
        ) else { return nil }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        image.draw(in: NSRect(x: 0, y: 0, width: side, height: side))
        NSGraphicsContext.restoreGraphicsState()

        let buckets = 12
        var weight = [CGFloat](repeating: 0, count: buckets)
        var hueSum = [CGFloat](repeating: 0, count: buckets)
        var satSum = [CGFloat](repeating: 0, count: buckets)
        var briSum = [CGFloat](repeating: 0, count: buckets)

        for y in 0..<side {
            for x in 0..<side {
                guard let color = rep.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB)
                else { continue }
                let saturation = color.saturationComponent
                let brightness = color.brightnessComponent
                guard saturation > 0.15, brightness > 0.2 else { continue }
                let pixelWeight = saturation * brightness
                let bucket = min(buckets - 1, Int(color.hueComponent * CGFloat(buckets)))
                weight[bucket] += pixelWeight
                hueSum[bucket] += color.hueComponent * pixelWeight
                satSum[bucket] += saturation * pixelWeight
                briSum[bucket] += brightness * pixelWeight
            }
        }

        guard let best = weight.indices.max(by: { weight[$0] < weight[$1] }),
              weight[best] > 1.5 // capa essencialmente P&B/cinza → barras brancas
        else { return nil }

        let total = weight[best]
        return Color(nsColor: NSColor(
            hue: hueSum[best] / total,
            saturation: max(0.5, satSum[best] / total),
            brightness: max(0.9, briSum[best] / total),
            alpha: 1
        ))
    }
}
