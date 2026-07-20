# Notificações webhook — lado do app (Plano 2/2) — Implementação

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ligar o app do Knobler ao relay já no ar (`https://push.appzoi.com.br`): parear o dispositivo, manter um WebSocket vivo que recebe notificações e as exibe no notch (com avatar remoto e clique seguro), e uma aba de config com o link + rotacionar.

**Architecture:** Um `WebhookClient` (ObservableObject) encapsula pareamento (POST /register → Keychain), a conexão WSS (`URLSessionWebSocketTask`, auth por header, reconnect robusto) e entrega `PushNotification` → `NotchNotification` → `viewModel.enqueue`. O card de notificação já existente ganha avatar remoto (com guardas) e filtro de esquema no clique. Uma aba nova nos Ajustes mostra link/status/rotacionar. O relay é o Plano 1 (já implantado e validado E2E).

**Tech Stack:** Swift 5 · AppKit + SwiftUI · `URLSessionWebSocketTask` (nativo) · `Network` (NWPathMonitor) · Security (Keychain) · ImageIO (validação de imagem). Sem dependências novas.

**Plano 2 de 2.** O Plano 1 (relay) está completo e no ar. Este plano é o lado macOS; ele é testável de verdade contra o relay vivo.

## Contexto de pesquisa (já validado)

`docs/superpowers/specs/2026-07-20-webhook-notifications-research.md` contém a classe `WebhookClient` completa, o `KeychainStore` e o loader de avatar com as guardas — este plano os adapta. Os achados críticos (bugs da Apple DTS já contornados na classe): detecção de queda nativa demora 60s–3min → pong-timeout de app + NWPathMonitor + wake; `pongReceiveHandler` chamado 2× → idempotência por epoch; App Nap estrangula timers → `beginActivity`.

## Global Constraints

- **Deployment target macOS 14.2** (usuário roda 26). Swift 5, AppKit+SwiftUI, app `LSUIElement`.
- **Relay ao vivo:** base `https://push.appzoi.com.br`. Pareamento `POST /register` → `{deviceId, deviceSecret, publishToken}`. Rotação `POST /rotate` (header `Authorization: Bearer <deviceSecret>`) → `{publishToken}`. WebSocket `wss://push.appzoi.com.br/ws` com header `Authorization: Bearer <deviceSecret>` (**nunca** na query). Link público do usuário: `https://push.appzoi.com.br/w/<publishToken>`.
- **Mensagem recebida (JSON):** `{ "type":"notify", "title", "body", "iconURL"|null, "url"|null, "sound":bool, "id"|null, "ts":number }`.
- **Segredos no Keychain:** service `com.zoi.knobler.webhook`, uma conta por valor (`deviceId`/`deviceSecret`/`publishToken`), `kSecAttrAccessibleAfterFirstUnlock`. Nunca em UserDefaults, nunca em log.
- **WebhookClient:** `URLSessionWebSocketTask` nativo; auth por header; reconnect backoff+jitter (teto ~30s); pong-timeout de app (~10s) + `NWPathMonitor` + `NSWorkspace.didWakeNotification`; idempotência por **epoch**; `maximumMessageSize = 1<<20`; `ProcessInfo.beginActivity(.userInitiatedAllowingIdleSystemSleep)` enquanto conectado; **instância única** pela vida do app; `URLSessionConfiguration.default` (nunca `.background`); `shutdown()` no encerramento.
- **Clique (`openURL`):** abrir **só** `http`/`https`. Qualquer outro esquema: ignorar.
- **Avatar remoto:** só `https`; validar `Content-Type` de imagem; teto **512 KB** (cortar no download); timeout **5s**; validar bytes como imagem (`CGImageSource`); cache `NSCache`; fallback SF Symbol `bell.badge.fill`. Cortado se o toggle `loadRemoteImages` estiver off.
- **Settings:** `webhookNotifications` default **false** (opt-in); `loadRemoteImages` default **true**.
- **Aba de config** "Notificações externas": master toggle · indicador de conexão (verde/cinza) · link read-only + Copiar · Rotacionar link (confirmação) · toggle carregar imagens remotas · rodapé com exemplo `curl`.
- **Comentários e strings de UI em pt-BR** (convenção do projeto). Marcar simplificações com `// ponytail:`.
- **XcodeGen:** `sources: [Knobler]` inclui todo `.swift` da pasta automaticamente. Rodar `xcodegen generate` **após adicionar arquivo novo** (antes do build). **Nunca** editar `Knobler.xcodeproj` à mão.
- **Sem alvo XCTest no projeto.** Validação por task: `xcodegen generate` (se novo arquivo) → `xcodebuild -project Knobler.xcodeproj -scheme Knobler -configuration Debug build` → `./tools/snapshot.sh` (quando a mudança toca o render do notch) → E2E real contra o relay vivo (Task 8). Ao adicionar `.swift` que a `NotchView` use, **adicioná-lo à lista manual de `tools/snapshot.sh`**.
- **Versionamento:** feature pré-1.0 → **MINOR**. Escrever em `## [Unreleased]` do `CHANGELOG.md`; release no fim com `./tools/release.sh minor`.

---

## File Structure

