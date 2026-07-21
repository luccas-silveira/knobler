# Mapeamento de webhook — App (Plano B de B) — Implementação

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:subagent-driven-development. Steps usam `- [ ]`.

**Goal:** Lado macOS do mapeamento: a aba "Notificações externas" vira **lista de perfis**; cada perfil abre um **editor lado-a-lado** (campos ↔ árvore do payload, clique-pra-inserir, preview) que salva o template no relay; o card do notch renderiza `iconEmoji`. E deploy do relay+app juntos no fim.

**Architecture:** `WebhookClient` ganha a camada HTTP de perfis (CRUD contra a API do relay já pronta). UI nova: `ProfilesListView` + `MappingEditorView` (com o wrapper AppKit `CursorTextView` da pesquisa). `NotchNotification`+card ganham emoji. Publish token por perfil vive no Keychain (o relay só tem o hash).

**Tech Stack:** Swift 5 · SwiftUI + AppKit (`NSViewRepresentable`/`NSTextView`) · macOS 14.2. Sem deps novas.

**Plano B de B.** O relay (Plano A) está pronto e deploy-ready (não deployado). Este plano fecha o app e **deploya relay+app juntos** (Task B5) — evita a janela de notificações-off (BUG 2 do review).

## Global Constraints

- Deployment **macOS 14.2**. `xcodegen generate` após adicionar `.swift`. **`Knobler.xcodeproj` e `Snapshots/` são gitignored — NÃO commitar.** Gate: `xcodebuild -project Knobler.xcodeproj -scheme Knobler -configuration Debug build` → `** BUILD SUCCEEDED **`. Diagnostics do SourceKit ("Cannot find type X") = falso-positivo por-arquivo; ignore.
- **`TextSelection`/cursor do SwiftUI é macOS 15+** → o editor usa **`NSViewRepresentable` sobre `NSTextView`** (ver pesquisa). Folha da árvore = **`.onTapGesture`** (não `Button` — roubaria o foco).
- Relay: base `https://push.appzoi.com.br`. API de perfis auth por header `Authorization: Bearer <deviceSecret>`: `POST /profiles {name}`→`{profileId,publishToken}`; `GET /profiles`→`[{profileId,name,hasMapping,icon}]`; `GET /profiles/<id>`→`{name,mapping,icon,lastPayload}` (link null); `PUT /profiles/<id> {name?,mapping?,icon?}`; `DELETE /profiles/<id>`; `POST /profiles/<id>/rotate`→`{publishToken}`.
- **O relay não devolve o publishToken no GET** (só o hash) → o app guarda o token por perfil no **Keychain** (account `profile:<id>`) no create/rotate, e monta o link local `…/w/<token>`.
- `mapping` = JSON `{title,body,url,sound,id,iconTemplate}`. Ícone fixo do perfil = campo `icon` (URL ou emoji). Preview local reimplementa `render({{}})` (~20 linhas).
- Card do notch: `NotchNotification.iconEmoji: String?`; render do emoji no slot 32×32 (glifo grande) quando presente, senão `iconURL` (path atual), senão fallback.
- Comentários/strings pt-BR. Marcar simplificações com `// ponytail:`.
- Sem alvo XCTest → validação = build + snapshot (card) + E2E real (B5).

## File Structure

- `Knobler/NotificationInterceptor.swift` — modifica: `NotchNotification.iconEmoji`.
- `Knobler/NotchView.swift` — modifica: `RemoteAvatarView` renderiza emoji.
- `Knobler/WebhookClient.swift` — modifica: `handle` decodifica `iconEmoji`; **novos** métodos de perfis (CRUD+rotate); `rotate()` legado → por perfil.
- `Knobler/WebhookKeychainStore.swift` — modifica: token por perfil (`saveProfileToken/loadProfileToken/deleteProfileToken`).
- `Knobler/ProfilesListView.swift` — **novo**: lista de perfis (substitui o conteúdo da aba).
- `Knobler/MappingEditorView.swift` — **novo**: editor lado-a-lado (CursorTextView, InsertionRouter, JSONTreeView, preview).
- `Knobler/WebhookSettingsView.swift` — modifica: aba mostra `ProfilesListView`.

---

### Task B1: `iconEmoji` no `NotchNotification` + render no card

**Files:** Modify `Knobler/NotificationInterceptor.swift`, `Knobler/NotchView.swift`, `Knobler/WebhookClient.swift`.

