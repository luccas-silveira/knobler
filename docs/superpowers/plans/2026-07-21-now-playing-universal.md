# Now Playing Universal — Plano de Implementação

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Trocar o motor AppleScript (Spotify/Music) do card de música pelo mediaremote-adapter, exibindo e controlando qualquer fonte de mídia do macOS (YouTube no navegador, podcasts, IINA…).

**Architecture:** `MediaRemoteSource.swift` (novo) envolve `/usr/bin/perl adapter.pl framework stream` e entrega estado consolidado (parser de diff); `MediaController` mantém a casca pública (`PlaybackState`, comandos, `currentPosition`) e troca o miolo. Framework vendorado (build local da tag v0.7.6), embutido sem link via `project.yml`.

**Tech Stack:** Swift/AppKit, `Process`+`Pipe`, mediaremote-adapter v0.7.6 (BSD-3), XcodeGen, cmake (build único do vendor).

## Global Constraints

- Deployment target macOS **14.2**; nada de API >14.2 sem `#available`.
- `Knobler.xcodeproj` é artefato — mudanças estruturais só em `project.yml` + `xcodegen generate`.
- Comentários e strings de UI em **pt-BR**; simplificações deliberadas com `// ponytail:`.
- `tools/snapshot.sh` tem lista manual de arquivos — arquivo novo usado pela `NotchView` entra lá.
- Harness (`tools/main.swift`) usa o init memberwise de `PlaybackState` — campos novos precisam de default e entrar depois dos existentes.
- CHANGELOG: registrar em `## [Unreleased]`; versão/tag só via `tools/release.sh` (não rodar).

---

### Task 1: Vendorar o adapter

**Files:**
- Create: `Vendor/MediaRemoteAdapter.framework` (binário, build local), `Vendor/mediaremote-adapter.pl`, `Vendor/PROVENANCE.md`
- Modify: `project.yml`

**Interfaces:**
- Produces: no bundle final — `Contents/Frameworks/MediaRemoteAdapter.framework` e `Contents/Resources/mediaremote-adapter.pl` (caminhos que a Task 2 resolve via `Bundle.main`).

- [ ] **Step 1: Build da tag pinada** (instalar cmake se faltar: `brew install cmake`)

```bash
cd "$(mktemp -d)" && git clone --depth 1 --branch v0.7.6 https://github.com/ungive/mediaremote-adapter
cd mediaremote-adapter && mkdir build && cd build && cmake .. && cmake --build . --config Release
```

Expected: `MediaRemoteAdapter.framework` no diretório de build (universal ou arch nativa).

- [ ] **Step 2: Copiar artefatos + procedência**

```bash
mkdir -p ~/Desktop/knobler/Vendor
cp -R MediaRemoteAdapter.framework ~/Desktop/knobler/Vendor/
cp ../mediaremote-adapter.pl ~/Desktop/knobler/Vendor/
```

`Vendor/PROVENANCE.md`: origem (repo/tag/commit), licença BSD-3, comando de build, data, e o porquê (releases não têm binário).

- [ ] **Step 3: project.yml** — embutir sem linkar (Xcode assina o framework aninhado, resolve distribuição) e o `.pl` como resource:

```yaml
    dependencies:
      - package: FluidAudio
      - sdk: Collaboration.framework
      - framework: Vendor/MediaRemoteAdapter.framework
        embed: true
        link: false
        codeSign: true
    sources:
      - Knobler
      - path: Vendor/mediaremote-adapter.pl
        buildPhase: resources
```

- [ ] **Step 4: Gerar e compilar**

Run: `xcodegen generate && xcodebuild -project Knobler.xcodeproj -scheme Knobler -configuration Debug build`
Expected: BUILD SUCCEEDED; no app do DerivedData, `Contents/Frameworks/MediaRemoteAdapter.framework` e `Contents/Resources/mediaremote-adapter.pl` existem.

- [ ] **Step 5: Smoke test do adapter no bundle**

```bash
APP=$(xcodebuild -project Knobler.xcodeproj -scheme Knobler -configuration Debug -showBuildSettings 2>/dev/null | awk '/BUILT_PRODUCTS_DIR/{print $3; exit}')/Knobler.app
/usr/bin/perl "$APP/Contents/Resources/mediaremote-adapter.pl" "$APP/Contents/Frameworks/MediaRemoteAdapter.framework" test; echo "exit=$?"
```

Expected: `exit=0`.

- [ ] **Step 6: Commit** — `feat(media): vendora mediaremote-adapter v0.7.6 (framework + script perl)`