Novos (sob `Knobler/`, auto-incluídos pelo XcodeGen):
- `Knobler/WebhookKeychainStore.swift` — Keychain: get/set/delete de `deviceId`/`deviceSecret`/`publishToken` (padrão do `DeepgramKeyStore`, múltiplas contas).
- `Knobler/RemoteAvatarLoader.swift` — loader assíncrono do avatar remoto com guardas + `NSCache`.
- `Knobler/WebhookClient.swift` — pareamento + WSS + reconnect + entrega. `ObservableObject`.
- `Knobler/WebhookSettingsView.swift` — a aba "Notificações externas".

Modificados:
- `Knobler/NotificationInterceptor.swift` — `NotchNotification` ganha `iconURL` e `webhookID`.
- `Knobler/NotchViewModel.swift` — `enqueue` substitui por `webhookID` (progresso).
- `Knobler/NotchView.swift` — `appIcon` carrega avatar remoto; `openSourceApp` filtra esquema.
- `Knobler/AppSettings.swift` — chaves `webhookNotifications`/`loadRemoteImages` + aba no `TabView`.
- `Knobler/KnoblerApp.swift` — instancia `WebhookClient`, liga/desliga no sink de settings, mapeia recebido → `enqueue`, `shutdown()` no quit.
- `tools/snapshot.sh` — adicionar `RemoteAvatarLoader.swift` à lista (a `NotchView` passa a usá-lo).

---

### Task 1: `WebhookKeychainStore.swift` — segredos no Keychain

**Files:**
- Create: `Knobler/WebhookKeychainStore.swift`

**Interfaces:**
- Produces: `enum WebhookKeychainStore` com `enum Account: String { case deviceId, deviceSecret, publishToken }` e `static func load(_:) -> String?`, `save(_:_:)`, `delete(_:)`, `clearAll()`.

- [ ] **Step 1: Criar `Knobler/WebhookKeychainStore.swift`**

```swift
//
//  WebhookKeychainStore.swift
//  Knobler
//
//  Segredos do relay de webhook no Keychain (não em UserDefaults, não em log).
//  Uma conta por valor sob o mesmo service. Acessível após o 1º unlock (o
//  agente lê no login sem interação). Espelha o padrão do DeepgramKeyStore.
//

import Security
import Foundation

enum WebhookKeychainStore {
    enum Account: String, CaseIterable { case deviceId, deviceSecret, publishToken }
    private static let service = "com.zoi.knobler.webhook"

    static func load(_ account: Account) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account.rawValue,
            kSecReturnData as String: true,
        ]
        var out: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &out) == errSecSuccess,
              let data = out as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func save(_ value: String, _ account: Account) {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account.rawValue,
        ]
        SecItemDelete(base as CFDictionary)
        guard !value.isEmpty else { return }
        var add = base
        add[kSecValueData as String] = Data(value.utf8)
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(add as CFDictionary, nil)
    }

    static func delete(_ account: Account) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account.rawValue,
        ]
        SecItemDelete(query as CFDictionary)
    }

    static func clearAll() { Account.allCases.forEach(delete) }
}
```

- [ ] **Step 2: Gerar projeto e compilar**

Run: `xcodegen generate && xcodebuild -project Knobler.xcodeproj -scheme Knobler -configuration Debug build 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Round-trip manual do Keychain (opcional, confirma leitura/escrita)**

Run:
```bash
cat > /tmp/kc-check.swift <<'SWIFT'
import Security; import Foundation
let service="com.zoi.knobler.webhook.selfcheck"
func save(_ v:String,_ a:String){var b:[String:Any]=[kSecClass as String:kSecClassGenericPassword,kSecAttrService as String:service,kSecAttrAccount as String:a];SecItemDelete(b as CFDictionary);b[kSecValueData as String]=Data(v.utf8);SecItemAdd(b as CFDictionary,nil)}
func load(_ a:String)->String?{let q:[String:Any]=[kSecClass as String:kSecClassGenericPassword,kSecAttrService as String:service,kSecAttrAccount as String:a,kSecReturnData as String:true];var o:CFTypeRef?;guard SecItemCopyMatching(q as CFDictionary,&o)==errSecSuccess,let d=o as? Data else{return nil};return String(data:d,encoding:.utf8)}
save("abc","deviceSecret"); print(load("deviceSecret")=="abc" ? "keychain OK" : "keychain FALHOU")
var del:[String:Any]=[kSecClass as String:kSecClassGenericPassword,kSecAttrService as String:service,kSecAttrAccount as String:"deviceSecret"];SecItemDelete(del as CFDictionary)
SWIFT
swift /tmp/kc-check.swift; rm -f /tmp/kc-check.swift
```
Expected: `keychain OK`.

- [ ] **Step 4: Commit**

```bash
git add Knobler/WebhookKeychainStore.swift Knobler.xcodeproj
git commit -m "feat(webhook): store de segredos no Keychain (deviceId/deviceSecret/publishToken)"
```

---

### Task 2: `NotchNotification` — campos `iconURL`/`webhookID` + replace no `enqueue`

**Files:**
- Modify: `Knobler/NotificationInterceptor.swift` (struct `NotchNotification`)
- Modify: `Knobler/NotchViewModel.swift` (`enqueue`)

**Interfaces:**
- Produces: `NotchNotification` com `var iconURL: String? = nil` e `var webhookID: String? = nil`. `NotchViewModel.enqueue` substitui a ativa/fila com mesmo `webhookID` não-nulo.

- [ ] **Step 1: Adicionar campos ao `NotchNotification`** — em `Knobler/NotificationInterceptor.swift`, dentro da struct (junto de `openURL`):

```swift
    /// Avatar remoto (webhook): URL https carregada com guardas no card.
    var iconURL: String? = nil
    /// ID de dedupe do webhook: mesmo id substitui em vez de empilhar (progresso).
    var webhookID: String? = nil
