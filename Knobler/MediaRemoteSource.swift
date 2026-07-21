//
//  MediaRemoteSource.swift
//  Knobler
//
//  Now Playing universal via mediaremote-adapter (vendorado, v0.7.6): o
//  bloqueio do MediaRemote no macOS 15.4+ é contornado rodando o framework
//  auxiliar dentro do /usr/bin/perl (binário da Apple com o entitlement).
//  `stream` emite JSON por linha em modo diff; comandos são one-shot `send N`.
//

import AppKit

final class MediaRemoteSource {
    /// Estado consolidado após o merge dos diffs. Campo ausente = nil.
    struct NowPlaying {
        var bundleIdentifier: String?
        var parentBundleIdentifier: String?
        var playing: Bool
        var title: String?
        var artist: String?
        var album: String?
        var duration: Double?
        var elapsedTime: Double?
        var playbackRate: Double?
        var shuffleMode: Int?   // 1 desligado · 2 álbuns · 3 faixas · nil = fonte não reporta
        var artworkData: String?   // base64
    }

    /// IDs dos comandos MediaRemote que o adapter aceita em `send N`.
    enum Command: Int {
        case togglePlayPause = 2, nextTrack = 4, previousTrack = 5, toggleShuffle = 6
    }

    /// Chamado na main queue a cada atualização; nil = nada tocando.
    var onUpdate: ((NowPlaying?) -> Void)?

    private var process: Process?
    private var buffer = Data()
    private var payload: [String: Any] = [:]
    private var restartAttempts = 0
    private var stopped = false

    /// [script.pl, framework] — nil fora do bundle real (harness de snapshot).
    private static var adapterArguments: [String]? {
        guard let script = Bundle.main.url(forResource: "mediaremote-adapter", withExtension: "pl"),
              let frameworks = Bundle.main.privateFrameworksPath
        else { return nil }
        return [script.path, frameworks + "/MediaRemoteAdapter.framework"]
    }

    func start() {
        stopped = false
        guard let base = Self.adapterArguments else { return }
        // Health check do README: exit 0 = adapter funcional. Se um update do
        // macOS quebrar o truque do perl, o card só fica vazio — sem crash.
        let test = Process()
        test.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        test.arguments = base + ["test"]
        test.standardOutput = FileHandle.nullDevice
        test.standardError = FileHandle.nullDevice
        test.terminationHandler = { [weak self] proc in
            DispatchQueue.main.async {
                guard proc.terminationStatus == 0 else {
                    NSLog("MediaRemoteSource: adapter quebrado (test → %d); now playing desligado",
                          proc.terminationStatus)
                    return
                }
                self?.startStream()
            }
        }
        try? test.run()
    }

    func stop() {
        stopped = true
        process?.terminationHandler = nil
        process?.terminate()
        process = nil
    }

    func send(_ command: Command) {
        guard let base = Self.adapterArguments else { return }
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        proc.arguments = base + ["send", "\(command.rawValue)"]
        proc.standardOutput = FileHandle.nullDevice
        proc.standardError = FileHandle.nullDevice
        try? proc.run()
    }

    // MARK: - Stream