---

### Task 2: MediaRemoteSource.swift

**Files:**
- Create: `Knobler/MediaRemoteSource.swift`
- Modify: `tools/snapshot.sh` (adicionar o arquivo à lista)

**Interfaces:**
- Produces (Task 3 consome):
  - `MediaRemoteSource.NowPlaying` — struct com `bundleIdentifier: String?`, `parentBundleIdentifier: String?`, `playing: Bool`, `title: String?`, `artist: String?`, `album: String?`, `duration: Double?`, `elapsedTime: Double?`, `playbackRate: Double?`, `shuffleMode: Int?`, `artworkData: String?`
  - `var onUpdate: ((NowPlaying?) -> Void)?` (main queue; `nil` = nada tocando)
  - `func start()`, `func stop()`, `func send(_ command: Command)` com `Command` = `.togglePlayPause`(2), `.nextTrack`(4), `.previousTrack`(5), `.toggleShuffle`(6)
  - `static func merge(base:incoming:diff:) -> [String: Any]` e `static func decode(_:) -> NowPlaying?` (puras, testáveis)

- [ ] **Step 1: Escrever o arquivo** (código completo)

```swift
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
                    NSLog("MediaRemoteSource: adapter quebrado (test → \(proc.terminationStatus)); now playing desligado")
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
            NSLog("MediaRemoteSource: stream morreu \(restartAttempts)×; desistindo")
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
// swiftc -parse-as-library -D MEDIAREMOTE_SELFCHECK Knobler/MediaRemoteSource.swift -o /tmp/mrck && /tmp/mrck
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
            "bundleIdentifier": "com.apple.WebKit", "parentApplicationBundleIdentifier": "com.apple.Safari",
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
```

- [ ] **Step 2: Rodar o self-check**

Run: `swiftc -parse-as-library -swift-version 5 -D MEDIAREMOTE_SELFCHECK Knobler/MediaRemoteSource.swift -o /tmp/mrck && /tmp/mrck`
Expected: `MediaRemoteSource self-check ok`

