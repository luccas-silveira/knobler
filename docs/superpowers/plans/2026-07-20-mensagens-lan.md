# Mensagens LAN entre computadores — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Trocar mensagens entre Macs rodando Knobler na mesma rede local — abrir a aba Mensagens no notch, ver quem está online, escolher alguém e mandar um recado (com opção de resposta) que aparece no notch da outra pessoa com nome e foto.

**Architecture:** Bonjour (`NWListener`/`NWBrowser`) anuncia e descobre um serviço `_knobler._tcp`; um protocolo JSON emoldurado (4 bytes de tamanho + corpo) sobre `NWConnection` efêmera troca perfis e mensagens. Um listener **separado** do servidor `localhost:4477` — a API de automação não é exposta à rede. UI vive numa aba dentro do notch aberto; mensagem recebida abre o notch como um card.

**Tech Stack:** Swift 5, SwiftUI + AppKit, framework `Network` (Bonjour), `Collaboration` (foto/nome da conta), XcodeGen, `UserDefaults` + JSON em Application Support.

## Global Constraints

- **Deployment target:** macOS 14.2 (`project.yml`). O código de rede é compatível; a **permissão de Rede Local** é comportamento de runtime do macOS 15+/26.
- **Permissão de Rede Local (macOS 15+):** Info.plist precisa de `NSLocalNetworkUsageDescription` e `NSBonjourServices = ["_knobler._tcp"]` (via `project.yml`). Negação chega como `kDNSServiceErr_PolicyDenied (-65570)` no `stateUpdateHandler`. Disparar browse/advertise quando o usuário abre a aba (app ativo), não no launch.
- **Segurança:** listener aceita LAN (modo aberto). Teto de 64 KB por moldura; texto truncado a 2000 chars; foto decodificada via ImageIO (inválida → placeholder). Nenhum caminho de execução a partir do payload.
- **Sem dependências novas de terceiros:** só frameworks do sistema (`Network`, `Collaboration`).
- **Versionamento:** feature → SemVer **MINOR**. Escrever em `## [Unreleased]` do `CHANGELOG.md`. **Nunca** editar `MARKETING_VERSION` à mão nem criar tag — `tools/release.sh` é o único escritor.
- **XcodeGen:** `sources: [Knobler]` é a pasta inteira; arquivo novo em `Knobler/` entra ao rodar `xcodegen generate`. **Nunca** editar `Knobler.xcodeproj` à mão.
- **Testes:** o projeto **não tem alvo XCTest**. Verificação = `xcrun swiftc` (compile), o self-check `assert` do codec (rodável isolado, padrão do `tools/snapshot.sh`), `xcodebuild ... build`, e snapshot visual.
- **Convenções:** comentários e strings de UI em **pt-BR**. Simplificações deliberadas marcadas com `// ponytail:`.
- **Identidade estável:** `myID` = UUID gerado uma única vez, guardado em `UserDefaults`. Histórico e cache de foto são chaveados por ele.

---

### Task 1: Protocolo de fio (Wire) + modelos

Entrega o codec do protocolo (a única lógica não-trivial: framing binário + JSON tagueado) com um self-check `assert` rodável, mais os modelos de dados puros.

**Files:**
- Create: `Knobler/Wire.swift`
- Create: `Knobler/Peer.swift`
- Create: `tools/wirecheck.swift` (fora do alvo; rodado à mão, como `tools/main.swift`)

**Interfaces:**
- Consumes: nada.
- Produces:
  - `enum Packet: Codable, Equatable` — casos `.profileRequest`, `.profileResponse(id:name:avatar:)`, `.message(id:from:fromName:text:reply:)`, `.ack`.
  - `enum Frame { static let maxSize = 65536; static func encode(_:) throws -> Data; static func decode(_ body: Data) throws -> Packet }`.
  - `enum WireError: Error { case tooBig }`.
  - `struct Peer: Identifiable, Equatable { let id: String; var name: String; var endpoint: NWEndpoint; var online: Bool }`.
  - `struct PeerMessage: Identifiable, Codable, Equatable { let id, peerID: String; let incoming: Bool; var text: String; var allowReply: Bool; let at: Date; var delivered: Bool }`.
  - `struct PeerProfile: Codable, Equatable { let id, name: String; var avatarJPEG: Data? }`.

- [ ] **Step 1: Escrever `Knobler/Wire.swift`**

```swift
//
//  Wire.swift
//  Knobler
//
//  Protocolo de fio das mensagens LAN: pacote JSON tagueado por "t",
//  emoldurado com prefixo de 4 bytes (tamanho, big-endian) + corpo.
//  Só Foundation — sem Network — pra ser testável isolado (tools/wirecheck.swift).
//

import Foundation

enum Packet: Codable, Equatable {
    case profileRequest
    case profileResponse(id: String, name: String, avatar: Data?)
    case message(id: String, from: String, fromName: String, text: String, reply: Bool)
    case ack

    private enum Key: String, CodingKey {
        case t, id, name, avatar, from, fromName, text, reply
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: Key.self)
        switch self {
        case .profileRequest:
            try c.encode("profile", forKey: .t)
        case let .profileResponse(id, name, avatar):
            try c.encode("profileResp", forKey: .t)
            try c.encode(id, forKey: .id)
            try c.encode(name, forKey: .name)
            try c.encodeIfPresent(avatar, forKey: .avatar) // Data → base64 no JSON
        case let .message(id, from, fromName, text, reply):
            try c.encode("msg", forKey: .t)
            try c.encode(id, forKey: .id)
            try c.encode(from, forKey: .from)
            try c.encode(fromName, forKey: .fromName)
            try c.encode(text, forKey: .text)
            try c.encode(reply, forKey: .reply)
        case .ack:
            try c.encode("ack", forKey: .t)
        }
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Key.self)
        switch try c.decode(String.self, forKey: .t) {
        case "profile":
            self = .profileRequest
        case "profileResp":
            self = .profileResponse(
                id: try c.decode(String.self, forKey: .id),
                name: try c.decode(String.self, forKey: .name),
                avatar: try c.decodeIfPresent(Data.self, forKey: .avatar))
        case "msg":
            self = .message(
                id: try c.decode(String.self, forKey: .id),
                from: try c.decode(String.self, forKey: .from),
                fromName: try c.decode(String.self, forKey: .fromName),
                text: try c.decode(String.self, forKey: .text),
                reply: try c.decode(Bool.self, forKey: .reply))
        case "ack":
            self = .ack
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .t, in: c, debugDescription: "tipo de pacote desconhecido")
        }
    }
}

enum WireError: Error { case tooBig }

enum Frame {
    static let maxSize = 64 * 1024

    /// 4 bytes de tamanho (big-endian) + corpo JSON.
    static func encode(_ packet: Packet) throws -> Data {
        let body = try JSONEncoder().encode(packet)
        guard body.count <= maxSize else { throw WireError.tooBig }
        var len = UInt32(body.count).bigEndian
        var out = Data(bytes: &len, count: 4)
        out.append(body)
        return out
    }

    static func decode(_ body: Data) throws -> Packet {
        try JSONDecoder().decode(Packet.self, from: body)
    }
}
```

- [ ] **Step 2: Escrever `tools/wirecheck.swift` (self-check por asserts)**

