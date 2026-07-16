//
//  MediaController.swift
//  Knobler
//
//  Now Playing do Spotify e do Apple Music via AppleScript, atualizado por
//  push (DistributedNotificationCenter) — sem polling contínuo. Se os dois
//  estiverem abertos, quem está tocando ganha.
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
    }

    private struct Player {
        let bundleID: String
        let scriptName: String
        let notificationName: String
        let durationInMilliseconds: Bool
        let hasArtworkURL: Bool
        /// Nome da propriedade de shuffle no dicionário AppleScript do player.
        let shuffleProperty: String
    }

    private static let players = [
        Player(
            bundleID: "com.spotify.client", scriptName: "Spotify",
            notificationName: "com.spotify.client.PlaybackStateChanged",
            durationInMilliseconds: true, hasArtworkURL: true,
            shuffleProperty: "shuffling"),
        Player(
            bundleID: "com.apple.Music", scriptName: "Music",
            notificationName: "com.apple.Music.playerInfo",
            durationInMilliseconds: false, hasArtworkURL: false,
            shuffleProperty: "shuffle enabled"),
    ]

    @Published private(set) var state: PlaybackState?
    @Published private(set) var artwork: NSImage? {
        didSet { artworkTint = artwork.flatMap(Self.vibrantTint) }
    }
    /// Cor vibrante dominante da capa — tinge o visualizador como no iPhone.
    @Published private(set) var artworkTint: Color?
    /// Bundle ID do player ativo (pro tap de áudio saber quem capturar).
    private(set) var activeBundleID: String?

    private var activePlayer: Player?
    private var compiledScripts: [String: NSAppleScript] = [:]
    private var lastArtworkKey: String?

    init() {
        for player in Self.players {
            DistributedNotificationCenter.default().addObserver(
                self,
                selector: #selector(playbackChanged),
                name: Notification.Name(player.notificationName),
                object: nil
            )
        }
        refresh()
    }

    deinit {
        DistributedNotificationCenter.default().removeObserver(self)
    }

    /// Usado pelo harness de renderização offline (verificação visual pré-entrega).
    func injectPreview(state: PlaybackState?, artwork: NSImage?) {
        self.state = state
        self.artwork = artwork
    }

    // MARK: - Comandos

    func playPause() { command("playpause") }
    func nextTrack() { command("next track") }
    func previousTrack() { command("previous track") }

    func toggleShuffle() {
        guard let player = activePlayer else { return }
        command("set \(player.shuffleProperty) to not \(player.shuffleProperty)")
    }

    /// Posição estimada agora, sem refetch: posição do último fetch + tempo decorrido.
    func currentPosition(at date: Date = Date()) -> TimeInterval {
        guard let s = state else { return 0 }
        guard s.isPlaying else { return s.position }
        return min(s.duration, s.position + date.timeIntervalSince(s.fetchedAt))
    }

    // MARK: - Estado

    @objc private func playbackChanged() {
        refresh()
    }

    func refresh() {
        // player ativo: entre os abertos, o que estiver tocando ganha;
        // nenhum tocando → o primeiro aberto com faixa carregada
        var chosen: (Player, PlaybackState)?
        for player in Self.players where isRunning(player) {
            guard let fetched = fetchState(of: player) else { continue }
            if fetched.isPlaying {
                chosen = (player, fetched)
                break
            }
            if chosen == nil { chosen = (player, fetched) }
        }

        guard let (player, newState) = chosen else {
            activePlayer = nil
            activeBundleID = nil
            state = nil
            return
        }
        activePlayer = player
        activeBundleID = player.bundleID
        state = newState
        fetchArtworkIfNeeded(player: player, state: newState)
    }

    private func fetchState(of player: Player) -> PlaybackState? {
        let source = """
        tell application "\(player.scriptName)"
            if player state is stopped then return "stopped"
            set t to current track
            set artURL to ""
            \(player.hasArtworkURL ? "set artURL to artwork url of t" : "")
            return (player state as string) & "\\n" & name of t & "\\n" & artist of t \
                & "\\n" & album of t & "\\n" & player position & "\\n" & duration of t \
                & "\\n" & artURL & "\\n" & \(player.shuffleProperty)
        end tell
        """

        guard let output = run(source), output != "stopped" else { return nil }
        let parts = output.components(separatedBy: "\n")
        guard parts.count >= 8 else { return nil }

        let rawDuration = Self.number(parts[5]) ?? 0
        return PlaybackState(
            isPlaying: parts[0] == "playing",
            title: parts[1],
            artist: parts[2],
            album: parts[3],
            duration: player.durationInMilliseconds ? rawDuration / 1000 : rawDuration,
            position: Self.number(parts[4]) ?? 0,
            fetchedAt: Date(),
            artworkURL: parts[6].isEmpty ? nil : parts[6],
            shuffling: parts[7] == "true"
        )
    }

    // MARK: - Privados

    private func isRunning(_ player: Player) -> Bool {
        // "tell application" abriria o app se não estiver rodando — guarda antes.
        NSWorkspace.shared.runningApplications.contains {
            $0.bundleIdentifier == player.bundleID
        }
    }

    private func command(_ verb: String) {
        guard let player = activePlayer, isRunning(player) else { return }
        _ = run("tell application \"\(player.scriptName)\" to \(verb)")
        // o player emite a notificação na sequência, mas o refetch curto
        // deixa a UI instantânea
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.refresh()
        }
    }

    private func run(_ source: String) -> String? {
        let script: NSAppleScript
        if let cached = compiledScripts[source] {
            script = cached
        } else {
            guard let fresh = NSAppleScript(source: source) else { return nil }
            compiledScripts[source] = fresh
            script = fresh
        }
        var error: NSDictionary?
        let descriptor = script.executeAndReturnError(&error)
        guard error == nil else { return nil }
        return descriptor.stringValue
    }

    /// AppleScript coage real → string com separador decimal do locale (vírgula em pt-BR).
    private static func number(_ raw: String) -> Double? {
        Double(raw.replacingOccurrences(of: ",", with: "."))
    }

    // MARK: - Artwork

    private func fetchArtworkIfNeeded(player: Player, state: PlaybackState) {
        if player.hasArtworkURL {
            // Spotify: URL http da capa
            guard let urlString = state.artworkURL, urlString != lastArtworkKey,
                  let url = URL(string: urlString) else { return }
            lastArtworkKey = urlString
            URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
                guard let data, let image = NSImage(data: data) else { return }
                DispatchQueue.main.async { self?.artwork = image }
            }.resume()
        } else {
            // Apple Music: bytes crus do artwork via AppleScript (só na troca de faixa)
            let key = "\(state.title)|\(state.artist)|\(state.album)"
            guard key != lastArtworkKey else { return }
            lastArtworkKey = key
            let source = "tell application \"Music\" to get data of artwork 1 of current track"
            var error: NSDictionary?
            let descriptor = NSAppleScript(source: source)?.executeAndReturnError(&error)
            artwork = (error == nil ? descriptor?.data : nil).flatMap(NSImage.init(data:))
        }
    }

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