```

- [ ] **Step 2: Replace por `webhookID` no `enqueue`** — em `Knobler/NotchViewModel.swift`, substituir o método `enqueue`:

```swift
    func enqueue(_ notification: NotchNotification) {
        // progresso: mesmo webhookID substitui a ativa ou a enfileirada
        if let wid = notification.webhookID {
            if activeNotification?.webhookID == wid {
                activeNotification = notification
                scheduleDismiss()
                return
            }
            if let i = queue.firstIndex(where: { $0.webhookID == wid }) {
                queue[i] = notification
                return
            }
        }
        if activeNotification == nil {
            show(notification)
        } else {
            queue.append(notification)
        }
    }
```

- [ ] **Step 3: Compilar**

Run: `xcodebuild -project Knobler.xcodeproj -scheme Knobler -configuration Debug build 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Commit**

```bash
git add Knobler/NotificationInterceptor.swift Knobler/NotchViewModel.swift
git commit -m "feat(webhook): iconURL/webhookID no NotchNotification + replace por id no enqueue"
```

---

### Task 3: `RemoteAvatarLoader.swift` — avatar remoto com guardas + cache

**Files:**
- Create: `Knobler/RemoteAvatarLoader.swift`

**Interfaces:**
- Produces: `final class RemoteAvatarLoader: NSObject, ObservableObject` com `@Published private(set) var image: NSImage?` e `func load(_ urlString: String?)`. Guardas: só https, Content-Type de imagem, teto 512 KB (corta no download), timeout 5s, validação por `CGImageSource`, cache `NSCache` estático por URL. `image = nil` → o card usa o fallback.

- [ ] **Step 1: Criar `Knobler/RemoteAvatarLoader.swift`**

```swift
//
//  RemoteAvatarLoader.swift
//  Knobler
//
//  Carrega o avatar remoto de uma notificação de webhook com guardas de
//  segurança (o remetente não é confiável): só https, content-type de imagem,
//  teto de tamanho, timeout curto, validação real dos bytes, cache em memória.
//

import AppKit
import ImageIO

final class RemoteAvatarLoader: NSObject, ObservableObject, URLSessionDataDelegate {
    @Published private(set) var image: NSImage?

    private static let cache = NSCache<NSString, NSImage>()
    private static let maxBytes = 512 * 1024

    private var session: URLSession?
    private var received = Data()
    private var currentURL: URL?

    /// Carrega (ou usa o cache). `nil`/inválido/desligado → `image` fica nil (fallback).
    func load(_ urlString: String?) {
        guard let urlString, let url = URL(string: urlString),
              url.scheme?.lowercased() == "https" else { image = nil; return }
        if let cached = Self.cache.object(forKey: url.absoluteString as NSString) {
            image = cached; return
        }
        currentURL = url
        received = Data()
        var req = URLRequest(url: url)
        req.timeoutInterval = 5
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 5
        cfg.timeoutIntervalForResource = 8
        // ponytail: uma session por load; o loader é curto e por-card
        let s = URLSession(configuration: cfg, delegate: self, delegateQueue: nil)
        session = s
        s.dataTask(with: req).resume()
    }

    func urlSession(_ s: URLSession, dataTask: URLSessionDataTask,
                    didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        guard let http = response as? HTTPURLResponse,
              let ct = http.value(forHTTPHeaderField: "Content-Type")?.lowercased(),
              ct.hasPrefix("image/") else { completionHandler(.cancel); return }
        if let len = http.value(forHTTPHeaderField: "Content-Length"),
           let n = Int(len), n > Self.maxBytes { completionHandler(.cancel); return }
        completionHandler(.allow)
    }

    func urlSession(_ s: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        received.append(data)
        if received.count > Self.maxBytes { dataTask.cancel() }
    }

    func urlSession(_ s: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        defer { session = nil }
        guard error == nil, received.count <= Self.maxBytes,
              let src = CGImageSourceCreateWithData(received as CFData, nil),
              CGImageSourceGetCount(src) > 0,
              let cg = CGImageSourceCreateImageAtIndex(src, 0, nil) else { return }
        let img = NSImage(cgImage: cg, size: .zero)
        if let url = currentURL { Self.cache.setObject(img, forKey: url.absoluteString as NSString) }
        DispatchQueue.main.async { self.image = img }
    }
}
```

- [ ] **Step 2: Gerar + compilar**

Run: `xcodegen generate && xcodebuild -project Knobler.xcodeproj -scheme Knobler -configuration Debug build 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit**

```bash
git add Knobler/RemoteAvatarLoader.swift Knobler.xcodeproj
git commit -m "feat(webhook): loader de avatar remoto com guardas (https/content-type/512KB/timeout) + cache"
```

---

### Task 4: `NotchView` — avatar remoto no card + clique só http/https

**Files:**
- Modify: `Knobler/NotchView.swift` (`appIcon(for:)`, `openSourceApp`)
- Modify: `tools/snapshot.sh` (adicionar `RemoteAvatarLoader.swift`)

**Interfaces:**
- Consumes: `RemoteAvatarLoader` (Task 3), `NotchNotification.iconURL` (Task 2), `AppSettings.loadRemoteImages` (Task 6 define; usar `AppSettings.shared.loadRemoteImages`).

> Nota de ordem: esta task referencia `AppSettings.shared.loadRemoteImages`, criado na Task 6. Se executar 4 antes de 6, adicione temporariamente a checagem como `true`; a Task 6 introduz a flag real. (Ou execute a Task 6 antes desta — a ordem 6→4 também funciona.)

- [ ] **Step 1: Trocar `appIcon(for:)` para carregar avatar remoto** — em `Knobler/NotchView.swift`, substituir o método:

```swift
    private func appIcon(for notification: NotchNotification) -> some View {
        RemoteAvatarView(iconURL: notification.iconURL,
                         fallbackPath: Self.appPath(bundleID: notification.bundleID,
                                                    named: notification.appName))
            .frame(width: 32, height: 32)
    }