```swift
//
//  wirecheck.swift — self-check do protocolo de fio. NÃO faz parte do alvo.
//  Rodar: xcrun swiftc Knobler/Wire.swift tools/wirecheck.swift -o /tmp/wirecheck && /tmp/wirecheck
//

import Foundation

// round-trip de mensagem
let msg = Packet.message(id: "m1", from: "u1", fromName: "Luccas", text: "olá", reply: true)
let framed = try Frame.encode(msg)
assert(framed.count > 4, "moldura tem prefixo + corpo")
let n = framed.prefix(4).withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }
assert(Int(n) == framed.count - 4, "prefixo bate com o tamanho do corpo")
assert(try Frame.decode(framed.suffix(from: 4)) == msg, "mensagem sobrevive ao round-trip")

// round-trip de perfil com avatar (Data → base64 → Data)
let jpeg = Data([0xFF, 0xD8, 0xFF, 0xE0, 1, 2, 3])
let prof = Packet.profileResponse(id: "u1", name: "Luccas", avatar: jpeg)
assert(try Frame.decode(Frame.encode(prof).suffix(from: 4)) == prof, "perfil+avatar sobrevive")

// profileRequest e ack
assert(try Frame.decode(Frame.encode(.profileRequest).suffix(from: 4)) == .profileRequest)
assert(try Frame.decode(Frame.encode(.ack).suffix(from: 4)) == .ack)

// teto de 64 KB
let huge = Packet.message(id: "x", from: "x", fromName: "x",
                          text: String(repeating: "a", count: 70_000), reply: false)
do { _ = try Frame.encode(huge); assert(false, "deveria estourar o teto") }
catch WireError.tooBig { /* esperado */ }

print("wire ok")
```

- [ ] **Step 3: Rodar o self-check e ver FALHAR (Wire.swift ainda incompleto? não — verificar que compila e passa)**

Run: `cd /Users/luccassilveira/Desktop/knobler && xcrun swiftc Knobler/Wire.swift tools/wirecheck.swift -o /tmp/wirecheck && /tmp/wirecheck`
Expected: imprime `wire ok`. (Se algum assert quebrar, o processo aborta com a mensagem do assert — corrigir antes de seguir.)

- [ ] **Step 4: Escrever `Knobler/Peer.swift` (modelos)**

```swift
//
//  Peer.swift
//  Knobler
//
//  Modelos das mensagens LAN. `Peer` referencia um endpoint Bonjour vivo;
//  `PeerMessage`/`PeerProfile` são dados puros (persistência + fio).
//

import Foundation
import Network

/// Uma pessoa descoberta na rede agora (some quando o Bonjour a remove).
struct Peer: Identifiable, Equatable {
    let id: String            // UUID vindo do TXT record
    var name: String          // nome de exibição (TXT record)
    var endpoint: NWEndpoint  // pra abrir conexão
    var online: Bool = true

    static func == (a: Peer, b: Peer) -> Bool {
        a.id == b.id && a.name == b.name && a.online == b.online
    }
}

/// Mensagem trocada. `peerID` é sempre o OUTRO lado (remetente se incoming,
/// destinatário se outgoing). `delivered` só importa em outgoing.
struct PeerMessage: Identifiable, Codable, Equatable {
    let id: String
    let peerID: String
    let incoming: Bool
    var text: String
    var allowReply: Bool
    let at: Date
    var delivered: Bool = true
}

/// Perfil publicado por um peer (resposta ao pedido `profile`).
struct PeerProfile: Codable, Equatable {
    let id: String
    let name: String
    var avatarJPEG: Data?
}
```

- [ ] **Step 5: Verificar que `Peer.swift` compila**

Run: `cd /Users/luccassilveira/Desktop/knobler && xcrun swiftc -typecheck -target arm64-apple-macos14.2 Knobler/Peer.swift`
Expected: sem saída (exit 0).

- [ ] **Step 6: Commit**

```bash
cd /Users/luccassilveira/Desktop/knobler
git add Knobler/Wire.swift Knobler/Peer.swift tools/wirecheck.swift
git commit -m "feat(mensagens): protocolo de fio + modelos (Wire, Peer)"
```

---

### Task 2: Identidade no AppSettings + prefill do macOS + UI de Ajustes

Nome e foto que os outros veem, pré-preenchidos com os da conta do macOS (via `Collaboration`), editáveis numa aba de Ajustes.

**Files:**
- Modify: `Knobler/AppSettings.swift` (adicionar identidade + helpers; nova aba na `SettingsView`)
- Create: `Knobler/IdentitySettingsView.swift`
- Modify: `project.yml` (linkar `Collaboration.framework`)

**Interfaces:**
- Consumes: `PeerProfile` (Task 1).
- Produces (em `AppSettings`):
  - `var myID: String` (UUID persistido, read-only).
  - `@Published var displayName: String`.
  - `func myAvatarJPEG() -> Data?` / `func setMyAvatar(_ image: NSImage)`.
  - `func myProfile() -> PeerProfile`.
  - `static func macOSFullName() -> String` / `static func macOSAvatar() -> NSImage?`.
  - `static func jpegThumbnail(_ image: NSImage, side: CGFloat = 64) -> Data?`.

- [ ] **Step 1: Linkar `Collaboration.framework` no `project.yml`**

Em `project.yml`, dentro de `targets.Knobler`, adicionar (irmão de `dependencies`):

```yaml
    dependencies:
      - package: FluidAudio
      - sdk: Collaboration.framework
```

- [ ] **Step 2: Adicionar identidade + helpers ao `AppSettings.swift`**

No topo do arquivo, trocar os imports por (adiciona `AppKit` e `Collaboration`):

```swift
import AppKit
import Collaboration
import Security
import ServiceManagement
import SwiftUI
```

Adicionar como propriedades de `AppSettings` (perto dos outros `@Published`):

```swift
    /// Nome que os outros veem nas Mensagens LAN. Começa com o do macOS.
    @Published var displayName: String {
        didSet { UserDefaults.standard.set(displayName, forKey: "displayName") }
    }
    /// UUID estável desta instalação — chaveia histórico e foto. Gerado 1x.
    let myID: String
```

No `init()`, antes do fim, adicionar:

```swift
        if let existing = defaults.string(forKey: "myID") {
            myID = existing
        } else {
            let generated = UUID().uuidString
            defaults.set(generated, forKey: "myID")
            myID = generated
        }
        displayName = defaults.string(forKey: "displayName") ?? AppSettings.macOSFullName()
```

Adicionar estes métodos a `AppSettings` (após o `init`):

```swift
    // MARK: - Identidade das Mensagens LAN

    /// Foto de perfil em App Support (me.jpg). nil se o usuário não definiu.
    private var myAvatarURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Knobler", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("me.jpg")
    }

    func myAvatarJPEG() -> Data? { try? Data(contentsOf: myAvatarURL) }

    func setMyAvatar(_ image: NSImage) {
        guard let jpeg = AppSettings.jpegThumbnail(image) else { return }
        try? jpeg.write(to: myAvatarURL)
        objectWillChange.send()
    }

    func myProfile() -> PeerProfile {
        PeerProfile(id: myID, name: displayName, avatarJPEG: myAvatarJPEG())
    }

    static func macOSFullName() -> String {
        let name = NSFullUserName()
        return name.isEmpty ? NSUserName() : name
    }

    static func macOSAvatar() -> NSImage? {
        CBUserIdentity(posixUID: getuid(), authority: .default())?.image
    }

    /// Redimensiona pra `side`×`side` e comprime em JPEG (~alguns KB).
    static func jpegThumbnail(_ image: NSImage, side: CGFloat = 64) -> Data? {
        let target = NSImage(size: NSSize(width: side, height: side))
        target.lockFocus()
        image.draw(in: NSRect(x: 0, y: 0, width: side, height: side),
                   from: .zero, operation: .copy, fraction: 1)
        target.unlockFocus()
        guard let tiff = target.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .jpeg, properties: [.compressionFactor: 0.7])
    }
```

