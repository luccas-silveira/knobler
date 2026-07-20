# Notificações externas via webhook — pesquisa (de-risk pré-plano)

**Data:** 2026-07-20
**Alimenta:** `2026-07-20-webhook-notifications-design.md` → plano de implementação
**Método:** 5 workstreams (R1–R5) em paralelo, modo aprofundado, múltiplas fontes.

> Este documento captura o que verificamos em fontes reais e **como isso muda/confirma
> a spec**. Os trechos de código aqui são os artefatos "carregadores" (load-bearing)
> prontos pra adaptar no plano.

---

## Sumário executivo — decisões e refinamentos

| Ponto | Antes (spec) | Depois da pesquisa | Motivo |
|---|---|---|---|
| Entropia do token | 128 bits | **256 bits** (32 bytes, base64url → 43 chars) | Custo zero, é o SOTA (ntfy/Pushcut na prática); "faz o que for SOTA". |
| Auth do WebSocket | `?s=<deviceSecret>` na query | **Header `Authorization: Bearer <deviceSecret>`** (não a query) | Query string cai no **access log do nginx** → segredo vazado em log. Header não. `URLRequest` deixa setar header. |
| Onde fica o rate limit | "no relay" (vago) | **Na app Node, token-bucket em memória** por device (sem Redis) + limite leve por IP no nginx (defesa em profundidade) | Token está no **path** (`/w/<token>`), o nginx não chaveia bem por path; e não queremos adicionar Redis num box já cheio. |
| better-sqlite3 | "better-sqlite3" | **fixar em `better-sqlite3@11`** (v12+ dropa Node 18) | Node 18.19 na VPS; v12 exige Node 20+. |
| App Nap (agente LSUIElement) | não previsto | **`ProcessInfo.beginActivity(.userInitiatedAllowingIdleSystemSleep)`** enquanto o socket deve viver | Sem isso o App Nap estrangula os timers de ping e o socket morre por idle. Deixa o Mac dormir normalmente (tratado no wake). |
| Detecção de queda no Mac | "reconnect com backoff" | idem, **mas** com pong-timeout de aplicação (~10s) + `NWPathMonitor` + wake, porque o erro nativo demora 60s–3min | Bug documentado da Apple (thread 678384). |
| Transporte offline | WS + fila drenada no reconnect | **mantido** (R5 sugeria polling `since=`; nosso WS+fila já entrega o mesmo, melhor UX) | Decisão já tomada; WS+fila = "since last delivery" implícito. |
| Rate limit números | 20/min burst 5 | **mantido** (R5 sugeriu 300/min; é serviço genérico, nosso volume é baixo) | Conservador de propósito; tunável. |
| Rotação do link | token antigo morre na hora | **mantido** (R5 sugeriu grace period 7d; opcional/futuro) | Simplicidade; "queimar e trocar". |
| Fallback de transporte | — | **`NWConnection`/`NWProtocolWebSocket`** se o `URLSessionWebSocketTask` se mostrar frágil em campo | Apple DTS (Quinn) recomenda Network framework pra código novo; guardamos como plano B. |

**Veredito:** a arquitetura da spec está sólida e confirmada por prior art (ntfy/Pushcut).
Nenhuma mudança estrutural — só os refinamentos acima. Pronto pra planejar.

---

## R1 — Relay: WebSocket server + SQLite (Node 18 + pm2)

**`ws`** (v8.x, compatível Node 18): usar servidor `http` nativo + `WebSocketServer({ noServer: true })`
e autenticar **no evento `upgrade`** (antes do handshake). Não usar `verifyClient` (deprecated).