- [ ] **Step 1: `NotchNotification.iconEmoji`** — em `NotificationInterceptor.swift`, junto de `iconURL`:
```swift
    /// Emoji fixo do perfil (webhook) — renderiza local, sem baixar nada.
    var iconEmoji: String? = nil
```

- [ ] **Step 2: `WebhookClient.handle` decodifica emoji** — em `WebhookClient.swift`, o struct `PushNotification` ganha `let iconEmoji: String?` e o `NotchNotification(...)` passa `iconEmoji: n.iconEmoji`. (Ordem do init: os campos novos foram declarados depois de `openURL`, então adicione `iconEmoji` na ordem de declaração da struct — confira em `NotificationInterceptor.swift` e case a ordem.)

- [ ] **Step 3: `RemoteAvatarView` renderiza emoji** — em `NotchView.swift`, a `RemoteAvatarView` recebe `iconEmoji` e, quando presente, mostra o glifo antes de tudo:
```swift
    var body: some View {
        Group {
            if let e = iconEmoji, !e.isEmpty {
                Text(e).font(.system(size: 22))
            } else if let img = loader.image {
                Image(nsImage: img).resizable().scaledToFit().clipShape(RoundedRectangle(cornerRadius: 7))
            } else if let path = fallbackPath {
                Image(nsImage: NSWorkspace.shared.icon(forFile: path)).resizable()
            } else {
                Image(systemName: "bell.badge.fill").resizable().scaledToFit().padding(6).foregroundStyle(.white.opacity(0.6))
            }
        }
        .onAppear { reload() }
        .onChange(of: iconURL) { _, _ in reload() }
    }
```
E o `appIcon(for:)` passa `iconEmoji: notification.iconEmoji` pro `RemoteAvatarView`. Se `iconEmoji` presente, não precisa carregar URL (o `reload()` só roda se não houver emoji — adicione o guard no `reload()`: `guard iconEmoji == nil else { return }`).

- [ ] **Step 4: Build + snapshot**
Run: `xcodegen generate && xcodebuild -project Knobler.xcodeproj -scheme Knobler -configuration Debug build 2>&1 | tail -3` → `** BUILD SUCCEEDED **`; `./tools/snapshot.sh 2>&1 | tail -3` (ajuste a lista se cascatear). Leia `Snapshots/notification.png` (fallback, sem emoji em snapshot — sem quebra).

- [ ] **Step 5: Commit** `git add Knobler/NotificationInterceptor.swift Knobler/NotchView.swift Knobler/WebhookClient.swift tools/snapshot.sh && git commit -m "feat(webhook): iconEmoji no card do notch"`

---

### Task B2: `WebhookClient` — API de perfis + token por perfil no Keychain

**Files:** Modify `Knobler/WebhookClient.swift`, `Knobler/WebhookKeychainStore.swift`.

**Interfaces (produz em `WebhookClient`):**
- `struct WebhookProfile: Identifiable { let id: String; var name: String; var hasMapping: Bool; var icon: String? }`
- `struct ProfileDetail { var name: String; var mapping: String?; var icon: String?; var lastPayload: String? }`
- `func listProfiles() async -> [WebhookProfile]`
- `func createProfile(name: String) async -> String?` (retorna profileId; guarda o publishToken no Keychain)
- `func getProfile(_ id: String) async -> ProfileDetail?`
- `func updateProfile(_ id: String, name: String?, mapping: String?, icon: String?) async`
- `func deleteProfile(_ id: String) async`
- `func rotateProfile(_ id: String) async` (guarda o novo token)
- `func link(for id: String) -> String?` (monta `…/w/<token>` do Keychain)

- [ ] **Step 1: Keychain por perfil** — em `WebhookKeychainStore.swift`, adicionar (usa `kSecAttrAccount = "profile:<id>"`):
```swift
    static func saveProfileToken(_ token: String, _ profileId: String) { saveRaw(token, account: "profile:\(profileId)") }
    static func loadProfileToken(_ profileId: String) -> String? { loadRaw(account: "profile:\(profileId)") }
    static func deleteProfileToken(_ profileId: String) { deleteRaw(account: "profile:\(profileId)") }
```
> Se o store atual não tiver helpers genéricos por `account`, extraia `saveRaw(_:account:)`/`loadRaw(account:)`/`deleteRaw(account:)` (a mesma lógica dos métodos por `Account`) e faça os métodos existentes chamarem eles. Sem mudar comportamento.