- [ ] **Step 3: Criar `Knobler/IdentitySettingsView.swift`**

```swift
//
//  IdentitySettingsView.swift
//  Knobler
//
//  Aba de Ajustes: nome e foto que os outros veem nas Mensagens LAN.
//

import AppKit
import SwiftUI

struct IdentitySettingsView: View {
    @ObservedObject var settings = AppSettings.shared
    @State private var avatar: NSImage?

    var body: some View {
        Form {
            Section("Como você aparece na rede") {
                HStack(spacing: 12) {
                    avatarThumb
                    VStack(alignment: .leading, spacing: 6) {
                        TextField("Nome de exibição", text: $settings.displayName)
                        HStack {
                            Button("Escolher foto…") { pickPhoto() }
                            Button("Usar a do macOS") { useMacOSPhoto() }
                        }
                    }
                }
            } footer: {
                Text("Outros Macs com Knobler na mesma rede veem este nome e esta foto.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear { avatar = loadAvatar() }
    }

    private var avatarThumb: some View {
        Group {
            if let avatar {
                Image(nsImage: avatar).resizable().scaledToFill()
            } else {
                ZStack {
                    Circle().fill(.gray.opacity(0.3))
                    Text(initials).font(.title3.weight(.semibold)).foregroundStyle(.white)
                }
            }
        }
        .frame(width: 56, height: 56)
        .clipShape(Circle())
    }

    private var initials: String {
        String(settings.displayName.prefix(1)).uppercased()
    }

    private func loadAvatar() -> NSImage? {
        settings.myAvatarJPEG().flatMap { NSImage(data: $0) }
    }

    private func pickPhoto() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .jpeg, .heic]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url,
              let image = NSImage(contentsOf: url) else { return }
        settings.setMyAvatar(image)
        avatar = loadAvatar()
    }

    private func useMacOSPhoto() {
        guard let image = AppSettings.macOSAvatar() else { return }
        settings.setMyAvatar(image)
        avatar = loadAvatar()
    }
}
```

- [ ] **Step 4: Adicionar a aba na `SettingsView`**

Em `AppSettings.swift`, no `TabView` de `SettingsView.body`, adicionar antes do fechamento do `TabView`:

```swift
            IdentitySettingsView()
                .tabItem { Label("Mensagens", systemImage: "bubble.left.and.bubble.right") }
```

- [ ] **Step 5: Regenerar projeto e compilar**

Run:
```bash
cd /Users/luccassilveira/Desktop/knobler && xcodegen generate && \
xcodebuild -project Knobler.xcodeproj -scheme Knobler -configuration Debug build 2>&1 | tail -3
```
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 6: Commit**

```bash
cd /Users/luccassilveira/Desktop/knobler
git add project.yml Knobler/AppSettings.swift Knobler/IdentitySettingsView.swift
git commit -m "feat(mensagens): identidade (nome+foto) com prefill do macOS"
```

---

### Task 3: MessageStore — histórico e cache de fotos

Persiste últimas 20 mensagens por peer e as fotos dos peers em Application Support.

**Files:**
- Create: `Knobler/MessageStore.swift`

**Interfaces:**
- Consumes: `PeerMessage` (Task 1).
- Produces:
  - `final class MessageStore: ObservableObject`
  - `@Published private(set) var threads: [String: [PeerMessage]]`
  - `func messages(for peerID: String) -> [PeerMessage]`
  - `func append(_ msg: PeerMessage)`
  - `func rememberName(_ name: String, for peerID: String)` / `func name(for peerID: String) -> String?`
  - `func cacheAvatar(_ jpeg: Data, for peerID: String)` / `func avatar(for peerID: String) -> NSImage?`

- [ ] **Step 1: Criar `Knobler/MessageStore.swift`**

```swift
//
//  MessageStore.swift
//  Knobler
//
//  Histórico das Mensagens LAN: últimas 20 por peer (JSON em App Support) +
//  cache das fotos dos peers (arquivos .jpg) + nomes conhecidos.
//

import AppKit
import Foundation

final class MessageStore: ObservableObject {
    /// peerID → últimas mensagens (mais antiga → mais nova).
    @Published private(set) var threads: [String: [PeerMessage]] = [:]
    /// peerID → último nome visto (pra rotular histórico com o peer offline).
    @Published private(set) var names: [String: String] = [:]

    private static let maxPerPeer = 20
    private var saveWork: DispatchWorkItem?

    private var baseDir: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Knobler", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
    private var threadsURL: URL { baseDir.appendingPathComponent("messages.json") }
    private var namesURL: URL { baseDir.appendingPathComponent("peerNames.json") }
    private var avatarsDir: URL {
        let dir = baseDir.appendingPathComponent("avatars", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    init() {
        if let data = try? Data(contentsOf: threadsURL),
           let decoded = try? JSONDecoder().decode([String: [PeerMessage]].self, from: data) {
            threads = decoded
        }
        if let data = try? Data(contentsOf: namesURL),
           let decoded = try? JSONDecoder().decode([String: String].self, from: data) {
            names = decoded
        }
    }

    func messages(for peerID: String) -> [PeerMessage] { threads[peerID] ?? [] }

    func append(_ msg: PeerMessage) {
        var list = threads[msg.peerID] ?? []
        list.append(msg)
        if list.count > Self.maxPerPeer { list.removeFirst(list.count - Self.maxPerPeer) }
        threads[msg.peerID] = list
        scheduleSave()
    }

    func name(for peerID: String) -> String? { names[peerID] }

    func rememberName(_ name: String, for peerID: String) {
        guard names[peerID] != name else { return }
        names[peerID] = name
        scheduleSave()
    }

    func cacheAvatar(_ jpeg: Data, for peerID: String) {
        try? jpeg.write(to: avatarsDir.appendingPathComponent("\(peerID).jpg"))
        objectWillChange.send()
    }

    func avatar(for peerID: String) -> NSImage? {
        NSImage(contentsOf: avatarsDir.appendingPathComponent("\(peerID).jpg"))
    }

    // ponytail: debounce simples de 1s; some flush no quit se virar problema
    private func scheduleSave() {
        saveWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.save() }
        saveWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1, execute: work)
    }

    private func save() {
        if let data = try? JSONEncoder().encode(threads) { try? data.write(to: threadsURL) }
        if let data = try? JSONEncoder().encode(names) { try? data.write(to: namesURL) }
    }
}
```

- [ ] **Step 2: Regenerar e compilar**

Run:
```bash
cd /Users/luccassilveira/Desktop/knobler && xcodegen generate && \
xcodebuild -project Knobler.xcodeproj -scheme Knobler -configuration Debug build 2>&1 | tail -3
```
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit**

```bash
cd /Users/luccassilveira/Desktop/knobler
git add Knobler/MessageStore.swift
git commit -m "feat(mensagens): MessageStore (histórico últimas 20/peer + cache de foto)"
```