```js
const http = require('http');
const { WebSocketServer } = require('ws');

const server = http.createServer(handleHttp);      // POST /register, /rotate, /w/<token>, /health
const wss = new WebSocketServer({ noServer: true });
const clients = new Map();                          // deviceId -> ws

server.on('upgrade', (req, socket, head) => {
  // AUTH via header (não query — evita vazar no log do nginx)
  const auth = req.headers['authorization'] || '';
  const secret = auth.startsWith('Bearer ') ? auth.slice(7) : null;
  const device = secret && lookupDeviceBySecretHash(sha256(secret));  // hash lookup
  if (!device || !req.url.startsWith('/ws')) {
    socket.write('HTTP/1.1 401 Unauthorized\r\n\r\n'); socket.destroy(); return;
  }
  wss.handleUpgrade(req, socket, head, (ws) => {
    ws.deviceId = device.device_id;
    // fecha conexão antiga do mesmo device
    clients.get(ws.deviceId)?.close(1000, 'replaced');
    clients.set(ws.deviceId, ws);
    ws.isAlive = true;
    ws.on('pong', () => { ws.isAlive = true; });
    ws.on('close', () => { if (clients.get(ws.deviceId) === ws) clients.delete(ws.deviceId); });
    ws.on('error', () => { if (clients.get(ws.deviceId) === ws) clients.delete(ws.deviceId); });
    drainQueue(ws.deviceId, ws);                    // entrega o que chegou offline
  });
});

// heartbeat global (ws pattern oficial): 30s, terminate quem não respondeu
setInterval(() => {
  for (const [id, ws] of clients) {
    if (ws.isAlive === false) { ws.terminate(); clients.delete(id); continue; }
    ws.isAlive = false; ws.ping();
  }
}, 30_000).unref();
```

**better-sqlite3@11** (Node 18). Build no Ubuntu 24.04: `apt install -y build-essential python3`
(node-gyp exige Python 3). WAL + prepared statements:

```js
const Database = require('better-sqlite3');
const db = new Database('relay.db', { timeout: 5000 });
db.pragma('journal_mode = WAL');
db.pragma('synchronous = NORMAL');
// prepared statements reutilizados (não montar SQL por string)
const qInsert = db.prepare('INSERT INTO queued (device_id, payload, dedupe_id, created_at) VALUES (?,?,?,?)');
```

**Graceful shutdown pra pm2** (SIGINT/SIGTERM): parar heartbeat, `ws.close(1001)` em todos,
`db.pragma('wal_checkpoint(RESTART)')`, `db.close()`, sair. `kill_timeout: 10000` no ecosystem.

**pm2:** usar **fork mode** (`instances: 1`). Cluster mode exigiria Redis + sticky sessions
pra WebSocket — desnecessário aqui.

**Alternativa se o build nativo falhar:** `node-sqlite3-wasm` (file-based, WAL, mais lento).
`node:sqlite` **não** serve (só Node 22+). `sql.js` só em memória. Ficar no better-sqlite3@11.

**Riscos:** WAL cresce sem checkpoint (fazer no shutdown + cron opcional); mismatch de versão
Node → `npm rebuild better-sqlite3`.

Fontes: github.com/websockets/ws (doc + examples), github.com/WiseLibs/better-sqlite3
(releases, performance.md, api.md), pm2.io/docs graceful-shutdown.

---

## R2 — Relay: borda (nginx + certbot + rate limit)

**nginx WebSocket**: `map` no bloco `http` + `location /ws` dedicado. **Nunca** hardcodar
`Connection "upgrade"** (quebra keep-alive das rotas HTTP normais).

```nginx
# bloco http {} (uma vez)
map $http_upgrade $connection_upgrade { default upgrade; '' close; }