- [ ] **Step 2: Métodos de perfis** — em `WebhookClient.swift`, um helper de request autenticado + os métodos. Esboço (usa `URLSession` já existente; auth pelo `deviceSecret` do Keychain):
```swift
    private func authed(_ path: String, method: String = "GET", body: Data? = nil) async -> Data? {
        guard let secret = WebhookKeychainStore.load(.deviceSecret) else { return nil }
        var req = URLRequest(url: base.appendingPathComponent(path))
        req.httpMethod = method
        req.setValue("Bearer \(secret)", forHTTPHeaderField: "Authorization")
        if let body { req.httpBody = body; req.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        return try? await session.data(for: req).0
    }
    func listProfiles() async -> [WebhookProfile] {
        guard let d = await authed("profiles"),
              let arr = try? JSONSerialization.jsonObject(with: d) as? [[String: Any]] else { return [] }
        return arr.map { WebhookProfile(id: $0["profileId"] as? String ?? "", name: $0["name"] as? String ?? "",
                                        hasMapping: $0["hasMapping"] as? Bool ?? false, icon: $0["icon"] as? String) }
    }
    func createProfile(name: String) async -> String? {
        guard let d = await authed("profiles", method: "POST", body: try? JSONSerialization.data(withJSONObject: ["name": name])),
              let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
              let id = o["profileId"] as? String, let tok = o["publishToken"] as? String else { return nil }
        WebhookKeychainStore.saveProfileToken(tok, id)
        return id
    }
    func getProfile(_ id: String) async -> ProfileDetail? {
        guard let d = await authed("profiles/\(id)"),
              let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { return nil }
        return ProfileDetail(name: o["name"] as? String ?? "", mapping: o["mapping"] as? String,
                             icon: o["icon"] as? String, lastPayload: o["lastPayload"] as? String)
    }
    func updateProfile(_ id: String, name: String? = nil, mapping: String? = nil, icon: String? = nil) async {
        var b: [String: Any] = [:]; if let name { b["name"] = name }; if let mapping { b["mapping"] = mapping }; if let icon { b["icon"] = icon }
        _ = await authed("profiles/\(id)", method: "PUT", body: try? JSONSerialization.data(withJSONObject: b))
    }
    func deleteProfile(_ id: String) async { _ = await authed("profiles/\(id)", method: "DELETE"); WebhookKeychainStore.deleteProfileToken(id) }
    func rotateProfile(_ id: String) async {
        guard let d = await authed("profiles/\(id)/rotate", method: "POST"),
              let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any], let tok = o["publishToken"] as? String else { return }
        WebhookKeychainStore.saveProfileToken(tok, id)
    }
    func link(for id: String) -> String? {
        guard let tok = WebhookKeychainStore.loadProfileToken(id) else { return nil }
        return base.appendingPathComponent("w").appendingPathComponent(tok).absoluteString
    }
```
> O `rotate()` legado (device-level) pode ser removido do `WebhookClient` — a UI passa a chamar `rotateProfile(id)`. A `link`/`connected` publicadas seguem como estão (a conexão WS é por device, inalterada).

- [ ] **Step 3: Build** → `** BUILD SUCCEEDED **`. (Sem teste automatizado; validado no E2E da B5.)
- [ ] **Step 4: Commit** `git add Knobler/WebhookClient.swift Knobler/WebhookKeychainStore.swift Knobler.xcodeproj && git commit -m "feat(webhook): camada HTTP de perfis no WebhookClient + token por perfil no Keychain"`

---

### Task B3: `ProfilesListView` — a aba vira lista de perfis

**Files:** Create `Knobler/ProfilesListView.swift`; Modify `Knobler/WebhookSettingsView.swift`.