---

### Task 4: LANMessaging — motor Bonjour + protocolo + gate de permissão

Anuncia e descobre peers; recebe conexões e responde a `profile`/`message`; envia mensagens e busca perfis; detecta negação de Rede Local (-65570).

**Files:**
- Create: `Knobler/LANMessaging.swift`
- Modify: `project.yml` (Info.plist: `NSLocalNetworkUsageDescription`, `NSBonjourServices`)

**Interfaces:**
- Consumes: `Packet`, `Frame`, `WireError` (Task 1); `Peer`, `PeerMessage`, `PeerProfile` (Task 1).
- Produces:
  - `final class LANMessaging: ObservableObject`
  - `@Published private(set) var peers: [Peer]`
  - `@Published private(set) var permissionDenied: Bool`
  - `var profileProvider: (() -> PeerProfile)?` (app fornece o próprio perfil pra responder/anunciar)
  - `var onIncoming: ((PeerMessage, PeerProfile?) -> Void)?`
  - `func start()` / `func stop()`
  - `func send(_ text: String, to peer: Peer, allowReply: Bool, completion: @escaping (Bool) -> Void)`
  - `func fetchProfile(from peer: Peer, completion: @escaping (PeerProfile?) -> Void)`
  - `func peer(withID id: String) -> Peer?`
  - `var diagnostics: [String: Any]` (pro `GET /status`)

- [ ] **Step 1: Adicionar as chaves de Info.plist no `project.yml`**

Em `project.yml`, dentro de `targets.Knobler.info.properties`, adicionar:

```yaml
        NSLocalNetworkUsageDescription: Knobler troca mensagens com outros Macs na sua rede local.
        NSBonjourServices:
          - _knobler._tcp
```

- [ ] **Step 2: Criar `Knobler/LANMessaging.swift`**

```swift
//
//  LANMessaging.swift
//  Knobler
//
//  Mensagens LAN: anuncia/descobre `_knobler._tcp` via Bonjour e troca
//  pacotes emoldurados (ver Wire.swift) por conexões efêmeras. Separado do
//  NotchAPIServer (localhost) — a API de automação não é exposta à rede.
//

import Foundation
import Network

final class LANMessaging: ObservableObject {
    static let serviceType = "_knobler._tcp"

    @Published private(set) var peers: [Peer] = []
    /// Rede Local negada pelo usuário (kDNSServiceErr_PolicyDenied -65570).
    @Published private(set) var permissionDenied = false

    /// App fornece o próprio perfil (id/nome/foto) pra anunciar e responder `profile`.
    var profileProvider: (() -> PeerProfile)?
    /// Mensagem recebida (já validada) → app grava/mostra.
    var onIncoming: ((PeerMessage, PeerProfile?) -> Void)?

    private var listener: NWListener?
    private var browser: NWBrowser?

    // MARK: Ciclo de vida

    func start() {
        guard listener == nil else { return }
        startListener()
        startBrowser()
    }

    func stop() {
        listener?.cancel(); listener = nil
        browser?.cancel(); browser = nil
        peers = []
    }

    func peer(withID id: String) -> Peer? { peers.first { $0.id == id } }

    var diagnostics: [String: Any] {
        ["peers": peers.count, "permissionDenied": permissionDenied]
    }

    // MARK: Anúncio (listener)

    private func startListener() {
        guard let profile = profileProvider?() else { return }
        let listener = try? NWListener(using: .tcp)
        guard let listener else { return }
        var txt = NWTXTRecord()
        txt["id"] = profile.id
        txt["name"] = profile.name
        listener.service = NWListener.Service(
            name: profile.id, type: Self.serviceType, txtRecord: txt)
        listener.stateUpdateHandler = { [weak self] state in
            if case let .failed(err) = state { self?.noteError(err) }
        }
        listener.newConnectionHandler = { [weak self] conn in
            self?.serve(conn)
        }
        listener.start(queue: .main)
        self.listener = listener
    }

    // MARK: Descoberta (browser)

    private func startBrowser() {
        let params = NWParameters.tcp
        let browser = NWBrowser(
            for: .bonjourWithTXTRecord(type: Self.serviceType, domain: nil), using: params)
        browser.stateUpdateHandler = { [weak self] state in
            if case let .failed(err) = state { self?.noteError(err) }
        }
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            self?.updatePeers(results)
        }
        browser.start(queue: .main)
        self.browser = browser
    }

    private func updatePeers(_ results: Set<NWBrowser.Result>) {
        let myID = profileProvider?().id
        var found: [Peer] = []
        for r in results {
            guard case let .bonjour(txt) = r.metadata,
                  let id = txt["id"], id != myID else { continue }
            let name = txt["name"] ?? id
            found.append(Peer(id: id, name: name, endpoint: r.endpoint))
        }
        peers = found.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    // MARK: Servir conexões de entrada

    private func serve(_ conn: NWConnection) {
        conn.start(queue: .main)
        receiveFrame(on: conn) { [weak self] packet in
            guard let self, let packet else { conn.cancel(); return }
            switch packet {
            case .profileRequest:
                let p = self.profileProvider?() ?? PeerProfile(id: "", name: "?", avatarJPEG: nil)
                self.sendFrame(.profileResponse(id: p.id, name: p.name, avatar: p.avatarJPEG),
                               on: conn, close: true)
            case let .message(id, from, fromName, text, reply):
                let clipped = String(text.prefix(2000))
                let msg = PeerMessage(id: id, peerID: from, incoming: true,
                                      text: clipped, allowReply: reply, at: Date())
                let prof = PeerProfile(id: from, name: fromName, avatarJPEG: nil)
                DispatchQueue.main.async { self.onIncoming?(msg, prof) }
                self.sendFrame(.ack, on: conn, close: true)
            default:
                conn.cancel()
            }
        }
    }

    // MARK: Enviar

    func send(_ text: String, to peer: Peer, allowReply: Bool,
              completion: @escaping (Bool) -> Void) {
        guard let me = profileProvider?() else { completion(false); return }
        let packet = Packet.message(
            id: UUID().uuidString, from: me.id, fromName: me.name,
            text: String(text.prefix(2000)), reply: allowReply)
        request(packet, to: peer.endpoint) { reply in
            if case .ack = reply { completion(true) } else { completion(false) }
        }
    }

    func fetchProfile(from peer: Peer, completion: @escaping (PeerProfile?) -> Void) {
        request(.profileRequest, to: peer.endpoint) { reply in
            if case let .profileResponse(id, name, avatar) = reply {
                completion(PeerProfile(id: id, name: name, avatarJPEG: avatar))
            } else {
                completion(nil)
            }
        }
    }

    /// Conecta, manda um pacote, lê a resposta, fecha. `nil` = falhou.
    private func request(_ packet: Packet, to endpoint: NWEndpoint,
                         completion: @escaping (Packet?) -> Void) {
        let conn = NWConnection(to: endpoint, using: .tcp)
        var finished = false
        func finish(_ reply: Packet?) {
            guard !finished else { return }
            finished = true
            conn.cancel()
            DispatchQueue.main.async { completion(reply) }
        }
        conn.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                self?.sendFrame(packet, on: conn, close: false)
                self?.receiveFrame(on: conn) { finish($0) }
            case let .failed(err), let .waiting(err):
                self?.noteError(err)
                finish(nil)
            default:
                break
            }
        }
        conn.start(queue: .main)
        // rede local não deve demorar; corta pendências
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { finish(nil) }
    }

    // MARK: Framing sobre NWConnection

    private func sendFrame(_ packet: Packet, on conn: NWConnection, close: Bool) {
        guard let data = try? Frame.encode(packet) else { conn.cancel(); return }
        conn.send(content: data, completion: .contentProcessed { _ in
            if close { conn.cancel() }
        })
    }

    /// Lê 4 bytes de tamanho, depois o corpo, decodifica. `nil` em erro.
    private func receiveFrame(on conn: NWConnection, then: @escaping (Packet?) -> Void) {
        conn.receive(minimumIncompleteLength: 4, maximumLength: 4) { header, _, _, err in
            guard let header, header.count == 4, err == nil else { then(nil); return }
            let n = Int(header.withUnsafeBytes { $0.load(as: UInt32.self).bigEndian })
            guard n > 0, n <= Frame.maxSize else { then(nil); return }
            conn.receive(minimumIncompleteLength: n, maximumLength: n) { body, _, _, err in
                guard let body, body.count == n, err == nil,
                      let packet = try? Frame.decode(body) else { then(nil); return }
                then(packet)
            }
        }
    }

    // MARK: Erros

    private func noteError(_ error: NWError) {
        // kDNSServiceErr_PolicyDenied == -65570 → Rede Local negada
        if case let .dns(code) = error, code == -65570 {
            DispatchQueue.main.async { self.permissionDenied = true }
        }
    }
}
```