```

- [ ] **Step 2: Adicionar a subview `RemoteAvatarView`** — no fim de `NotchView.swift` (fora da struct principal, no mesmo arquivo):

```swift
/// Avatar do card: tenta o avatar remoto (com guardas) quando há iconURL e o
/// toggle está on; senão o ícone do app; senão o sino.
private struct RemoteAvatarView: View {
    let iconURL: String?
    let fallbackPath: String?
    @StateObject private var loader = RemoteAvatarLoader()

    var body: some View {
        Group {
            if let img = loader.image {
                Image(nsImage: img).resizable().scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 7))
            } else if let path = fallbackPath {
                Image(nsImage: NSWorkspace.shared.icon(forFile: path)).resizable()
            } else {
                Image(systemName: "bell.badge.fill").resizable().scaledToFit()
                    .padding(6).foregroundStyle(.white.opacity(0.6))
            }
        }
        .onAppear { reload() }
        .onChange(of: iconURL) { _ in reload() }   // notificações consecutivas com avatares diferentes
    }

    private func reload() {
        if AppSettings.shared.loadRemoteImages { loader.load(iconURL) }
    }
}
```

- [ ] **Step 3: Filtrar o esquema no clique** — em `openSourceApp`, trocar o primeiro bloco:

```swift
    private func openSourceApp(_ notification: NotchNotification) {
        if let raw = notification.openURL, let url = URL(string: raw),
           let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" {
            NSWorkspace.shared.open(url)
            return
        }
        if notification.supacodeWorktree != nil || notification.supacodeTab != nil {
            Self.focusSupacode(
                worktree: notification.supacodeWorktree, tab: notification.supacodeTab)
            return
        }
        if let bundleID = notification.bundleID,
           let app = NSRunningApplication.runningApplications(
               withBundleIdentifier: bundleID).first {
            app.activate()
            return
        }
        Self.runningApp(named: notification.appName)?.activate()
    }