    private func startStream() {
        guard !stopped, let base = Self.adapterArguments else { return }
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        proc.arguments = base + ["stream", "--debounce=100"]
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = FileHandle.nullDevice
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            DispatchQueue.main.async { self?.consume(data) }
        }
        proc.terminationHandler = { [weak self] _ in
            DispatchQueue.main.async { self?.streamDied() }
        }
        do {
            try proc.run()
            process = proc
        } catch {
            NSLog("MediaRemoteSource: falha ao lançar o stream: \(error)")
        }
    }

    private func streamDied() {
        process = nil
        guard !stopped else { return }
        restartAttempts += 1
        guard restartAttempts <= 5 else {
            NSLog("MediaRemoteSource: stream morreu %d×; desistindo", restartAttempts)
            onUpdate?(nil)
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + Double(restartAttempts) * 2) { [weak self] in
            self?.startStream()
        }
    }

    private func consume(_ data: Data) {
        buffer.append(data)
        while let newline = buffer.firstIndex(of: 0x0A) {
            let line = buffer[buffer.startIndex..<newline]
            buffer.removeSubrange(buffer.startIndex...newline)
            // ponytail: linha malformada (ex.: Infinity, JSON inválido) é pulada
            // inteira — perde-se um tick, o próximo evento corrige.
            guard !line.isEmpty,
                  let json = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any],
                  json["type"] as? String == "data",
                  let incoming = json["payload"] as? [String: Any]
            else { continue }
            restartAttempts = 0
            payload = Self.merge(base: payload, incoming: incoming,
                                 diff: json["diff"] as? Bool ?? false)
            onUpdate?(Self.decode(payload))
        }
    }

    // MARK: - Parser (puro, coberto pelo self-check)

    /// Regra do adapter: diff=false substitui tudo; diff=true mescla — chave
    /// presente com null remove o campo, chave ausente fica como está.
    static func merge(base: [String: Any], incoming: [String: Any], diff: Bool) -> [String: Any] {
        guard diff else { return incoming }
        var merged = base
        for (key, value) in incoming {
            if value is NSNull { merged.removeValue(forKey: key) } else { merged[key] = value }
        }
        return merged
    }

    static func decode(_ payload: [String: Any]) -> NowPlaying? {
        // Issue #23 do adapter: o stream imprime um payload vazio primeiro;
        // sem título/fonte = nada tocando.
        guard let title = payload["title"] as? String, !title.isEmpty,
              payload["bundleIdentifier"] != nil
                || payload["parentApplicationBundleIdentifier"] != nil
        else { return nil }
        // Issue #28: duração pode vir infinita (live) — tratar como ausente.
        func finite(_ key: String) -> Double? {
            guard let n = (payload[key] as? NSNumber)?.doubleValue, n.isFinite else { return nil }
            return n
        }
        return NowPlaying(
            bundleIdentifier: payload["bundleIdentifier"] as? String,
            parentBundleIdentifier: payload["parentApplicationBundleIdentifier"] as? String,
            playing: payload["playing"] as? Bool ?? false,
            title: title,
            artist: payload["artist"] as? String,
            album: payload["album"] as? String,
            duration: finite("duration"),
            elapsedTime: finite("elapsedTime"),
            playbackRate: finite("playbackRate"),
            shuffleMode: (payload["shuffleMode"] as? NSNumber)?.intValue,
            artworkData: payload["artworkData"] as? String
        )
    }
}

#if MEDIAREMOTE_SELFCHECK
// swiftc -parse-as-library -swift-version 5 -D MEDIAREMOTE_SELFCHECK Knobler/MediaRemoteSource.swift -o /tmp/mrck && /tmp/mrck
@main enum MediaRemoteSelfCheck {
    static func main() {
        // merge: diff=false substitui
        var s = MediaRemoteSource.merge(base: ["title": "A", "artist": "X"],
                                        incoming: ["title": "B"], diff: false)
        assert(s["artist"] == nil && s["title"] as? String == "B")
        // merge: diff=true mescla; null remove; ausente preserva
        s = MediaRemoteSource.merge(
            base: ["title": "B", "artist": "X", "album": "Y"],
            incoming: ["artist": NSNull(), "title": "C"], diff: true)
        assert(s["title"] as? String == "C" && s["artist"] == nil && s["album"] as? String == "Y")
        // decode: payload vazio = nada tocando (issue #23)
        assert(MediaRemoteSource.decode([:]) == nil)
        // decode: campos mapeados; shuffleMode ausente = nil
        let now = MediaRemoteSource.decode([
            "bundleIdentifier": "com.apple.WebKit",
            "parentApplicationBundleIdentifier": "com.apple.Safari",
            "playing": true, "title": "Vídeo", "duration": 90.0, "elapsedTime": 10.0,
        ])!
        assert(now.playing && now.parentBundleIdentifier == "com.apple.Safari"
               && now.duration == 90 && now.shuffleMode == nil && now.artist == nil)
        // decode: duração infinita vira nil (issue #28)
        let live = MediaRemoteSource.decode([
            "bundleIdentifier": "app", "title": "Live", "duration": Double.infinity,
        ])!
        assert(live.duration == nil)
        print("MediaRemoteSource self-check ok")
    }
}
#endif