server {
  server_name push.appzoi.com.br;
  listen 443 ssl;                     # certbot preenche ssl_certificate etc.
  client_max_body_size 64k;           # payload é minúsculo (sem imagem embutida)

  location /ws {                      # WebSocket (mais específico que "/", ganha)
    proxy_pass http://127.0.0.1:PORTA;
    proxy_http_version 1.1;
    proxy_set_header Upgrade $http_upgrade;
    proxy_set_header Connection $connection_upgrade;
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto https;
    proxy_read_timeout 3600s;         # conexão longa; heartbeat de 30s reseta o timer
    proxy_send_timeout 3600s;
    proxy_buffering off;
    # não logar o Authorization; access_log padrão não loga header, OK
  }

  location / {                        # HTTP: /register, /rotate, /w/<token>, /health
    proxy_pass http://127.0.0.1:PORTA;
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto https;
    proxy_read_timeout 120s;
  }
}
```

**certbot** (2.9, plugin nginx): **DNS A `push.appzoi.com.br` → 147.79.87.179 tem que
existir e resolver ANTES** (challenge HTTP-01). Criar o vhost com `listen 80` primeiro,
`nginx -t && reload`, depois `certbot --nginx -d push.appzoi.com.br` (ele adiciona o 443 +
redirect + renovação automática via systemd timer). Validar com `certbot renew --dry-run`.

**Rate limit — decisão: na app Node, token-bucket em memória por device** (o token está no
path `/w/<token>`, então o nginx não chaveia bem; e não vamos subir Redis). 20/min, burst 5,
→ `429` com `Retry-After`. Implementação simples própria (Map<deviceId,{tokens,ts}>) ou
`rate-limiter-flexible` com backend **memory** (não Redis). **Somar** um limite leve por IP
no nginx como defesa em profundidade (opcional):

```nginx
# http {}: teto grosso por IP, só anti-flood
limit_req_zone $binary_remote_addr zone=push_ip:10m rate=120r/m;
# no location / : limit_req zone=push_ip burst=30 nodelay;
```

**Riscos:** se a app não mandar heartbeat, o socket morre no `proxy_read_timeout`; renovação
do certbot falhar silenciosamente (monitorar `/var/log/letsencrypt`).

Fontes: nginx.org/en/docs/http/websocket.html, certbot.eff.org, npm rate-limiter-flexible,
nginx docs rate limiting.

---

## R3 — Mac: cliente WebSocket (`URLSessionWebSocketTask`) — o achado crítico

**Dois bugs documentados pela Apple DTS que quase todo tutorial ignora:**
1. **Detecção de queda lentíssima:** depois que a rede some, `receive`/pong/delegate só
   falham em **60s–3min** (thread 678384). → não dá pra confiar no erro nativo pra reconectar
   rápido.
2. **`pongReceiveHandler` chamado 2×:** se a task é cancelada logo após um ping, o handler
   pode ser invocado duas vezes; embrulhado em `withCheckedThrowingContinuation` → **crash**
   (continuation resumida 2×) (thread 756482). → usar completion handler cru + idempotência.

**Mitigação (tudo na classe abaixo):** pong-timeout **de aplicação (~10s)** + `NWPathMonitor`
(reconecta quando a rede volta; para de tentar quando some) + `NSWorkspace.didWakeNotification`
(reconecta ao acordar) + **epoch token** que invalida todos os closures de uma conexão morta
de uma vez (mata reconnects duplicados e o double-call do pong) + **tudo numa serial queue**
(sem locks). `maximumMessageSize` explícito (default não é documentado). **Nunca**
`URLSessionConfiguration.background` (WebSocket não é suportado lá). Cuidado com o **retain
cycle**: `URLSession` retém o delegate até `invalidateAndCancel()` → manter **uma** instância
pela vida do app e chamar `shutdown()` no encerramento (não recriar a cada toggle).

**App Nap:** um LSUIElement ocioso sofre App Nap, que estica os timers de ping → socket morre.
Segurar `ProcessInfo.processInfo.beginActivity(options: .userInitiatedAllowingIdleSystemSleep,
reason: "socket de push")` enquanto conectado (a variante `…AllowingIdleSystemSleep` **permite**
o Mac dormir — a gente quer isso e trata no wake).

Classe pronta (adaptar no plano — é o esqueleto do `WebhookClient.swift`):

```swift
import Foundation; import AppKit; import Network; import os

struct PushNotification: Decodable {
    let type: String; let title: String?; let body: String?
    let iconURL: String?; let url: String?; let sound: String?; let id: String?; let ts: Double?
}

final class WebhookClient: NSObject, URLSessionWebSocketDelegate {
    enum State { case stopped, connecting, connected, waiting }
    var onNotify: ((PushNotification) -> Void)?
    var onStateChange: ((State) -> Void)?

    private let url: URL
    private let deviceSecret: String                 // vai no header Authorization
    private let queue = DispatchQueue(label: "com.knobler.webhook")
    private lazy var session: URLSession = {
        let c = URLSessionConfiguration.default      // NUNCA .background
        c.waitsForConnectivity = true; c.timeoutIntervalForRequest = 30
        let dq = OperationQueue(); dq.maxConcurrentOperationCount = 1
        return URLSession(configuration: c, delegate: self, delegateQueue: dq)
    }()
    private var task: URLSessionWebSocketTask?
    private var state: State = .stopped { didSet { DispatchQueue.main.async { self.onStateChange?(self.state) } } }
    private var epoch: UInt64 = 0
    private var attempt = 0
    private var pingWork, pongWork, reconnectWork: DispatchWorkItem?
    private let pingInterval: TimeInterval = 25, pongTimeout: TimeInterval = 10
    private let backoffBase: TimeInterval = 1, backoffCap: TimeInterval = 30
    private let path = NWPathMonitor(); private var online = true