- [ ] **Step 3: snapshot.sh** — adicionar `Knobler/MediaRemoteSource.swift \` à lista (logo após `Knobler/MediaController.swift \`).

- [ ] **Step 4: Commit** — `feat(media): fonte universal de now playing via mediaremote-adapter (stream + parser de diff)`

---

### Task 3: MediaController reescrito por dentro

**Files:**
- Modify: `Knobler/MediaController.swift` (reescrever miolo; manter casca)

**Interfaces:**
- Consumes: tudo da Task 2.
- Produces (já consumido por NotchView/KnoblerApp — não quebrar): `PlaybackState` com os campos atuais **mais** `rate: Double = 1` e `shuffleAvailable: Bool = true` (defaults → harness intacto); `state`, `artwork`, `artworkTint`, `activeBundleID`, `injectPreview`, `playPause()`, `nextTrack()`, `previousTrack()`, `toggleShuffle()`, `currentPosition(at:)`.

- [ ] **Step 1: Reescrever** — sai AppleScript/`DistributedNotificationCenter`/download de capa; entra `MediaRemoteSource`:

```swift
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
        // (corpo atual inalterado — manter como está no arquivo)
    }
}
```

(`vibrantTint` mantém o corpo existente, linhas 231–277 do arquivo atual.)

- [ ] **Step 2: Compilar via snapshot** (mais rápido que xcodebuild e valida o harness junto)

Run: `./tools/snapshot.sh`
Expected: compila e regenera `Snapshots/*.png`; ler `closed-music.png` e `music-expanded.png` — layout idêntico ao de antes.

- [ ] **Step 3: Build do app**

Run: `xcodebuild -project Knobler.xcodeproj -scheme Knobler -configuration Debug build`
Expected: BUILD SUCCEEDED.

- [ ] **Step 4: Commit** — `feat(media): MediaController agora consome o MediaRemoteSource (adapter como fonte única)`

---

### Task 4: Ajustes de UI + limpeza do Info.plist

**Files:**
- Modify: `Knobler/NotchView.swift:776-783` (shuffle apagado quando indisponível), `Knobler/NotchView.swift:751-772` (barra sem duração), `project.yml` (usage descriptions)

**Interfaces:**
- Consumes: `PlaybackState.shuffleAvailable`, `PlaybackState.duration == 0` (live).

- [ ] **Step 1: Shuffle apagado quando a fonte não reporta** — no `controls(_:)`:

```swift
Button { media.toggleShuffle() } label: {
    Image(systemName: "shuffle")
        .font(.body)
        .foregroundStyle(state.shuffling ? .white : .white.opacity(0.45))
        .contentTransition(.symbolEffect(.replace))
}
.disabled(!state.shuffleAvailable)
.opacity(state.shuffleAvailable ? 1 : 0.2)
```

- [ ] **Step 2: Barra de progresso sem duração (live/desconhecida)** — em `progressBar(_:)`, trocar o texto restante e a fração:

```swift
let position = media.currentPosition(at: context.date)
let fraction = state.duration > 0 ? position / state.duration : 0
HStack(spacing: 10) {
    Text(Self.timeString(position))
    GeometryReader { geo in
        ZStack(alignment: .leading) {
            Capsule().fill(.white.opacity(0.25))
            Capsule()
                .fill(.white)
                .frame(width: max(5, geo.size.width * fraction))
        }
    }
    .frame(height: 5)
    // sem duração (live) não há "quanto falta" — mantém a altura da linha
    Text(state.duration > 0 ? "-" + Self.timeString(max(0, state.duration - position)) : "–:––")
}
```

- [ ] **Step 3: project.yml — usage descriptions**: remover `NSAppleEventsUsageDescription` (AppleScript morreu; só o MediaController usava) e generalizar `NSAudioCaptureUsageDescription` para `Knobler lê o áudio do player para animar o visualizador no notch, como no iPhone.`

- [ ] **Step 4: Regenerar + validar**

Run: `xcodegen generate && ./tools/snapshot.sh && xcodebuild -project Knobler.xcodeproj -scheme Knobler -configuration Debug build`
Expected: tudo verde; ler `music-expanded.png` (shuffle presente e aceso — preview injeta `shuffleAvailable = true` por default).

- [ ] **Step 5: Commit** — `feat(notch): shuffle apagado sem suporte da fonte; barra lida com duração desconhecida`

---

### Task 5: E2E real + CHANGELOG

**Files:**
- Modify: `CHANGELOG.md` (`## [Unreleased]`)

- [ ] **Step 1: Reinstalar o app de verdade** (lição do HANDOFF: `/Applications` ≠ DerivedData)

```bash
osascript -e 'quit app "Knobler"' 2>/dev/null; sleep 1
APP=$(xcodebuild -project Knobler.xcodeproj -scheme Knobler -configuration Debug -showBuildSettings 2>/dev/null | awk '/BUILT_PRODUCTS_DIR/{print $3; exit}')/Knobler.app
rm -rf /Applications/Knobler.app && cp -R "$APP" /Applications/ && open /Applications/Knobler.app
```

- [ ] **Step 2: E2E universal** — tocar algo fora do Spotify (ex.: YouTube no Safari) e conferir pela API local do app:

Run: `open -a Safari "https://www.youtube.com/watch?v=dQw4w9WgXcQ"` → dar play → `curl -s localhost:<porta>/status` (porta: ver `NotchAPIServer.swift`)
Expected: `"player"` = `com.apple.Safari` (ou o bundle do WebKit pai) — antes seria `none`.

- [ ] **Step 3: E2E regressão Spotify** — tocar Spotify, conferir `status.player == com.spotify.client`, card com capa/tint, shuffle clicável.

- [ ] **Step 4: CHANGELOG** em `## [Unreleased]`:

```markdown
### Changed
- **Now playing universal**: o card de música agora mostra e controla qualquer
  fonte de mídia do macOS (YouTube no navegador, podcasts, IINA…), não só
  Spotify/Apple Music. Motor novo: mediaremote-adapter v0.7.6 vendorado
  (framework carregado via /usr/bin/perl, contornando o bloqueio do MediaRemote
  no 15.4+). AppleScript saiu; se um update da Apple quebrar o adapter, o card
  fica vazio sem derrubar o app. Shuffle aparece apagado quando a fonte não
  reporta (navegador); barra de progresso lida com duração desconhecida (live).
```

- [ ] **Step 5: Commit final** — `docs: CHANGELOG do now playing universal`

---

## Self-review (feito na escrita)

- Cobertura do spec: vendoring (T1), fonte+stream+pegadinhas #23/#28/artwork atrasado (T2), casca preservada+bundle do pai pro tap (T3), shuffle apagado+live (T4), E2E+degradação (T2 health check, T5). ✔
- Sem placeholders; único "manter como está" é o corpo de `vibrantTint`, que é cópia literal do arquivo atual (linhas citadas). ✔
- Tipos consistentes entre T2 (produces) e T3 (consumes). ✔