```

- [ ] **Step 4: Adicionar `RemoteAvatarLoader.swift` à lista do snapshot** — em `tools/snapshot.sh`, na lista manual de arquivos `.swift` compilados junto da `NotchView`, incluir `Knobler/RemoteAvatarLoader.swift` (localize a lista existente e acrescente a linha, seguindo o formato dos vizinhos).

- [ ] **Step 5: Compilar + snapshot**

Run:
```bash
xcodebuild -project Knobler.xcodeproj -scheme Knobler -configuration Debug build 2>&1 | tail -5
./tools/snapshot.sh 2>&1 | tail -5
```
Expected: `** BUILD SUCCEEDED **`; `Snapshots/*.png` regenerados. Leia os PNGs de notificação: o card deve renderizar com o fallback (sino/ícone) — em snapshot não há avatar remoto — sem quebra de layout.

- [ ] **Step 6: Commit**

```bash
git add Knobler/NotchView.swift tools/snapshot.sh Snapshots
git commit -m "feat(webhook): avatar remoto no card do notch + clique restrito a http/https"
```

---

### Task 5: `WebhookClient.swift` — pareamento + WSS + reconnect

**Files:**
- Create: `Knobler/WebhookClient.swift`

**Interfaces:**
- Consumes: `WebhookKeychainStore` (Task 1), `NotchNotification` (Task 2).
- Produces: `final class WebhookClient: NSObject, ObservableObject, URLSessionWebSocketDelegate` com:
  - `@Published private(set) var connected: Bool`
  - `@Published private(set) var link: String?` (`https://push.appzoi.com.br/w/<publishToken>`)
  - `var onNotify: ((NotchNotification) -> Void)?`
  - `func start()`, `func stop()`, `func shutdown()`, `func rotate()`

- [ ] **Step 1: Criar `Knobler/WebhookClient.swift`**

```swift
//
//  WebhookClient.swift
//  Knobler
//
//  Liga o app ao relay (push.appzoi.com.br): pareia o device (POST /register →
//  Keychain), mantém um WebSocket vivo (auth por header), reconecta sozinho, e
//  entrega cada notificação recebida. Ver a pesquisa (R3) para o racional dos
//  contornos de bugs do URLSessionWebSocketTask (detecção lenta, double-pong).
//

import Foundation
import AppKit
import Network
import os

private struct PushNotification: Decodable {
    let type: String
    let title: String?; let body: String?; let iconURL: String?
    let url: String?; let sound: Bool?; let id: String?
}

final class WebhookClient: NSObject, ObservableObject, URLSessionWebSocketDelegate {
    @Published private(set) var connected = false
    @Published private(set) var link: String?
    var onNotify: ((NotchNotification) -> Void)?

    private let base = URL(string: "https://push.appzoi.com.br")!
    private let log = Logger(subsystem: "com.zoi.knobler", category: "webhook")
    private let queue = DispatchQueue(label: "com.zoi.knobler.webhook")

    private lazy var session: URLSession = {
        let c = URLSessionConfiguration.default          // NUNCA .background
        c.waitsForConnectivity = true; c.timeoutIntervalForRequest = 30
        let dq = OperationQueue(); dq.maxConcurrentOperationCount = 1
        return URLSession(configuration: c, delegate: self, delegateQueue: dq)
    }()

    private var task: URLSessionWebSocketTask?
    private var running = false
    private var epoch: UInt64 = 0
    private var attempt = 0
    private var pingWork, pongWork, reconnectWork: DispatchWorkItem?
    private let pingInterval: TimeInterval = 25, pongTimeout: TimeInterval = 10
    private let backoffCap: TimeInterval = 30
    private let path = NWPathMonitor(); private var online = true
    private var activity: NSObjectProtocol?

    // MARK: API pública

    func start() {
        queue.async {
            guard !self.running else { return }
            self.running = true
            self.installObservers()
            self.ensurePairedThenConnect()
        }
    }

    func stop() {
        queue.async {
            self.running = false
            self.teardown(reconnect: false)
            self.endActivity()
            DispatchQueue.main.async { self.connected = false }
        }
    }

    func shutdown() {
        stop()
        path.cancel()
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        session.invalidateAndCancel()
    }

    /// Rotaciona o publishToken (link novo); o WS não cai (usa o deviceSecret).
    func rotate() {
        queue.async {
            guard let secret = WebhookKeychainStore.load(.deviceSecret) else { return }
            var req = URLRequest(url: self.base.appendingPathComponent("rotate"))
            req.httpMethod = "POST"
            req.setValue("Bearer \(secret)", forHTTPHeaderField: "Authorization")
            self.session.dataTask(with: req) { [weak self] data, _, _ in
                guard let self, let data,
                      let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let pub = obj["publishToken"] as? String else { return }
                WebhookKeychainStore.save(pub, .publishToken)
                self.publishLink(pub)
            }.resume()
        }
    }

    // MARK: Pareamento

    private func ensurePairedThenConnect() {
        if let pub = WebhookKeychainStore.load(.publishToken),
           WebhookKeychainStore.load(.deviceSecret) != nil {
            publishLink(pub); connect(); return
        }
        // 1º uso: registra
        var req = URLRequest(url: base.appendingPathComponent("register"))
        req.httpMethod = "POST"
        session.dataTask(with: req) { [weak self] data, _, err in
            guard let self else { return }
            self.queue.async {
                guard self.running else { return }
                guard err == nil, let data,
                      let o = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let did = o["deviceId"] as? String,
                      let sec = o["deviceSecret"] as? String,
                      let pub = o["publishToken"] as? String else {
                    self.log.error("register falhou; retry")
                    self.queue.asyncAfter(deadline: .now() + 5) { self.ensurePairedThenConnect() }
                    return
                }
                WebhookKeychainStore.save(did, .deviceId)
                WebhookKeychainStore.save(sec, .deviceSecret)
                WebhookKeychainStore.save(pub, .publishToken)
                self.publishLink(pub)
                self.connect()
            }
        }.resume()
    }

    private func publishLink(_ pub: String) {
        let l = base.appendingPathComponent("w").appendingPathComponent(pub).absoluteString
        DispatchQueue.main.async { self.link = l }
    }

    // MARK: Conexão

    private func connect() {
        guard running, let secret = WebhookKeychainStore.load(.deviceSecret) else { return }
        reconnectWork?.cancel(); reconnectWork = nil
        epoch &+= 1
        var req = URLRequest(url: base.appendingPathComponent("ws"))
        req.timeoutInterval = 15
        req.setValue("Bearer \(secret)", forHTTPHeaderField: "Authorization")
        let t = session.webSocketTask(with: req)
        t.maximumMessageSize = 1 << 20
        task = t; t.resume()
    }

    private func teardown(reconnect: Bool) {
        epoch &+= 1
        pingWork?.cancel(); pongWork?.cancel()
        task?.cancel(with: .goingAway, reason: nil); task = nil
        DispatchQueue.main.async { self.connected = false }
        if reconnect { scheduleReconnect() }
    }

    private func handleDrop(_ reason: String) {
        guard running else { return }
        log.notice("drop: \(reason, privacy: .public)")
        teardown(reconnect: true)
    }

    private func scheduleReconnect() {
        guard running, online else { return }
        let ceil = min(backoffCap, pow(2, Double(attempt))); attempt += 1
        let delay = Double.random(in: 0...ceil)
        let item = DispatchWorkItem { [weak self] in guard let s = self, s.running else { return }; s.connect() }
        reconnectWork = item
        queue.asyncAfter(deadline: .now() + delay, execute: item)
    }

    private func forceReconnect() {
        guard running else { return }
        attempt = 0
        teardown(reconnect: false)
        let item = DispatchWorkItem { [weak self] in guard let s = self, s.running, s.online else { return }; s.connect() }
        reconnectWork = item
        queue.asyncAfter(deadline: .now() + Double.random(in: 0...1.5), execute: item)
    }

    // MARK: receive / ping

    private func receiveNext(_ e: UInt64) {
        guard let task, e == epoch else { return }
        task.receive { [weak self] r in self?.queue.async {
            guard let s = self, e == s.epoch else { return }
            switch r {
            case .success(let m): s.handle(m); s.receiveNext(e)
            case .failure(let err): s.handleDrop("receive \(err)")
            }
        } }
    }

    private func schedulePing(_ e: UInt64) {
        let item = DispatchWorkItem { [weak self] in
            guard let s = self, e == s.epoch, let t = s.task, s.running else { return }
            s.armPong(e)
            t.sendPing { [weak self] err in self?.queue.async {
                guard let s = self, e == s.epoch else { return }
                s.pongWork?.cancel()
                if let err { s.handleDrop("pong \(err)") } else { s.schedulePing(e) }
            } }
        }
        pingWork = item
        queue.asyncAfter(deadline: .now() + pingInterval, execute: item)
    }

    private func armPong(_ e: UInt64) {
        let item = DispatchWorkItem { [weak self] in
            guard let s = self, e == s.epoch, s.running else { return }
            s.handleDrop("pong timeout")
        }
        pongWork = item
        queue.asyncAfter(deadline: .now() + pongTimeout, execute: item)
    }

    // MARK: entrega

    private func handle(_ m: URLSessionWebSocketTask.Message) {
        let data: Data
        switch m { case .string(let s): data = Data(s.utf8); case .data(let d): data = d; @unknown default: return }
        guard let n = try? JSONDecoder().decode(PushNotification.self, from: data), n.type == "notify",
              let title = n.title, !title.isEmpty else { return }
        // ordem dos args = ordem de declaração na struct (memberwise init é sensível à ordem):
        // appName, title, body, [bundleID], [supacode*], openURL, iconURL, webhookID
        let note = NotchNotification(
            appName: nil, title: title, body: n.body ?? "",
            openURL: n.url, iconURL: n.iconURL, webhookID: n.id)
        let playSound = n.sound ?? false
        DispatchQueue.main.async {
            if playSound { NSSound(named: "Pop")?.play() }
            self.onNotify?(note)
        }
    }

    // MARK: observers (wake / rede) + App Nap

    private func installObservers() {
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(didWake),
            name: NSWorkspace.didWakeNotification, object: nil)
        path.pathUpdateHandler = { [weak self] p in self?.queue.async {
            guard let s = self else { return }
            let ok = p.status == .satisfied, was = s.online; s.online = ok
            if ok && !was { s.forceReconnect() }
            else if !ok, s.running { s.teardown(reconnect: false) }
        } }
        path.start(queue: queue)
        beginActivity()
    }

    @objc private func didWake() { queue.async { self.forceReconnect() } }

    private func beginActivity() {
        guard activity == nil else { return }
        activity = ProcessInfo.processInfo.beginActivity(
            options: .userInitiatedAllowingIdleSystemSleep, reason: "socket de push do Knobler")
    }
    private func endActivity() {
        if let a = activity { ProcessInfo.processInfo.endActivity(a); activity = nil }
    }

    // MARK: URLSessionWebSocketDelegate

    func urlSession(_ s: URLSession, webSocketTask t: URLSessionWebSocketTask, didOpenWithProtocol p: String?) {
        queue.async {
            guard t === self.task else { return }
            self.attempt = 0
            DispatchQueue.main.async { self.connected = true }
            let e = self.epoch
            self.receiveNext(e); self.schedulePing(e)
            self.log.notice("conectado")
        }
    }
    func urlSession(_ s: URLSession, webSocketTask t: URLSessionWebSocketTask, didCloseWith code: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        queue.async { guard t === self.task else { return }; self.handleDrop("close \(code.rawValue)") }
    }
    func urlSession(_ s: URLSession, task t: URLSessionTask, didCompleteWithError e: Error?) {
        queue.async { guard t === self.task else { return }; self.handleDrop("complete \(e?.localizedDescription ?? "nil")") }
    }
}
```

> Nota: o init de `NotchNotification` usa argumentos nomeados; confira a assinatura real da struct (é `let`/`var` sintetizado). Se o init sintetizado exigir todos os campos, use um init explícito com defaults ou preencha os campos após criar. Ajuste os nomes/ordem conforme a struct em `NotificationInterceptor.swift`.

- [ ] **Step 2: Gerar + compilar**

Run: `xcodegen generate && xcodebuild -project Knobler.xcodeproj -scheme Knobler -configuration Debug build 2>&1 | tail -8`
Expected: `** BUILD SUCCEEDED **`. (Se o init de `NotchNotification` reclamar, ajuste a construção de `note` conforme a struct real.)

- [ ] **Step 3: Commit**

```bash
git add Knobler/WebhookClient.swift Knobler.xcodeproj
git commit -m "feat(webhook): WebhookClient (pareamento + WSS + reconnect robusto + App Nap)"
```

---

### Task 6: `AppSettings` — chaves + aba "Notificações externas"

**Files:**
- Modify: `Knobler/AppSettings.swift` (chaves + tab)
- Create: `Knobler/WebhookSettingsView.swift`

**Interfaces:**
- Produces: `AppSettings.webhookNotifications` (default false), `AppSettings.loadRemoteImages` (default true); `WebhookSettingsView(client:)`.
- Consumes: `WebhookClient` (Task 5).

- [ ] **Step 1: Adicionar as chaves ao `AppSettings`** — em `Knobler/AppSettings.swift`, junto dos outros `@Published` (ex.: perto de `notchNotifications`):

```swift
    /// Recebe notificações externas via webhook (relay push.appzoi.com.br). Opt-in.
    @Published var webhookNotifications: Bool {
        didSet { UserDefaults.standard.set(webhookNotifications, forKey: "webhookNotifications") }
    }
    /// Baixa o avatar remoto das notificações de webhook (expõe o IP do Mac ao remetente).
    @Published var loadRemoteImages: Bool {
        didSet { UserDefaults.standard.set(loadRemoteImages, forKey: "loadRemoteImages") }
    }
```

E no `private init()`, junto dos outros:

```swift
        webhookNotifications = defaults.bool(forKey: "webhookNotifications") // default false: opt-in
        loadRemoteImages = flag("loadRemoteImages")                           // default true
```

- [ ] **Step 2: Criar `Knobler/WebhookSettingsView.swift`**

```swift
//
//  WebhookSettingsView.swift
//  Knobler
//
//  Aba "Notificações externas": liga/desliga, mostra o link do device + status
//  da conexão, e permite copiar/rotacionar o link.
//

import SwiftUI

struct WebhookSettingsView: View {
    @ObservedObject var settings = AppSettings.shared
    @ObservedObject var client: WebhookClient
    @State private var confirmRotate = false

    var body: some View {
        Form {
            Section {
                Toggle("Receber notificações externas", isOn: $settings.webhookNotifications)
            } footer: {
                Text("Um webhook no seu link vira um card no notch. Ligado = o app mantém uma conexão com o relay.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            if settings.webhookNotifications {
                Section("Seu link") {
                    HStack {
                        Circle().fill(client.connected ? .green : .secondary)
                            .frame(width: 8, height: 8)
                        Text(client.connected ? "Conectado" : "Offline")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    if let link = client.link {
                        HStack {
                            Text(link).font(.caption.monospaced())
                                .textSelection(.enabled).lineLimit(1).truncationMode(.middle)
                            Spacer()
                            Button("Copiar") {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(link, forType: .string)
                            }
                        }
                    } else {
                        Text("Gerando link…").font(.caption).foregroundStyle(.secondary)
                    }
                    Button("Rotacionar link", role: .destructive) { confirmRotate = true }
                        .confirmationDialog("Gerar um link novo? O link antigo para de funcionar.",
                                            isPresented: $confirmRotate, titleVisibility: .visible) {
                            Button("Gerar link novo", role: .destructive) { client.rotate() }
                            Button("Cancelar", role: .cancel) {}
                        }
                }
                Section {
                    Toggle("Carregar imagens remotas", isOn: $settings.loadRemoteImages)
                } footer: {
                    Text("Baixa o avatar da notificação. Desligue para não expor o IP do seu Mac a quem envia o webhook.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section {
                    Text("curl -X POST \(client.link ?? "<link>") -d 'title=Oi&body=Tudo bem'")
                        .font(.caption.monospaced()).textSelection(.enabled)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
    }
}
```

- [ ] **Step 3: Adicionar a aba ao `SettingsView`** — em `AppSettings.swift`, `SettingsView.body` recebe o `WebhookClient`. Como o `SettingsView` é instanciado pelo `AppDelegate` (Task 7), adicione um parâmetro. Trocar o `TabView`:

```swift
struct SettingsView: View {
    @ObservedObject var settings = AppSettings.shared
    @ObservedObject var webhookClient: WebhookClient
    @State private var deepgramKey = DeepgramKeyStore.load()

    var body: some View {
        TabView {
            generalTab
                .tabItem { Label("Geral", systemImage: "gearshape") }
            RemindersView()
                .tabItem { Label("Lembretes", systemImage: "bell.badge") }
            DescansoTabView()
                .tabItem { Label("Descanso", systemImage: "moon.zzz") }
            WebhookSettingsView(client: webhookClient)
                .tabItem { Label("Notificações externas", systemImage: "bell.and.waves.left.and.right") }
        }
        .frame(width: 400, height: 580)
    }
    // ... generalTab inalterado ...
}
```

- [ ] **Step 4: Gerar + compilar**

Run: `xcodegen generate && xcodebuild -project Knobler.xcodeproj -scheme Knobler -configuration Debug build 2>&1 | tail -8`
Expected: pode falhar em `SettingsView(...)` sem o argumento `webhookClient` — o call site é ajustado na Task 7. Se você executar 6 antes de 7, o build só fecha após a Task 7. Confirme que o **erro é só o call site de `SettingsView`** (não erro nos arquivos desta task). Se preferir build verde isolado, faça a Task 7 em seguida antes de validar.

- [ ] **Step 5: Commit**

```bash
git add Knobler/AppSettings.swift Knobler/WebhookSettingsView.swift Knobler.xcodeproj
git commit -m "feat(webhook): chaves de settings + aba Notificações externas (link/status/rotacionar)"
```

---

### Task 7: `KnoblerApp` — fiação do `WebhookClient` no AppDelegate

**Files:**
- Modify: `Knobler/KnoblerApp.swift`

**Interfaces:**
- Consumes: `WebhookClient` (Task 5), `SettingsView(webhookClient:)` (Task 6), `viewModel.enqueue` (Task 2).

- [ ] **Step 1: Declarar a instância** — junto de `private let apiServer = NotchAPIServer()`:

```swift
    let webhookClient = WebhookClient()
```

- [ ] **Step 2: Mapear recebido → enqueue em todos os notches** — no `applicationDidFinishLaunching` (perto de `apiServer.onNotification`):

```swift
        webhookClient.onNotify = { [weak self] notification in
            self?.notches.values.forEach { $0.viewModel.enqueue(notification) }
        }
```

- [ ] **Step 3: Ligar/desligar no sink de settings** — dentro do `sink` do `AppSettings.shared.objectWillChange` (junto de `if AppSettings.shared.localAPI { apiServer.start() }`):

```swift
                    if AppSettings.shared.webhookNotifications {
                        self?.webhookClient.start()
                    } else {
                        self?.webhookClient.stop()
                    }
```

- [ ] **Step 4: Passar o client pro `SettingsView`** — em `openSettings()`, trocar:

```swift
            window.contentView = NSHostingView(rootView: SettingsView(webhookClient: webhookClient))
```

- [ ] **Step 5: `shutdown()` no encerramento** — em `applicationWillTerminate`, adicionar:

```swift
        webhookClient.shutdown()
```

- [ ] **Step 6: Gerar + compilar (agora fecha verde)**

Run: `xcodegen generate && xcodebuild -project Knobler.xcodeproj -scheme Knobler -configuration Debug build 2>&1 | tail -8`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 7: Commit**

```bash
git add Knobler/KnoblerApp.swift Knobler.xcodeproj
git commit -m "feat(webhook): fiação do WebhookClient no AppDelegate (start/stop, onNotify→enqueue, shutdown)"
```

---

### Task 8: E2E real contra o relay vivo + CHANGELOG

**Files:**
- Modify: `CHANGELOG.md`

- [ ] **Step 1: Escrever no CHANGELOG** — em `## [Unreleased]` do `CHANGELOG.md`, adicionar:

```markdown
### Adicionado
- Notificações externas via webhook: cada dispositivo tem um link próprio
  (`https://push.appzoi.com.br/w/<token>`) que recebe título, descrição, avatar
  e ação de clique, exibidos no notch. Relay próprio na VPS; conexão WebSocket
  do Mac; opt-in em Ajustes › Notificações externas.
```

- [ ] **Step 2: Build + instalar + rodar o app**

Run:
```bash
xcodebuild -project Knobler.xcodeproj -scheme Knobler -configuration Debug build 2>&1 | tail -3
APP=$(find ~/Library/Developer/Xcode/DerivedData -name Knobler.app -path '*Debug*' 2>/dev/null | head -1)
pkill -x Knobler 2>/dev/null; sleep 1
open "$APP"
```
Expected: o app abre (agente na barra). Abrir Ajustes › **Notificações externas**, ligar o toggle. O status deve virar **Conectado** (verde) e um **link** aparecer.

- [ ] **Step 3: E2E — publicar um webhook e ver no notch**

Copie o link exibido na aba e publique (substitua `<LINK>`):
```bash
curl -X POST "<LINK>" -H 'Content-Type: application/json' \
  -d '{"title":"Deploy finalizado","body":"produção no ar","url":"https://github.com","sound":true,"id":"t1"}'
```
Expected: `{"ok":true,"delivered":"push"}` e **um card aparece no notch** com título/descrição. Clicar abre `github.com` no navegador. Publicar de novo com o mesmo `"id":"t1"` e corpo diferente → **atualiza o mesmo card** (não empilha).

- [ ] **Step 4: E2E — offline/fila** (opcional): desligue o toggle (desconecta), publique um webhook (retorna `queued`), religue → o card aparece ao reconectar (drena a fila).

- [ ] **Step 5: Commit**

```bash
git add CHANGELOG.md
git commit -m "docs(webhook): CHANGELOG do lado app; E2E validado contra o relay vivo"
```

---

## Self-Review

**Cobertura da spec (Peça 2/3/4 — app):**
- `WebhookClient` (pareamento, WSS header-auth, reconnect, App Nap, shutdown) → Task 5. ✅
- Keychain (3 segredos, afterFirstUnlock) → Task 1. ✅
- Avatar remoto com guardas + fallback → Tasks 3, 4. ✅
- Clique só http/https → Task 4. ✅
- Replace por `id` → Task 2. ✅
- Aba de config (toggle/status/link/copiar/rotacionar/imagens) → Task 6. ✅
- Fiação no AppDelegate (start/stop/enqueue/shutdown) → Task 7. ✅
- Settings opt-in (webhookNotifications false, loadRemoteImages true) → Task 6. ✅
- E2E real → Task 8. ✅

**Placeholders:** nenhum "TBD/TODO"; todo passo tem código/comando. Duas notas de ordem (Task 4↔6, 6↔7) são dependências explícitas, não placeholders.

**Consistência de tipos:** `WebhookKeychainStore.Account`, `WebhookClient.{connected, link, onNotify, start, stop, shutdown, rotate}`, `RemoteAvatarLoader.{image, load}`, `NotchNotification.{iconURL, webhookID}`, `AppSettings.{webhookNotifications, loadRemoteImages}`, `SettingsView(webhookClient:)` — usados de forma consistente entre as tasks.

**Risco conhecido (validar na execução):** (1) o init sintetizado de `NotchNotification` pode exigir ordem/args específicos — a construção de `note` na Task 5 pode precisar de ajuste (nota no passo). (2) a lista manual de `tools/snapshot.sh` precisa do `RemoteAvatarLoader.swift` (Task 4). (3) A detecção de queda/App Nap só se valida em uso real (desligar Wi-Fi, deixar ocioso) — plano B `NWConnection` documentado na pesquisa se ficar frágil.