    init(url: URL, deviceSecret: String) { self.url = url; self.deviceSecret = deviceSecret; super.init() }

    func start() { queue.async { guard self.state == .stopped else { return }
        self.installObservers(); self.attempt = 0; self.connect() } }
    func stop() { queue.async { self.state = .stopped; self.teardown(.goingAway, reconnect: false) } }
    func shutdown() { stop(); path.cancel()
        NSWorkspace.shared.notificationCenter.removeObserver(self); session.invalidateAndCancel() }

    private func connect() {
        guard state == .stopped || state == .waiting else { return }
        reconnectWork?.cancel(); reconnectWork = nil; state = .connecting; epoch &+= 1
        var req = URLRequest(url: url); req.timeoutInterval = 15
        req.setValue("Bearer \(deviceSecret)", forHTTPHeaderField: "Authorization")   // auth por header
        let t = session.webSocketTask(with: req); t.maximumMessageSize = 1 << 20
        task = t; t.resume()
    }
    private func teardown(_ code: URLSessionWebSocketTask.CloseCode, reconnect: Bool) {
        epoch &+= 1; pingWork?.cancel(); pongWork?.cancel()
        task?.cancel(with: code, reason: nil); task = nil
        if reconnect { state = .waiting; scheduleReconnect() }
    }
    private func handleDrop(_ reason: String) {
        guard state == .connecting || state == .connected else { return }
        teardown(.abnormalClosure, reconnect: true)
    }
    private func scheduleReconnect() {
        guard state == .waiting, online else { return }
        let ceil = min(backoffCap, backoffBase * pow(2, Double(attempt))); attempt += 1
        let delay = Double.random(in: 0...ceil)                       // full jitter
        let item = DispatchWorkItem { [weak self] in guard let s = self, s.state == .waiting else { return }; s.connect() }
        reconnectWork = item; queue.asyncAfter(deadline: .now() + delay, execute: item)
    }
    private func forceReconnect() {                                   // wake / rede voltou
        guard state != .stopped else { return }; attempt = 0
        teardown(.goingAway, reconnect: false); state = .waiting
        let item = DispatchWorkItem { [weak self] in guard let s = self, s.state == .waiting, s.online else { return }; s.connect() }
        reconnectWork = item; queue.asyncAfter(deadline: .now() + Double.random(in: 0...1.5), execute: item)
    }
    private func receiveNext(_ e: UInt64) {
        guard let task, e == epoch else { return }
        task.receive { [weak self] r in self?.queue.async { guard let s = self, e == s.epoch else { return }
            switch r { case .success(let m): s.handle(m); s.receiveNext(e)
                       case .failure(let err): s.handleDrop("receive \(err)") } } }
    }
    private func schedulePing(_ e: UInt64) {
        let item = DispatchWorkItem { [weak self] in guard let s = self, e == s.epoch, let t = s.task, s.state == .connected else { return }
            s.armPong(e)
            t.sendPing { [weak self] err in self?.queue.async { guard let s = self, e == s.epoch else { return }
                s.pongWork?.cancel(); if let err { s.handleDrop("pong \(err)") } else { s.schedulePing(e) } } } }
        pingWork = item; queue.asyncAfter(deadline: .now() + pingInterval, execute: item)
    }
    private func armPong(_ e: UInt64) {
        let item = DispatchWorkItem { [weak self] in guard let s = self, e == s.epoch, s.state == .connected else { return }
            s.handleDrop("pong timeout") }                            // contorna o delay de 60s–3min
        pongWork = item; queue.asyncAfter(deadline: .now() + pongTimeout, execute: item)
    }
    private func handle(_ m: URLSessionWebSocketTask.Message) {
        let data: Data; switch m { case .string(let s): data = Data(s.utf8); case .data(let d): data = d; @unknown default: return }
        guard let n = try? JSONDecoder().decode(PushNotification.self, from: data), n.type == "notify" else { return }
        DispatchQueue.main.async { self.onNotify?(n) }
    }
    private func installObservers() {
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(didWake),
            name: NSWorkspace.didWakeNotification, object: nil)       // NOTIF CENTER do NSWorkspace, não o default
        path.pathUpdateHandler = { [weak self] p in self?.queue.async { guard let s = self else { return }
            let ok = p.status == .satisfied, was = s.online; s.online = ok
            if ok && !was { s.forceReconnect() }                      // trata TRANSIÇÃO (1º status pode vir espúrio)
            else if !ok, s.state == .connecting || s.state == .connected { s.teardown(.goingAway, reconnect: false); s.state = .waiting } } }
        path.start(queue: queue)
    }
    @objc private func didWake() { queue.async { self.forceReconnect() } }

    func urlSession(_ s: URLSession, webSocketTask t: URLSessionWebSocketTask, didOpenWithProtocol p: String?) {
        queue.async { guard t === self.task else { return }; self.state = .connected; self.attempt = 0
            let e = self.epoch; self.receiveNext(e); self.schedulePing(e) } }
    func urlSession(_ s: URLSession, webSocketTask t: URLSessionWebSocketTask, didCloseWith code: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        queue.async { guard t === self.task else { return }; self.handleDrop("server close \(code.rawValue)") } }
    func urlSession(_ s: URLSession, task t: URLSessionTask, didCompleteWithError e: Error?) {
        queue.async { guard t === self.task else { return }; self.handleDrop("didComplete \(e?.localizedDescription ?? "nil")") } }
}
```

**Recomendação:** ficar no nativo (contornável, zero dependência). **Plano B** se a queda/sleep
continuarem ruins mesmo com os workarounds: migrar a camada de transporte pra
`NWConnection`/`NWProtocolWebSocket` (mesma máquina de estado). **Validar empiricamente**:
desligar o Wi-Fi e medir o tempo até reconectar; confirmar cadência do ping com o app ocioso
(Instruments/logs) por causa do App Nap.

Fontes: developer.apple.com (receive/sendPing/maximumMessageSize/didWakeNotification),
Apple Dev Forums thread/678384 e thread/756482, TN3151, useyourloaf NWPathMonitor.

---

## R4 — Mac: avatar remoto com guardas + Keychain múltiplo

**`AsyncImage` NÃO serve** (não deixa validar Content-Type/tamanho nem impor timeout). Fazer
um loader com `URLSessionDataDelegate`:
- só `https` (validar `url.scheme`);
- `didReceive response`: checar `Content-Type` de imagem e `Content-Length` → `.cancel` se ruim;
- `didReceive data`: acumular e **cancelar se passar 512 KB** (Content-Length é mentiroso);
- validar os bytes como imagem de verdade via **`CGImageSourceCreateWithData` + count > 0**
  (não confiar no header);
- cache em memória **`NSCache<NSString,NSImage>`** por hash da URL; fallback pra SF Symbol (sino);
- `URLSessionConfiguration` com `timeoutIntervalForRequest = 5`, `timeoutIntervalForResource = 10`.
- **Refinar** (nit do agente): reusar **uma** session/loader e deduplicar downloads em voo pela
  mesma URL, em vez de criar session nova a cada `updateNSView`.

**Keychain — múltiplos segredos:** um `kSecAttrAccount` por valor (`deviceId`, `deviceSecret`,
`publishToken`) sob o mesmo `kSecAttrService` (melhor que serializar JSON: atômico, leitura
parcial, flags por item). `kSecAttrAccessible = kSecAttrAccessibleAfterFirstUnlock` (agente
lê no login sem interação, depois do 1º unlock). Estende o padrão do `DeepgramKeyStore` já
existente. Esqueleto:

```swift
enum KeychainStore {
    enum Account: String { case deviceId, deviceSecret, publishToken }
    static let service = "com.zoi.knobler.webhook"
    static func save(_ v: String, _ a: Account) { /* SecItemUpdate → senão SecItemAdd com
        kSecAttrAccessibleAfterFirstUnlock */ }
    static func load(_ a: Account) -> String? { /* SecItemCopyMatching */ }
    static func delete(_ a: Account) { /* SecItemDelete (ok se errSecItemNotFound) */ }
}
```

Fontes: developer.apple.com (URLSessionConfiguration, URLSessionDataDelegate, CGImageSource,
NSCache, kSecAttrAccount, kSecAttrAccessibleAfterFirstUnlock, AsyncImage).

---

## R5 — Prior art (ntfy / Pushover / Pushcut / Gotify)

- **"Token na URL como bearer secret"** é o modelo de ntfy (topics) e Pushcut (secret webhook)
  — validado como aceitável **com HTTPS + rotação**. É exatamente o nosso.
- **Contrato de payload:** o nosso (`title`, `body`, `icon`, `url`, `sound`, `id`) cobre o
  essencial. Campos que eles têm e nós **deixamos fora de propósito (futuro):** `priority`
  (ntfy 1–5, Pushover −2..2) e `tags`/emoji (ntfy). Aceitar **JSON + form-encoded + query**
  é o padrão de conveniência do ntfy (bom pra Zapier/n8n/curl).
- **Dedupe/replace por `id`:** é o padrão de "update" do ntfy (message id/sequence). Nosso
  `id` = diferencial real frente a Pushover/Gotify (que não têm). Manter.
- **Offline:** ntfy usa polling `since=<id>` com cache (~12h). Nós usamos **WS + fila drenada
  no reconnect**, que entrega o mesmo resultado com push ao vivo. **Mantido** — não trocar por
  polling.
- **Rate limit:** ntfy documenta ~60 burst + reposição. Nosso 20/min burst 5 é conservador e
  ok pro volume de "notificações de verdade"; tunável.
- **Segurança do link:** recomendam **≥256 bits** de entropia, rotação com revoke, e **não
  logar o token** (truncar tipo `aBcD…90_-`). Adotado: 256 bits + rotação (morte imediata) +
  não logar segredo.

Fontes: docs.ntfy.sh/publish, pushover.net/api, pushcut.io/webapi, gotify.net/docs.

---

## Contradições resolvidas (resumo)

1. **Auth WS por query vs header** → **header** (`Authorization: Bearer`), pra não vazar no
   access log do nginx.
2. **Rate limit no nginx (por header) vs na app** → **na app**, em memória, por device (token
   está no path; sem Redis).
3. **Entropia 128 vs 256 bits** → **256** (SOTA, custo zero).
4. **Offline: WS+fila vs polling `since=`** → **WS+fila** (decisão mantida; mesmo efeito, melhor UX).
5. **Rate limit 20/min vs 300/min** → **20/min** (nosso volume é baixo; conservador de propósito).
6. **Rotação: morte imediata vs grace 7d** → **imediata** (grace fica como futuro opcional).

## Riscos a validar empiricamente (no plano/execução)

- [ ] `URLSessionWebSocketTask`: medir tempo real de reconnect ao desligar o Wi-Fi (esperado
  ~10s com o pong-timeout; se ruim → plano B `NWConnection`).
- [ ] App Nap: confirmar (Instruments/logs) que o ping mantém cadência de 25s com o app ocioso;
  ajustar `beginActivity` se preciso.
- [ ] `better-sqlite3@11` compila limpo na VPS (build-essential + python3) ou usar prebuilt.
- [ ] certbot: registro DNS A de `push.appzoi.com.br` propaga antes de rodar o challenge.
- [ ] `maximumMessageSize` default é indocumentado → sempre setar explícito (1 MiB).

---

## Refinamentos que atualizam a spec de design

Aplicar em `2026-07-20-webhook-notifications-design.md`:
1. Token de publicação e deviceSecret: **256 bits** (era 128).
2. Auth do WebSocket: **header `Authorization: Bearer <deviceSecret>`**, não query string.
3. Rate limit: **na app Node, token-bucket em memória** por device (+ limite leve por IP no
   nginx). Sem Redis.
4. Dependência: **`better-sqlite3@11`** (pin Node 18).
5. Cliente Mac: **App Nap** via `beginActivity(.userInitiatedAllowingIdleSystemSleep)`; pong-
   timeout de app + `NWPathMonitor` + wake; `maximumMessageSize` explícito; **plano B
   `NWConnection`** documentado como fallback.
6. Não logar o token/segredo (truncar em logs).