- [ ] **Step 1: `ProfilesListView.swift`** — lista, adicionar, e navegar pro editor:
```swift
import SwiftUI

struct ProfilesListView: View {
    @ObservedObject var client: WebhookClient
    @State private var profiles: [WebhookProfile] = []
    @State private var editing: WebhookProfile?
    @State private var novoNome = ""

    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                TextField("Nome do perfil (ex.: GitHub)", text: $novoNome)
                Button("Adicionar") {
                    let nome = novoNome.trimmingCharacters(in: .whitespaces); guard !nome.isEmpty else { return }
                    novoNome = ""
                    Task { _ = await client.createProfile(name: nome); await recarregar() }
                }
            }
            List(profiles) { p in
                HStack {
                    Text(p.icon ?? "🔔").frame(width: 22)
                    VStack(alignment: .leading) {
                        Text(p.name)
                        Text(p.hasMapping ? "mapeado" : "sem mapa (captura)").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if let l = client.link(for: p.id) {
                        Button("Copiar link") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(l, forType: .string) }
                    }
                    Button("Mapear") { editing = p }
                    Button(role: .destructive) { Task { await client.deleteProfile(p.id); await recarregar() } } label: { Image(systemName: "trash") }
                }
            }
        }
        .padding()
        .task { await recarregar() }
        .sheet(item: $editing) { p in
            MappingEditorView(client: client, profile: p, onClose: { editing = nil; Task { await recarregar() } })
        }
    }
    private func recarregar() async { profiles = await client.listProfiles() }
}
```

- [ ] **Step 2: A aba mostra a lista** — em `WebhookSettingsView.swift`, quando `webhookNotifications` on, mostrar `ProfilesListView(client: client)` (mantendo o master toggle + status de conexão no topo; **remova** o bloco antigo de link-único/rotacionar — agora é por perfil).

- [ ] **Step 3: `xcodegen generate && xcodebuild ... build`** → SUCCEEDED. (A `MappingEditorView` vem na B4 — se compilar antes dela, crie um stub mínimo `struct MappingEditorView: View { ...; var body: some View { Text("") } }` e substitua na B4; OU faça B4 antes do build. Recomendo: implementar B4 e B3 juntas antes do build.)
- [ ] **Step 4: Commit** `git add Knobler/ProfilesListView.swift Knobler/WebhookSettingsView.swift Knobler.xcodeproj && git commit -m "feat(webhook): aba vira lista de perfis"`

---

### Task B4: `MappingEditorView` — editor lado-a-lado (o núcleo)

**Files:** Create `Knobler/MappingEditorView.swift`.

Baseado na pesquisa (`docs/superpowers/specs/2026-07-20-webhook-mapping-research.md`). Peças: `CursorTextView` (wrapper `NSTextView`), `InsertionRouter`, `JSONValue`+`JSONTreeView`, `render` local pro preview.

- [ ] **Step 1: `MappingEditorView.swift`** — copie o código carregador da pesquisa (R1) e monte o editor. Estrutura:
  - `enum TemplateField { case title, body, url, id }` + `InsertionRouter` (ObservableObject).
  - `CursorTextView: NSViewRepresentable` sobre `NSTextView` (o código exato da pesquisa: `makeCoordinator`, `makeNSView` com `scrollableTextView()`, `textDidChange`→binding, `textDidBeginEditing`→`router.active=self`, `insertAtCursor` com `shouldChangeText`+`replaceCharacters`+`didChangeText`, UTF-16 `(s as NSString).length`).
  - `enum JSONValue` (`from(_:)` tratando Bool via `CFBooleanGetTypeID`, objeto ordenado por chave) + `JSONTreeView` recursiva (`DisclosureGroup` **expandido por padrão**, folha com **`.onTapGesture`** → `router.insert("{{\(path)}}")`, mostrando tipo+valor por nó).
  - `render(tpl, JSONValue)` local (regex `\{\{\s*([^}]+?)\s*\}\}`, resolve dot-path+índice, ausente→vazio).
  - `MappingEditorView(client, profile, onClose)`:
    - `@State` dos campos (title/body/url/id), `icon` (fixed), `sound` (toggle), `root: JSONValue?` (do lastPayload), `router`.
    - `.task`: `getProfile(id)` → parseia `mapping` JSON nos campos + `icon` + `JSONValue.from(JSONSerialization(lastPayload))` na árvore.
    - Layout `HSplitView`: esquerda = os `CursorTextView` (title/body/url/id) + `TextField` do ícone + `Toggle` do som + **preview ao vivo** (`Text(render(title,root))` etc.); direita = `JSONTreeView` (ou "mande um webhook de teste pro link" se `root == nil`) + botão "Recarregar teste" (`getProfile` de novo).
    - "Salvar": serializa `{title,body,url,sound,id}` → JSON, `updateProfile(id, mapping: json, icon: icon)`, `onClose()`.
  - ⚠️ Compatível com macOS 14.2: sem `TextSelection`, sem `onChange` single-param (use two-param `{ _, _ in }`).