- [ ] **Step 3: Regenerar e compilar**

Run:
```bash
cd /Users/luccassilveira/Desktop/knobler && xcodegen generate && \
xcodebuild -project Knobler.xcodeproj -scheme Knobler -configuration Debug build 2>&1 | tail -3
```
Expected: `** BUILD SUCCEEDED **`. (Se `NWError.dns` não casar, ver nota abaixo¹.)

> ¹ Se o compilador reclamar do padrão `.dns(code)`, trocar `noteError` por comparação via `errorCode`: `if (error as NSError).code == -65570 || "\(error)".contains("-65570") { ... }`. `NWError.dns(DNSServiceErrorType)` existe no SDK; o valor `-65570` é `kDNSServiceErr_PolicyDenied`.

- [ ] **Step 4: Commit**

```bash
cd /Users/luccassilveira/Desktop/knobler
git add project.yml Knobler/LANMessaging.swift
git commit -m "feat(mensagens): motor Bonjour + protocolo + gate de Rede Local"
```

---

### Task 5: NotchViewModel + NotchView — aba e modo de card

Adiciona o estado de aba (Música | Mensagens) no notch aberto e o modo `.message` do card de entrada.

**Files:**
- Modify: `Knobler/NotchViewModel.swift`
- Modify: `Knobler/NotchView.swift` (novo `case .message` no switch de conteúdo, tamanho, e a barra de abas dentro de `expandedContent`)

**Interfaces:**
- Consumes: `MessageStore`, `LANMessaging` (via ambiente, Task 3/4).
- Produces (em `NotchViewModel`):
  - `enum NotchTab { case music, messages }` + `@Published var tab: NotchTab`
  - `struct IncomingMessage: Equatable { let peerID, name, text: String; let allowReply: Bool }`
  - `@Published var incoming: IncomingMessage?`
  - `func showIncoming(_ m: IncomingMessage)` / `func dismissIncoming()`
  - `func openThread(peerID: String)`
  - `var onSendReply: ((String, String) -> Void)?` (peerID, texto)
  - `case message` adicionado a `Mode` e à prioridade de `mode`.

- [ ] **Step 1: Adicionar estado ao `NotchViewModel.swift`**

Adicionar após `@Published var askText = ""`:

```swift
    /// Aba do notch aberto: música (default) ou mensagens LAN.
    enum NotchTab: Equatable { case music, messages }
    @Published var tab: NotchTab = .music

    /// Mensagem LAN chegando, exibida como card no notch.
    struct IncomingMessage: Equatable {
        let peerID: String
        let name: String
        let text: String
        let allowReply: Bool
    }
    @Published var incoming: IncomingMessage?
    /// Resposta rápida do card → app envia (peerID, texto).
    var onSendReply: ((String, String) -> Void)?
    private var incomingWork: DispatchWorkItem?
```

- [ ] **Step 2: Registrar o modo `.message`**

No `enum Mode`, adicionar `message`:

```swift
    enum Mode: Equatable {
        case closed, music, notification, hud, dictation, question, pomodoro, airpods, message
    }
```

No cálculo de `mode`, inserir `.message` logo abaixo de `.question` (prioridade alta, mas sem atropelar a pergunta interativa):

```swift
    var mode: Mode {
        if ask != nil { return .question }
        if incoming != nil { return .message }
        if dictation != nil { return .dictation }
        if activeNotification != nil { return .notification }
        if hud != nil { return .hud }
        if airpodsCard { return .airpods }
        if expanded { return .music }
        if pomodoro != nil { return .pomodoro }
        return .closed
    }
```

- [ ] **Step 3: Adicionar os métodos de mensagem ao `NotchViewModel`**

```swift
    // MARK: - Mensagens LAN

    /// Mostra o card de entrada. Sem resposta permitida, some sozinho (como
    /// notificação); com resposta, fica até o usuário responder ou fechar.
    func showIncoming(_ m: IncomingMessage) {
        incoming = m
        incomingWork?.cancel()
        guard !m.allowReply else { return }
        let work = DispatchWorkItem { [weak self] in self?.incoming = nil }
        incomingWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 6, execute: work)
    }

    func dismissIncoming() {
        incomingWork?.cancel()
        incoming = nil
    }

    /// Abre a conversa daquele peer na aba Mensagens.
    func openThread(peerID: String) {
        dismissIncoming()
        tab = .messages
        setExpandedDirect(true)
    }
```

- [ ] **Step 4: Renderizar o card `.message` no `NotchView.swift`**

No `switch vm.mode` de conteúdo (perto do `case .notification:`), adicionar:

```swift
            case .message:
                if let incoming = vm.incoming {
                    IncomingMessageView(vm: vm, incoming: incoming)
                        .frame(width: 360 - 40)
                        .padding(.top, topInset)
                        .padding(.bottom, 12)
                        .transition(.blurReplace.combined(with: .move(edge: .top)))
                }
```

No `currentSize` (switch de tamanho), adicionar antes do fechamento:

```swift
        case .message:
            let tall = vm.incoming?.allowReply == true
            return CGSize(width: 360, height: topInset + (tall ? 108 : 72))
```

E na lista `compact` (linha ~52) o `.message` **não** é compacto (é um card) — nada a mudar ali, pois `compact` lista só closed/hud/dictation/pomodoro.

- [ ] **Step 5: Adicionar a barra de abas ao `expandedContent`**

Localizar `private var expandedContent: some View {` (~linha 531). Envolver o conteúdo atual de música numa troca por aba. No topo do `VStack`/`Group` retornado, inserir a barra e, quando `vm.tab == .messages`, mostrar `MessagesView`:

```swift
    @ViewBuilder
    private var expandedContent: some View {
        VStack(spacing: 8) {
            tabBar
            if vm.tab == .messages {
                MessagesView(vm: vm)
            } else {
                musicContent   // (renomear o corpo antigo de expandedContent p/ musicContent)
            }
        }
    }

    private var tabBar: some View {
        HStack(spacing: 6) {
            tabButton("Música", .music, "music.note")
            tabButton("Mensagens", .messages, "bubble.left.and.bubble.right")
            Spacer()
        }
        .foregroundStyle(.white)
    }

    private func tabButton(_ title: String, _ tab: NotchViewModel.NotchTab,
                           _ icon: String) -> some View {
        Button { vm.tab = tab } label: {
            Label(title, systemImage: icon)
                .font(.caption.weight(.medium))
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(Capsule().fill(.white.opacity(vm.tab == tab ? 0.22 : 0.08)))
        }
        .buttonStyle(.plain)
    }
```

> Renomear o corpo atual de `expandedContent` (todo o conteúdo de música/shelf/pomodoro/mirror) para uma nova propriedade `private var musicContent: some View { ... }` com o mesmo conteúdo. A `NotchView` já recebe `shelf` e `vm`; `MessagesView(vm:)` usa os objetos de ambiente (Task 8 injeta `LANMessaging`/`MessageStore`/`AppSettings` via `.environmentObject`).

- [ ] **Step 6: Compilar (vai falhar até Task 6/7 criarem as views — verificação parcial)**

Run: `cd /Users/luccassilveira/Desktop/knobler && xcrun swiftc -typecheck -target arm64-apple-macos14.2 Knobler/NotchViewModel.swift`
Expected: `NotchViewModel.swift` sozinho compila (exit 0). O build completo só fecha após Task 7 — **não** commitar quebrado; ver Step 7.

- [ ] **Step 7: Commit (parcial, do ViewModel; NotchView fica junto de Task 7)**

```bash
cd /Users/luccassilveira/Desktop/knobler
git add Knobler/NotchViewModel.swift
git commit -m "feat(mensagens): estado de aba + modo de card no NotchViewModel"
```

> As edições de `NotchView.swift` (Steps 4-5) dependem de `MessagesView`/`IncomingMessageView` (Tasks 6-7); serão commitadas no fim da Task 7, quando o build fecha.

---

### Task 6: MessagesView — lista de peers, conversa e envio

A aba: quem está online → conversa (histórico) → escrever com toggle "permite resposta".

**Files:**
- Create: `Knobler/MessagesView.swift`

**Interfaces:**
- Consumes: `NotchViewModel` (Task 5), `LANMessaging`/`MessageStore`/`AppSettings` (ambiente), `Peer`/`PeerMessage` (Task 1).
- Produces: `struct MessagesView: View` (init `MessagesView(vm: NotchViewModel)`).

- [ ] **Step 1: Criar `Knobler/MessagesView.swift`**

```swift
//
//  MessagesView.swift
//  Knobler
//
//  Aba de Mensagens LAN no notch: lista de online → conversa → escrever.
//

import SwiftUI

struct MessagesView: View {
    @ObservedObject var vm: NotchViewModel
    @EnvironmentObject var lan: LANMessaging
    @EnvironmentObject var store: MessageStore

    @State private var selectedPeerID: String?
    @State private var draft = ""
    @State private var allowReply = true

    var body: some View {
        Group {
            if lan.permissionDenied {
                info("Libere a Rede Local em Ajustes › Privacidade › Rede Local.")
            } else if let id = selectedPeerID {
                conversation(peerID: id)
            } else {
                peerList
            }
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Lista de online

    private var peerList: some View {
        VStack(alignment: .leading, spacing: 6) {
            if lan.peers.isEmpty {
                info("Ninguém online na rede.")
            } else {
                ForEach(lan.peers) { peer in
                    Button { open(peer.id) } label: { peerRow(peer) }
                        .buttonStyle(.plain)
                }
            }
        }
    }

    private func peerRow(_ peer: Peer) -> some View {
        HStack(spacing: 8) {
            avatar(peerID: peer.id, name: peer.name).frame(width: 28, height: 28)
            Text(peer.name).font(.footnote.weight(.medium))
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.white.opacity(0.4))
        }
        .padding(.horizontal, 8).padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 8).fill(.white.opacity(0.08)))
    }

    // MARK: Conversa

    private func conversation(peerID: String) -> some View {
        let peer = lan.peer(withID: peerID)
        let name = peer?.name ?? store.name(for: peerID) ?? "?"
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Button { selectedPeerID = nil } label: {
                    Image(systemName: "chevron.left")
                }.buttonStyle(.plain)
                avatar(peerID: peerID, name: name).frame(width: 22, height: 22)
                Text(name).font(.footnote.weight(.semibold))
                Spacer()
                if peer == nil {
                    Text("offline").font(.caption2).foregroundStyle(.white.opacity(0.4))
                }
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(store.messages(for: peerID)) { bubble($0) }
                }
            }
            .frame(maxHeight: 160)
            composer(peer: peer)
        }
    }

    private func bubble(_ m: PeerMessage) -> some View {
        HStack {
            if !m.incoming { Spacer(minLength: 24) }
            VStack(alignment: m.incoming ? .leading : .trailing, spacing: 1) {
                Text(m.text).font(.footnote)
                if !m.incoming, !m.delivered {
                    Text("não entregue").font(.caption2).foregroundStyle(.orange)
                }
            }
            .padding(.horizontal, 8).padding(.vertical, 5)
            .background(RoundedRectangle(cornerRadius: 8)
                .fill(.white.opacity(m.incoming ? 0.10 : 0.22)))
            if m.incoming { Spacer(minLength: 24) }
        }
    }

    private func composer(peer: Peer?) -> some View {
        HStack(spacing: 6) {
            Toggle("", isOn: $allowReply).labelsHidden().toggleStyle(.switch).scaleEffect(0.7)
                .help("Permite resposta")
            TextField("Mensagem…", text: $draft)
                .textFieldStyle(.plain).font(.footnote)
                .padding(.horizontal, 8).padding(.vertical, 5)
                .background(RoundedRectangle(cornerRadius: 8).fill(.white.opacity(0.08)))
                .onSubmit { sendDraft(to: peer) }
            Button { sendDraft(to: peer) } label: { Image(systemName: "paperplane.fill") }
                .buttonStyle(.plain).disabled(peer == nil || draft.isEmpty)
        }
    }

    // MARK: Ações

    private func open(_ peerID: String) {
        selectedPeerID = peerID
        if let peer = lan.peer(withID: peerID) {
            store.rememberName(peer.name, for: peerID)
            lan.fetchProfile(from: peer) { profile in
                if let jpeg = profile?.avatarJPEG { store.cacheAvatar(jpeg, for: peerID) }
            }
        }
    }

    private func sendDraft(to peer: Peer?) {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let peer, !text.isEmpty else { return }
        draft = ""
        let reply = allowReply
        lan.send(text, to: peer, allowReply: reply) { ok in
            store.append(PeerMessage(id: UUID().uuidString, peerID: peer.id, incoming: false,
                                     text: text, allowReply: reply, at: Date(), delivered: ok))
        }
    }

    // MARK: Helpers

    @ViewBuilder
    private func avatar(peerID: String, name: String) -> some View {
        if let img = store.avatar(for: peerID) {
            Image(nsImage: img).resizable().scaledToFill().clipShape(Circle())
        } else {
            ZStack {
                Circle().fill(.gray.opacity(0.35))
                Text(String(name.prefix(1)).uppercased())
                    .font(.caption2.weight(.semibold))
            }
        }
    }

    private func info(_ text: String) -> some View {
        Text(text).font(.caption).foregroundStyle(.white.opacity(0.6))
            .frame(maxWidth: .infinity, alignment: .center).padding(.vertical, 12)
    }
}
```