> ponytail: v1 sem pills, sem autocomplete, sem busca na árvore (a pesquisa confirmou como polish). Ícone é só o campo fixo (URL/emoji); o `iconTemplate` (mapear do payload) fica pra depois — o relay já suporta, a UI adiciona quando pedir.

- [ ] **Step 2: `xcodegen generate && xcodebuild ... build`** → `** BUILD SUCCEEDED **`. (SourceKit vai reclamar de tipos de outros arquivos — ignore; só o xcodebuild vale.)
- [ ] **Step 3: Commit** `git add Knobler/MappingEditorView.swift Knobler.xcodeproj && git commit -m "feat(webhook): editor de mapeamento lado-a-lado (NSTextView + árvore + preview)"`

---

### Task B5: Deploy relay+app juntos + E2E + CHANGELOG

**Files:** Modify `CHANGELOG.md`.

- [ ] **Step 1: Deploy do RELAY (Plano A, adiado até aqui)** — na branch, o relay está pronto @ 09f9d92:
```bash
cd /Users/luccassilveira/Desktop/knobler
rsync -az --delete --exclude node_modules --exclude '*.db' --exclude '*.db-wal' --exclude '*.db-shm' relay/ root@147.79.87.179:/opt/knobler-relay/
ssh root@147.79.87.179 'cd /opt/knobler-relay && node --test 2>&1 | grep -E "# (tests|pass|fail)"; pm2 restart knobler-relay && sleep 1 && curl -s 127.0.0.1:8477/health'
```
Expected: suíte verde no Node 18; `/health` ok. A migração cria o perfil "Padrão" do device atual (captura-only).

- [ ] **Step 2: CHANGELOG** — em `## [Unreleased]` › `### Added`:
```markdown
- **Webhooks configuráveis (mapeamento por perfil)**: cada fonte externa (GitHub,
  Stripe, n8n…) vira um perfil com link próprio; manda um webhook de teste, e um
  editor lado-a-lado mapeia os campos da notificação a partir do payload capturado
  (texto livre + `{{ variáveis }}`). Ícone por perfil (URL ou emoji). (`template.js`,
  `profiles` no relay; `MappingEditorView`, `ProfilesListView` no app.)
```

- [ ] **Step 3: Build + instalar + rodar o app**
```bash
xcodebuild -project Knobler.xcodeproj -scheme Knobler -configuration Debug build 2>&1 | tail -3
APP=$(find ~/Library/Developer/Xcode/DerivedData -name Knobler.app -path '*Debug*' | head -1)
pkill -x Knobler; sleep 1; open "$APP"
```

- [ ] **Step 4: E2E real** (do usuário / dirigível): Ajustes › Notificações externas → "Adicionar perfil" (ex.: GitHub) → o perfil aparece com link. Copiar o link e mandar um payload cru:
```bash
curl -X POST "<link-do-perfil>" -H 'Content-Type: application/json' -d '{"repository":{"name":"knobler"},"commits":[{"message":"fix bug"}]}'
# → 202 captured (ainda sem mapa)
```
Abrir "Mapear": a árvore mostra `repository.name`, `commits.0.message`. Montar `Título = Push em {{repository.name}}`, `Corpo = {{commits.0.message}}`, ícone `🚀`, salvar. Publicar de novo → **card no notch**: "Push em knobler" / "fix bug" / 🚀. Editar no cursor + clicar na árvore insere `{{path}}`.

- [ ] **Step 5: Commit** `git add CHANGELOG.md && git commit -m "docs(webhook): CHANGELOG do mapeamento; deploy relay+app"`

---

## Self-Review

- Cobertura da spec: iconEmoji (B1), API de perfis+Keychain (B2), lista (B3), editor lado-a-lado (B4), deploy junto+E2E (B5). ✅
- BUG 1 (rotate) fechado dos dois lados: relay (fix wave A4) + app (B2 usa `rotateProfile`). ✅
- BUG 2 (deploy-gate): resolvido — deploy do relay só na B5, junto do app com a UI de perfis. ✅
- Ordem: B3 referencia `MappingEditorView` (B4) → implementar **B4 antes do build da B3**, ou stub. Anotado.
- Riscos: (1) init do `NotchNotification` com `iconEmoji` — casar a ordem de declaração (B1). (2) editor AppKit — a pesquisa validou o padrão, mas o comportamento de foco/cursor só se confirma rodando (E2E B5). (3) snapshot pode cascatear (B1) — adicionar arquivos à lista se preciso; xcodebuild é o gate.