- [ ] **Step 2: Verificar type-check isolado**

Run: `cd /Users/luccassilveira/Desktop/knobler && xcrun swiftc -typecheck -target arm64-apple-macos14.2 Knobler/MessagesView.swift Knobler/NotchViewModel.swift Knobler/Peer.swift Knobler/MessageStore.swift Knobler/LANMessaging.swift Knobler/Wire.swift Knobler/AppSettings.swift 2>&1 | tail -5`
Expected: sem erros (exit 0). Avisos de `@EnvironmentObject` são normais.

- [ ] **Step 3: Commit**

```bash
cd /Users/luccassilveira/Desktop/knobler
git add Knobler/MessagesView.swift
git commit -m "feat(mensagens): MessagesView (lista de online + conversa + envio)"
```

---

### Task 7: IncomingMessageView — card de entrada + fechar o build

O card que desce do notch quando chega mensagem (foto + nome + texto + resposta rápida). Fecha as edições de `NotchView.swift` da Task 5.

**Files:**
- Create: `Knobler/IncomingMessageView.swift`
- Modify: `Knobler/NotchView.swift` (as edições de Task 5, Steps 4-5, agora compiláveis)

**Interfaces:**
- Consumes: `NotchViewModel`, `NotchViewModel.IncomingMessage` (Task 5), `MessageStore` (ambiente).
- Produces: `struct IncomingMessageView: View` (init `IncomingMessageView(vm:incoming:)`).

- [ ] **Step 1: Criar `Knobler/IncomingMessageView.swift`**

```swift
//
//  IncomingMessageView.swift
//  Knobler
//
//  Card que desce do notch quando chega uma mensagem LAN: foto + nome +
//  texto e, se permitido, resposta rápida. Clicar abre a conversa na aba.
//

import SwiftUI

struct IncomingMessageView: View {
    @ObservedObject var vm: NotchViewModel
    @EnvironmentObject var store: MessageStore
    let incoming: NotchViewModel.IncomingMessage

    @State private var reply = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button { vm.openThread(peerID: incoming.peerID) } label: { header }
                .buttonStyle(.plain)
            if incoming.allowReply { replyField }
        }
        .foregroundStyle(.white)
    }

    private var header: some View {
        HStack(spacing: 8) {
            avatar.frame(width: 30, height: 30)
            VStack(alignment: .leading, spacing: 1) {
                Text(incoming.name).font(.footnote.weight(.semibold))
                Text(incoming.text).font(.caption).foregroundStyle(.white.opacity(0.75))
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
            Button { vm.dismissIncoming() } label: {
                Image(systemName: "xmark.circle.fill").foregroundStyle(.white.opacity(0.5))
            }.buttonStyle(.plain)
        }
    }

    private var replyField: some View {
        HStack(spacing: 6) {
            TextField("Responder…", text: $reply)
                .textFieldStyle(.plain).font(.footnote)
                .padding(.horizontal, 8).padding(.vertical, 5)
                .background(RoundedRectangle(cornerRadius: 8).fill(.white.opacity(0.10)))
                .onSubmit(send)
            Button(action: send) { Image(systemName: "paperplane.fill") }
                .buttonStyle(.plain).disabled(reply.isEmpty)
        }
    }

    private func send() {
        let text = reply.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        reply = ""
        vm.onSendReply?(incoming.peerID, text)
        vm.dismissIncoming()
    }

    @ViewBuilder
    private var avatar: some View {
        if let img = store.avatar(for: incoming.peerID) {
            Image(nsImage: img).resizable().scaledToFill().clipShape(Circle())
        } else {
            ZStack {
                Circle().fill(.gray.opacity(0.35))
                Text(String(incoming.name.prefix(1)).uppercased())
                    .font(.footnote.weight(.semibold))
            }
        }
    }
}
```

- [ ] **Step 2: Aplicar as edições pendentes de `NotchView.swift` (Task 5, Steps 4-5)**

Confirmar que `NotchView.swift` tem: (a) `case .message:` no switch de conteúdo, (b) `case .message:` no `currentSize`, (c) `expandedContent` dividido em `tabBar` + `musicContent`/`MessagesView`. (Ver Task 5 para o código exato.)

- [ ] **Step 3: Regenerar e build completo**

Run:
```bash
cd /Users/luccassilveira/Desktop/knobler && xcodegen generate && \
xcodebuild -project Knobler.xcodeproj -scheme Knobler -configuration Debug build 2>&1 | tail -3
```
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Commit (fecha Task 5 + Task 7)**

```bash
cd /Users/luccassilveira/Desktop/knobler
git add Knobler/IncomingMessageView.swift Knobler/NotchView.swift
git commit -m "feat(mensagens): card de entrada + integração na NotchView"
```

---

### Task 8: Fiação no app, snapshot e CHANGELOG

Instancia o motor, injeta os objetos de ambiente, liga recebimento→notch e envio-de-resposta, dispara o start ao abrir a aba, expõe diagnóstico no `GET /status`, atualiza o snapshot e o CHANGELOG.

**Files:**
- Modify: `Knobler/KnoblerApp.swift` (instanciar `LANMessaging`+`MessageStore`; injeção; fiação; start ao abrir aba; `/status`)
- Modify: `tools/snapshot.sh` (adicionar arquivos novos usados pela `NotchView`)
- Modify: `CHANGELOG.md`

**Interfaces:**
- Consumes: `LANMessaging`, `MessageStore`, `AppSettings`, `NotchViewModel` (todas as tasks anteriores).
- Produces: app funcional ponta a ponta.

- [ ] **Step 1: Localizar onde `NotchAPIServer`/`NotchViewModel` são criados no `KnoblerApp.swift`**

Run: `cd /Users/luccassilveira/Desktop/knobler && grep -n "NotchAPIServer\|NotchViewModel\|environmentObject\|statusProvider\|contentView\|NotchWindow(" Knobler/KnoblerApp.swift`
Expected: mostra o AppDelegate onde os singletons são montados e a `NotchView` é hospedada. Usar esses pontos nos steps seguintes.

> **Contexto do `KnoblerApp.swift` (verificado):** há um `NotchViewModel` por tela em
> `notches[displayID].viewModel`. Todo evento faz fan-out via
> `notches.values.forEach { $0.viewModel... }`. A `NotchView` é hospedada por tela em
> `placeWindows()` (loop ~linha 482) com assinatura real
> `NotchView(vm: viewModel, media: media, levels: audioLevels, shelf: shelf)`. A fiação
> por-vm (ex. `onAskAnswered`) vive dentro desse loop (linhas ~495-521). `import Combine`
> já existe no topo.

- [ ] **Step 2: Instanciar motor + store; injetar ambiente no host por tela**

No AppDelegate (junto de `private let apiServer = NotchAPIServer()`, ~linha 47), adicionar:

```swift
    let messageStore = MessageStore()
    let lanMessaging = LANMessaging()
    private var lanCancellables = Set<AnyCancellable>()
```

Em `placeWindows()`, trocar o `rootView:` do `NSHostingView` (linhas ~489-491) por:

```swift
                panel.contentView = NSHostingView(
                    rootView: NotchView(
                        vm: viewModel, media: media, levels: audioLevels, shelf: shelf)
                        .environmentObject(lanMessaging)
                        .environmentObject(messageStore)
                        .environmentObject(AppSettings.shared))
```

- [ ] **Step 3: Fiar recebimento (fan-out) e resposta/observação por-vm**

No `applicationDidFinishLaunching`, junto do resto da fiação (ex. perto de `apiServer.onNotification`, ~linha 192):

```swift
        // Mensagens LAN: perfil próprio + recebimento (card em todas as telas, como notificação)
        lanMessaging.profileProvider = { AppSettings.shared.myProfile() }
        lanMessaging.onIncoming = { [weak self] msg, profile in
            guard let self else { return }
            let name = profile?.name ?? self.messageStore.name(for: msg.peerID) ?? "?"
            self.messageStore.rememberName(name, for: msg.peerID)
            self.messageStore.append(msg)
            self.notches.values.forEach {
                $0.viewModel.showIncoming(.init(peerID: msg.peerID, name: name,
                                                text: msg.text, allowReply: msg.allowReply))
            }
            if let peer = self.lanMessaging.peer(withID: msg.peerID) {
                self.lanMessaging.fetchProfile(from: peer) { prof in
                    if let jpeg = prof?.avatarJPEG { self.messageStore.cacheAvatar(jpeg, for: msg.peerID) }
                }
            }
        }
```

Dentro do loop `placeWindows()`, no bloco de criação de cada `viewModel` (junto de `viewModel.onAskAnswered`, ~linha 497), adicionar a fiação por-vm:

```swift
                // resposta rápida do card → envia, grava o outgoing e some em todas as telas
                viewModel.onSendReply = { [weak self] peerID, text in
                    guard let self, let peer = self.lanMessaging.peer(withID: peerID) else { return }
                    self.lanMessaging.send(text, to: peer, allowReply: true) { ok in
                        self.messageStore.append(PeerMessage(id: UUID().uuidString, peerID: peerID,
                            incoming: false, text: text, allowReply: true, at: Date(), delivered: ok))
                    }
                    self.notches.values.forEach { $0.viewModel.dismissIncoming() }
                }
                // Rede Local: liga o Bonjour quando o usuário abre a aba Mensagens
                // (app ativo → prompt num momento sensato). start() é idempotente.
                viewModel.$tab
                    .filter { $0 == .messages }
                    .sink { [weak self] _ in self?.lanMessaging.start() }
                    .store(in: &lanCancellables)
```

- [ ] **Step 4: Liberar o teclado do painel para os campos de texto de Mensagens**

O painel só aceita teclado enquanto um card ativo existe (sink do `$ask`, ~linha 514). Os
campos de Mensagens (compositor na aba + resposta no card de entrada) também precisam. Logo
após o sink existente do `$ask`, adicionar um segundo sink no mesmo bloco por-vm:

```swift
                // teclado também quando: card de entrada com resposta, ou aba Mensagens aberta
                viewModel.$incoming.map { $0?.allowReply == true }
                    .combineLatest(viewModel.$tab, viewModel.$expanded)
                    .map { replyable, tab, expanded in replyable || (tab == .messages && expanded) }
                    .removeDuplicates()
                    .sink { [weak panel] active in
                        if active { panel?.allowsKeyboard = true }
                        else if panel?.viewModel?.ask == nil, panel?.isKeyWindow == true {
                            panel?.allowsKeyboard = false; panel?.resignKey()
                        }
                    }
                    .store(in: &lanCancellables)
```

> Se `NotchWindow` não expuser `viewModel`, simplificar o `else` para apenas
> `panel?.allowsKeyboard = false` quando `active == false` e a pergunta não estiver ativa —
> ou combinar este publisher com `viewModel.$ask.map { $0 != nil }` num único `active` que já
> cobre ask + mensagens, substituindo o sink original do `$ask` em vez de adicionar um segundo.

- [ ] **Step 5: Expor diagnóstico no `GET /status`**

Localizar o `apiServer.statusProvider` (~linha 307). Acrescentar ao dicionário `status`:

```swift
            status["lanMessaging"] = self?.lanMessaging.diagnostics ?? [:]
```

- [ ] **Step 6: Atualizar `tools/snapshot.sh`**

Adicionar `Knobler/MessagesView.swift` e `Knobler/IncomingMessageView.swift` à lista manual de fontes compiladas (junto de `NotchView.swift` e afins). Também `Knobler/Peer.swift`, `Knobler/Wire.swift`, `Knobler/LANMessaging.swift`, `Knobler/MessageStore.swift`, `Knobler/AppSettings.swift` se a `NotchView` passar a referenciá-los na compilação isolada.

Run (após editar): `cd /Users/luccassilveira/Desktop/knobler && ./tools/snapshot.sh 2>&1 | tail -5`
Expected: regenera os PNGs sem erro de compilação. (A aba Mensagens aparece vazia no snapshot — sem rede — o que é esperado.)

- [ ] **Step 7: Escrever o CHANGELOG**

Em `CHANGELOG.md`, sob `## [Unreleased]` (criar a seção se não existir), adicionar:

```markdown
### Adicionado
- Mensagens LAN: descubra outros Macs com Knobler na mesma rede e mande recados
  que aparecem no notch da pessoa, com nome e foto. Aba Mensagens no notch aberto,
  recado com ou sem resposta, histórico das últimas 20 conversas por pessoa.
  Identidade (nome/foto) configurável, pré-preenchida com a da conta do macOS.
```

- [ ] **Step 8: Build final + commit**

```bash
cd /Users/luccassilveira/Desktop/knobler && xcodegen generate && \
xcodebuild -project Knobler.xcodeproj -scheme Knobler -configuration Debug build 2>&1 | tail -3
```
Expected: `** BUILD SUCCEEDED **`.

```bash
git add Knobler/KnoblerApp.swift tools/snapshot.sh CHANGELOG.md Snapshots
git commit -m "feat(mensagens): fiação no app, snapshot e CHANGELOG"
```

- [ ] **Step 9: Verificação manual ponta a ponta (dois Macs)**

1. Instalar o build em dois Macs na mesma rede.
2. Em cada um, abrir Ajustes › Mensagens e conferir nome/foto.
3. Abrir o notch e a aba Mensagens no Mac A → conceder Rede Local no prompt → ver o Mac B na lista.
4. Mandar um recado **sem** resposta → confirmar que aparece no notch do B e some sozinho.
5. Mandar um recado **com** resposta → responder pelo card do B → confirmar a resposta chegando no A.
6. Reiniciar o app e confirmar que o histórico das últimas mensagens reaparece.
7. `curl -s localhost:4477/status | grep lanMessaging` → ver `peers`/`permissionDenied`.

---

## Notas de execução

- **Ordem de dependência:** Task 1 → 2 → 3 → 4 são independentes de UI e devem fechar build/self-check antes das Tasks 5-7. A `NotchView.swift` só compila completa ao fim da Task 7 (por isso o commit do ViewModel na Task 5 é separado).
- **Prompt de Rede Local:** se não aparecer, conferir Ajustes › Privacidade › Rede Local; testar em VM limpa; `NSBonjourServices` precisa listar `_knobler._tcp`.
- **Release:** ao terminar tudo e validar, publicar com `./tools/release.sh minor` (único escritor de versão/tag).
