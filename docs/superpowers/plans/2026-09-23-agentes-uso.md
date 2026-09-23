# Agentes (uso + sessões de Claude/Codex) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Nova seção "Agentes" no notch com anéis de limite de Claude/Codex e a lista de sessões com estado, usando o backend do codenotch vendorizado.

**Architecture:** Backend do codenotch copiado quase literal em `Vendor/Codenotch/` + um shim com os ~10 tipos externos que ele pede. Um singleton `AgentesUso` (ObservableObject) é dono do `ActivityCoordinator`, de um poll de 60 s nos dois `UsageProvider` e do `SessionCompletionWatcher`; é injetado em toda `NotchView`. A UI é nossa: nova `NotchSection.agentes`.

**Tech Stack:** Swift 5, SwiftUI/AppKit, Combine, SQLite3 (sistema), Security.framework. Sem SwiftNIO, Sparkle, zstd.

**Spec:** `docs/superpowers/specs/2026-09-23-agentes-uso-design.md` (ver `## Decisões do grill`). Dossiê: `docs/superpowers/research/2026-09-23-agentes-uso-research.md`.

Referência upstream: `git clone --depth 1 https://github.com/vinzdg/codenotch /tmp/codenotch` — caminhos `Sources/...` abaixo são dele.

## Global Constraints

- Deployment target macOS 14.2; Swift 5.0 (igual nos dois projetos; nenhum símbolo 15+ no conjunto — A8).
- Projeto gerado por XcodeGen: mudanças em `project.yml`, depois `xcodegen generate`. Nunca editar `.xcodeproj`.
- Arquivos vendorizados preservam o texto upstream; cada alteração nossa marcada `// knobler:`. `Vendor/Codenotch/LICENSE` com o MIT do codenotch.
- Fidelidade ao original (decisão do usuário): `ClaudeTokenRefresher`, `ClaudeUsageCLI`, `CodexLocalProvider` (rede) e som de sessão entram como upstream.
- Única divergência: leitura silenciosa do Keychain por query (A3), nunca `SecKeychainSetUserInteractionAllowed(false)`.
- Anel do Claude atrás de `AppSettings.agentesClaudeUso`, **padrão false**, com aviso (termos de uso + prompts do Keychain) nos Ajustes. Com ele desligado, nenhum código do provider do Claude roda (nem Keychain, nem subprocesso).
- UI e comentários em pt-BR. Simplificação deliberada marcada `// ponytail:`.
- Todo `.swift` que a `NotchView` arraste entra em `tools/notchview-fontes.txt`. Check novo entra em `tools/check.sh`.
- `NotchNotification` construída **acima** do laço por tela.

## Review Focus

1. Claude Code não instalado / `~/.claude/sessions` inexistente: seção mostra "nenhuma sessão", sem crash nem timer frenético (teste no Task 2).
2. Arquivo `sessions/<pid>.json` de processo morto: sessão some (ProcessLiveness) (teste no Task 2).
3. `wham/usage` com `plan_type` desconhecido ou campo nulo: anel mostra "—", não derruba o poll (teste no Task 2).
4. Interruptor do Claude desligado com o app rodando: provider para, anel some, nenhum prompt de Keychain depois (teste no Task 3).
5. Dois monitores: uma sessão entrando em `waiting` gera **um** aviso e **um** som, não um por tela (teste no Task 3).

---

### Task 1: Vendorizar o backend e compilar no app

**Files:**
- Create: `Vendor/Codenotch/LICENSE`, `Vendor/Codenotch/Sessions/*.swift`, `Vendor/Codenotch/Providers/*.swift`, `Vendor/Codenotch/Model/{UsageModel,UsageArchive}.swift`, `Vendor/Codenotch/CodenotchShim.swift`
- Modify: `project.yml` (sources + `libsqlite3.tbd`)

**Interfaces:**
- Produces (upstream, sem renomear): `AgentSession`, `AgentActivityMonitor`, `ActivityCoordinator(monitors:)`, `.setEnabled(Set<String>)`, `ClaudeSessionMonitor`, `CodexActivityMonitor`, `SessionCompletionWatcher.absorb(_:) -> [Event]`, `SessionFocus`, `UsageProvider.fetchSnapshot() async throws -> ProviderSnapshot`, `ClaudeOAuthProvider`, `CodexLocalProvider`, `ProviderSnapshot`, `LimitWindow` (`usedFraction: Double?`, reset date).

- [ ] **Step 1: Copiar os arquivos**

```bash
U=/tmp/codenotch/Sources; V=Vendor/Codenotch
mkdir -p $V/Sessions $V/Providers $V/Model $V/App
cp /tmp/codenotch/LICENSE $V/LICENSE
for f in AgentSession AgentActivityMonitor ActivityCoordinator ClaudeSessionMonitor ClaudeSessionRecord ClaudeTranscript ClaudeSessionOwnership ClaudeDesktopSessionIndex ProcessLiveness CodexActivityMonitor SessionCompletionWatcher SessionFocus TerminalTabFocus; do cp $U/Sessions/$f.swift $V/Sessions/; done
for f in UsageProvider ClaudeOAuthProvider ClaudeCredentials ClaudeProfile ClaudeTokenRefresher ClaudeCLI ClaudeUsageCLI CodexLocalProvider CodexCredentials CodexProfile CodexUsage CredentialCache KeychainItem KeychainPrompt SQLiteStore ProviderAccount; do cp $U/Providers/$f.swift $V/Providers/; done
cp $U/Model/UsageModel.swift $U/Model/UsageArchive.swift $V/Model/
cp $U/App/SessionChime.swift $U/App/Log.swift $U/App/Runtime.swift $V/App/
```

(Se `SessionChime` referenciar arquivo de áudio, copiar o recurso para `Knobler/Resources/` e ajustar `// knobler:` o nome.)

- [ ] **Step 2: Adicionar ao `project.yml`**

Em `targets.Knobler.sources`, abaixo de `- path: Vendor/MonitorControl`:

```yaml
      - path: Vendor/Codenotch
        excludes: ["LICENSE"]
```

Em `dependencies`: `- sdk: libsqlite3.tbd`. Rodar `xcodegen generate`.

- [ ] **Step 3: Compilar e escrever o shim guiado pelo erro**

Run: `xcodebuild -project Knobler.xcodeproj -scheme Knobler -configuration Debug build CODE_SIGNING_ALLOWED=NO 2>&1 | grep error: | sort -u`

Esperado: erros de `L10n`, `Preferences`, `ProviderGlyph`, `ClaudeDesktopUsageCache`, `ResetCopy`, `UsageBand`, `UsageStore`. Criar `Vendor/Codenotch/CodenotchShim.swift` só com o que o compilador pedir, ponto de partida:

```swift
// knobler: substitutos mínimos dos tipos do codenotch que não vieram (UI/prefs).
import Foundation

enum L10n {
    static func t(_ s: String) -> String { s }
}

enum Preferences {
    // knobler: o Knobler não expõe os limites extras do Codex.
    static func storedShowCodexExtraLimits() -> Bool { false }
}

enum ProviderGlyph: String, Codable { case claude, openai }
```

`ClaudeDesktopUsageCache`: no `ClaudeOAuthProvider`, a injeção é opcional — trocar o default por `nil` com `// knobler: sem zstd; cache do app desktop do Claude fora`. `ResetCopy`/`UsageBand`/`UsageStore`: stub mínimo no shim ou apagar o trecho de UI que os usa em `UsageModel.swift`/`ProviderAccount.swift` com `// knobler:`. Repetir até o build passar.

- [ ] **Step 4: Divergência A3 no `KeychainPrompt.swift`**

Localizar o bloco em `Providers/KeychainPrompt.swift:116-125` que chama `SecKeychainSetUserInteractionAllowed(false)`. Remover a chamada global e, na query do item, acrescentar:

```swift
// knobler: silêncio só nesta query; o global derrubava a leitura dos segredos do webhook.
let context = LAContext()
context.interactionNotAllowed = true
query[kSecUseAuthenticationContext as String] = context
```

(`import LocalAuthentication`; se a query usa o keychain legado de arquivo, onde `LAContext` não vale, usar `query[kSecUseAuthenticationUI as String] = kSecUseAuthenticationUIFail` — conferir no MCP `xcode` DocumentationSearch.) Manter o fallback `/usr/bin/security` como upstream.

- [ ] **Step 5: Build verde**

Run: `xcodebuild -project Knobler.xcodeproj -scheme Knobler -configuration Debug build CODE_SIGNING_ALLOWED=NO`
Expected: `** BUILD SUCCEEDED **`, e `grep -rn SecKeychainSetUserInteractionAllowed Vendor/Codenotch` vazio.

- [ ] **Step 6: Commit**

```bash
git add Vendor/Codenotch project.yml
git commit -m "chore: vendoriza backend de sessões e uso do codenotch (MIT)"
```

---

### Task 2: Self-check do backend vendorizado

**Files:**
- Create: `tools/agentescheck.swift`, `tools/fixtures/agentes/` (JSONs)
- Modify: `tools/check.sh`

**Interfaces:**
- Consumes: `ClaudeSessionRecord` (parse de `sessions/<pid>.json`), `ProcessLiveness`, `CodexUsage` (parse da resposta `wham/usage`), `SessionCompletionWatcher`.

- [ ] **Step 1: Fixtures**

`tools/fixtures/agentes/claude-busy.json`:
```json
{"pid":999999,"sessionId":"s1","cwd":"/tmp/proj","startedAt":1790000000000,"version":"2.1.280","kind":"interactive","entrypoint":"cli","name":"proj","status":"busy","updatedAt":1790000001000,"statusUpdatedAt":1790000001000}
```
Mais `claude-waiting.json` (`"status":"waiting","waitingFor":"permission"`), `claude-idle.json`, `claude-empty.json` (`"status":""`), `codex-usage.json` (resposta real: `{"plan_type":"prolite","rate_limit":{"primary_window":{"used_percent":42,"reset_at":1790003600},"secondary_window":null}}` — ajustar as chaves ao que `CodexUsage.swift` decodifica).

- [ ] **Step 2: Escrever o check (falha antes de existir entrada no check.sh)**

```swift
// Compila com:
// xcrun swiftc -parse-as-library -swift-version 5 Vendor/Codenotch/Sessions/{AgentSession,ClaudeSessionRecord,ProcessLiveness,SessionCompletionWatcher}.swift Vendor/Codenotch/Providers/CodexUsage.swift Vendor/Codenotch/Model/UsageModel.swift Vendor/Codenotch/CodenotchShim.swift Vendor/Codenotch/App/Log.swift tools/agentescheck.swift -o /tmp/agentescheck && /tmp/agentescheck
import Foundation

@main
enum AgentesCheck {
    static func fixture(_ n: String) -> Data {
        try! Data(contentsOf: URL(fileURLWithPath: "tools/fixtures/agentes/\(n)"))
    }

    static func main() {
        // Estados do registro do Claude Code.
        assert(ClaudeSessionRecord.decode(fixture("claude-busy.json"))?.state == .busy)
        assert(ClaudeSessionRecord.decode(fixture("claude-waiting.json"))?.state == .waiting)
        assert(ClaudeSessionRecord.decode(fixture("claude-idle.json"))?.state == .idle)
        assert(ClaudeSessionRecord.decode(Data("lixo".utf8)) == nil)

        // Pid morto (Review Focus 2).
        assert(!ProcessLiveness.isAlive(pid: 999_999))
        assert(ProcessLiveness.isAlive(pid: getpid()))

        // Codex com plan_type desconhecido e janela nula (Review Focus 3).
        let snap = try? CodexUsage.parse(fixture("codex-usage.json"))
        assert(snap != nil)
        assert(snap!.windows.first?.usedFraction == 0.42)

        // busy -> waiting dispara um evento; repetir o mesmo estado não dispara.
        var w = SessionCompletionWatcher()
        let s = { (st: AgentSession.State) in AgentSession(id: "a", name: "p", detail: "", state: st, waitingFor: nil, since: Date()) }
        _ = w.absorb(["claude": [s(.busy)]])
        assert(w.absorb(["claude": [s(.waiting)]]).count == 1)
        assert(w.absorb(["claude": [s(.waiting)]]).isEmpty)
        print("agentescheck OK")
    }
}
```

Os nomes `decode`, `isAlive`, `parse` devem ser trocados pelos que o upstream expõe (conferir com `grep -n "static func" Vendor/Codenotch/...`); se só houver API de instância, adaptar a chamada — não alterar o vendorizado.

- [ ] **Step 3: Rodar**

Run: a linha do cabeçalho. Expected: `agentescheck OK`. Se um arquivo arrastar mais dependência, acrescentar à linha (não stubar no check).

- [ ] **Step 4: Registrar em `tools/check.sh`** (junto do `agentrequestcheck`, linha 67)

```bash
swift_check agentescheck     Vendor/Codenotch/Sessions/AgentSession.swift Vendor/Codenotch/Sessions/ClaudeSessionRecord.swift Vendor/Codenotch/Sessions/ProcessLiveness.swift Vendor/Codenotch/Sessions/SessionCompletionWatcher.swift Vendor/Codenotch/Providers/CodexUsage.swift Vendor/Codenotch/Model/UsageModel.swift Vendor/Codenotch/CodenotchShim.swift Vendor/Codenotch/App/Log.swift tools/agentescheck.swift
```

(Se o check lê fixtures por caminho relativo, confirmar que `check.sh` roda da raiz.) Run: `./tools/check.sh`. Expected: tudo verde.

- [ ] **Step 5: Commit**

```bash
git add tools/agentescheck.swift tools/fixtures/agentes tools/check.sh
git commit -m "test: agentescheck cobre parse de sessão, liveness e uso do Codex"
```

---

### Task 3: `AgentesUso` — store singleton, preferência e aviso

**Files:**
- Create: `Knobler/AgentesUso.swift`
- Modify: `Knobler/AppSettings.swift` (nova pref), `Knobler/KnoblerApp.swift` (~:891 criar; laço ~:1169 injetar), `tools/agentescheck.swift`

**Interfaces:**
- Consumes: Task 1.
- Produces:
```swift
@MainActor final class AgentesUso: ObservableObject {
    static let shared: AgentesUso
    @Published private(set) var sessoes: [AgentSession]      // todas, ordenadas: waiting, busy, success, idle
    @Published private(set) var uso: [String: ProviderSnapshot] // "claude", "codex"
    var onEvento: ((AgentSession, SessionCompletionWatcher.Reason) -> Void)?
    func iniciar()
    func focar(_ s: AgentSession)
}
// AppSettings: @Published var agentesClaudeUso: Bool  (UserDefaults "agentesClaudeUso", padrão false)
```

- [ ] **Step 1: Pref**

Em `AppSettings.swift`, seguindo o padrão das vizinhas (`notchNotifications` :19):

```swift
    /// Anel de limite do Claude. Desligado por padrão: lê o login do Claude Code
    /// (termos de uso de 2026-02) e o macOS pede senha do Keychain algumas vezes por dia.
    @Published var agentesClaudeUso: Bool {
        didSet { defaults.set(agentesClaudeUso, forKey: "agentesClaudeUso") }
    }
```
e no `init`: `agentesClaudeUso = defaults.bool(forKey: "agentesClaudeUso")`. (Usar o nome real do `UserDefaults` do arquivo.)

- [ ] **Step 2: Store**

```swift
import AppKit
import Combine

/// Sessões e limites de Claude/Codex, vindos do backend do codenotch
/// (`Vendor/Codenotch`). Um só pra todas as telas.
@MainActor
final class AgentesUso: ObservableObject {
    static let shared = AgentesUso()

    @Published private(set) var sessoes: [AgentSession] = []
    @Published private(set) var uso: [String: ProviderSnapshot] = [:]
    /// Disparado uma vez por transição, independente de quantas telas existem.
    var onEvento: ((AgentSession, SessionCompletionWatcher.Reason) -> Void)?

    private let coordinator = ActivityCoordinator(monitors: [
        "claude": ClaudeSessionMonitor(),
        "codex": CodexActivityMonitor(),
    ])
    private let codex = CodexLocalProvider()
    private lazy var claude = ClaudeOAuthProvider()
    private var watcher = SessionCompletionWatcher()
    private var bag = Set<AnyCancellable>()
    private var timer: Timer?

    func iniciar() {
        coordinator.setEnabled(["claude", "codex"])
        coordinator.sessionsPublisher   // nome real do publisher agregado no ActivityCoordinator
            .receive(on: RunLoop.main)
            .sink { [weak self] porFonte in self?.absorver(porFonte) }
            .store(in: &bag)
        AppSettings.shared.$agentesClaudeUso
            .removeDuplicates()
            .sink { [weak self] ligado in
                if !ligado { self?.uso["claude"] = nil }
                Task { await self?.atualizarUso() }
            }
            .store(in: &bag)
        // ponytail: poll fixo de 60 s como o UsageStore do codenotch; sem backoff próprio além do do provider.
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { await self?.atualizarUso() }
        }
    }

    private func absorver(_ porFonte: [String: [AgentSession]]) {
        for evento in watcher.absorb(porFonte) { onEvento?(evento.session, evento.reason) }
        let ordem: [AgentSession.State] = [.waiting, .busy, .success, .idle]
        sessoes = porFonte.values.joined().sorted {
            (ordem.firstIndex(of: $0.state)!, $1.since) < (ordem.firstIndex(of: $1.state)!, $0.since)
        }
    }

    private func atualizarUso() async {
        if let s = try? await codex.fetchSnapshot() { uso["codex"] = s }
        guard AppSettings.shared.agentesClaudeUso else { return }
        if let s = try? await claude.fetchSnapshot() { uso["claude"] = s }
    }

    func focar(_ s: AgentSession) { SessionFocus.focus(s) }  // API real do SessionFocus
}
```

`ClaudeOAuthProvider` é `lazy` para não tocar Keychain enquanto a pref estiver desligada (Review Focus 4).

- [ ] **Step 3: Compor no `AppDelegate`**

Em `KnoblerApp.swift`, junto da criação do `AgentRequestStore` (~:891): `AgentesUso.shared.iniciar()` e

```swift
AgentesUso.shared.onEvento = { [weak self] sessao, motivo in
    // Construída acima do laço por tela: um id só, um card só no histórico.
    let n = NotchNotification(title: sessao.name,
                              body: motivo == .waiting ? (sessao.waitingFor ?? "Esperando você") : "Concluído",
                              /* demais campos com o init real */)
    self?.notches.values.forEach { $0.viewModel.enqueue(n) }
    SessionChime.play(motivo)   // API real do SessionChime; toca uma vez
}
```

No laço por tela (~:1169-1194) passar `agentes: AgentesUso.shared` pra `NotchView`.

- [ ] **Step 4: Teste do "um evento só"** (Review Focus 5) em `tools/agentescheck.swift`

O watcher já garante um evento por transição (Step 2 do Task 2); aqui o risco é o `enqueue` por tela. Verificar à mão com dois monitores no Task 5, e no código garantir por leitura que o `NotchNotification(` está fora do `forEach`.

- [ ] **Step 5: Build + commit**

Run: `xcodebuild ... build CODE_SIGNING_ALLOWED=NO` → `BUILD SUCCEEDED`.

```bash
git add Knobler/AgentesUso.swift Knobler/AppSettings.swift Knobler/KnoblerApp.swift
git commit -m "feat: store de sessões e limites de Claude/Codex"
```

---

### Task 4: Seção "Agentes" na UI + Ajustes

**Files:**
- Create: `Knobler/AgentesView.swift`
- Modify: `Knobler/NotchSectionOrder.swift` (caso `agentes`, título "Agentes", ícone, altura, `padrao`), `Knobler/NotchPresentation.swift:261` (`NotchSectionInputs.agentes`), `Knobler/NotchView.swift` (propriedade `agentes`, ramo de conteúdo), `Knobler/NotchViewModel.swift` (alimentar input), tela de Ajustes (toggle + aviso), `tools/notchview-fontes.txt`, `tools/sectionordercheck.swift`, `tools/main.swift` (cenário)

**Interfaces:**
- Consumes: `AgentesUso.sessoes`, `.uso`, `.focar(_:)`; `ActivityRingView(progress:color:lineWidth:)` (`Knobler/NotchView.swift:1624`).

- [ ] **Step 1: Teste de ordem falhando**

Em `tools/sectionordercheck.swift`, acrescentar:
```swift
assert(NotchSectionOrder.padrao.contains(.agentes))
assert(NotchSection.agentes.titulo == "Agentes")
```
Run a linha do cabeçalho do check. Expected: erro de compilação (`agentes` não existe).

- [ ] **Step 2: Seção**

`NotchSection`: acrescentar `agentes` ao fim do `case` (rawValue novo, não quebra ordem salva); `titulo` → `"Agentes"`; ícone `"sparkles"` (conferir o switch de ícone vizinho); altura como as vizinhas (~192); `padrao` com `.agentes` depois de `.atividade`. `NotchSectionInputs`: `var agentes = false` (true quando há sessão ou uso). Rodar o check: PASS.

- [ ] **Step 3: View**

```swift
import SwiftUI

/// Anéis de limite (Claude/Codex) e sessões dos agentes.
struct AgentesView: View {
    @ObservedObject var agentes: AgentesUso

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 16) {
                ForEach(["claude", "codex"], id: \.self) { id in
                    if let s = agentes.uso[id] { anel(id == "claude" ? "Claude" : "Codex", s) }
                }
            }
            if agentes.sessoes.isEmpty {
                Text("Nenhuma sessão").font(.caption).foregroundStyle(.secondary)
            }
            ForEach(agentes.sessoes.prefix(4)) { s in
                Button { agentes.focar(s) } label: {
                    HStack(spacing: 8) {
                        Circle().fill(cor(s.state)).frame(width: 7, height: 7)
                        Text(s.name).font(.caption.weight(.medium)).lineLimit(1)
                        Spacer()
                        Text(rotulo(s)).font(.caption2).foregroundStyle(.secondary)
                    }
                }.buttonStyle(.plain)
            }
        }
    }

    private func anel(_ nome: String, _ s: ProviderSnapshot) -> some View {
        // headline do provider; nil = sem dado, anel vira spinner
        let w = s.windows.first { $0.id == s.headlineID } ?? s.windows.first
        return HStack(spacing: 6) {
            ActivityRingView(progress: w?.usedFraction.map { min($0, 1) }, color: .white, lineWidth: 3)
                .frame(width: 22, height: 22)
            VStack(alignment: .leading, spacing: 0) {
                Text(nome).font(.caption.weight(.medium))
                Text(w?.usedFraction.map { "\(Int($0 * 100))%" } ?? "—").font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    private func cor(_ e: AgentSession.State) -> Color {
        switch e { case .waiting: .orange; case .busy: .blue; case .success: .green; case .idle: .gray }
    }

    private func rotulo(_ s: AgentSession) -> String {
        switch s.state {
        case .waiting: s.waitingFor ?? "Esperando você"
        case .busy: "Trabalhando"
        case .success: "Concluído"
        case .idle: "Ocioso"
        }
    }
}
```
(Mostrar hora do reset abaixo do %, se `LimitWindow` tiver a data — usar o campo real e `Text(date, style: .relative)`.)

- [ ] **Step 4: Ligar na `NotchView`**

Propriedade `@ObservedObject var agentes: AgentesUso` ao lado de `agentRequestStore` (:10-11); ramo `case .agentes: AgentesView(agentes: agentes)` no switch de seções; `NotchViewModel.updateSections` recebe `agentes: !AgentesUso.shared.sessoes.isEmpty || !AgentesUso.shared.uso.isEmpty`. Se o card expandido mudar de altura, ramo próprio em `currentSize` (ver memória: centraliza o excedente sem isso).

- [ ] **Step 5: Ajustes**

Na tela de Ajustes onde vivem as seções, grupo "Agentes":
```swift
Toggle("Mostrar limite do Claude", isOn: $settings.agentesClaudeUso)
Text("Lê o login do Claude Code num endereço interno da Anthropic. Os termos de uso de fevereiro de 2026 não permitem isso ao pé da letra, e o macOS pode pedir a senha do Keychain algumas vezes por dia.")
    .font(.caption).foregroundStyle(.secondary)
```

- [ ] **Step 6: Snapshot**

`tools/notchview-fontes.txt`: acrescentar `Knobler/AgentesView.swift`, `Knobler/AgentesUso.swift` e os arquivos de `Vendor/Codenotch` que eles arrastam. `tools/main.swift`: cenário `expanded-agentes` com um `AgentesUso` preenchido (adicionar `#if DEBUG func injetar(sessoes:uso:)` no store) e reset no laço junto de `NotificationHistory.shared.prune`. Run `./tools/snapshot.sh` e ler `Snapshots/expanded-agentes.png`.

- [ ] **Step 7: Check + commit**

Run: `./tools/check.sh` → verde.
```bash
git add Knobler tools
git commit -m "feat: seção Agentes com limites e sessões de Claude/Codex"
```

---

### Task 5: Docs, novidade e verificação ao vivo

**Files:**
- Modify: `CHANGELOG.md` (`## [Unreleased]` — **resolver antes o conflito `UU` pendente**), `README.md` (crédito ao codenotch, MIT), `docs/architecture.md` (AgentesUso)
- Create: `Knobler/Novidades/<próxima minor>.html`; acrescentar a versão a `NovidadesCatalogo.versoes`

- [ ] **Step 1:** CHANGELOG em `### Adicionado`: "Seção Agentes: sessões do Claude Code e do Codex com estado (trabalhando, esperando você, concluída) e anéis de limite do plano; o do Claude é opcional nos Ajustes."
- [ ] **Step 2:** Novidade HTML no formato das vizinhas em `Knobler/Novidades/`.
- [ ] **Step 3: Ao vivo** — instalar em `/Applications` (assinatura `Knobler Local Signing`), abrir `claude` num terminal e `codex` noutro: estado muda busy → waiting → done no notch; clique leva à aba certa (aceitar Automação uma vez); som toca **uma** vez com dois monitores; % do Codex bate com `/status` do codex; ligar o interruptor do Claude, aceitar Keychain, % bate com `/usage`; desligar e confirmar que nenhum prompt volta.
- [ ] **Step 4: Commit**

```bash
git add CHANGELOG.md README.md docs Knobler/Novidades Knobler/NovidadesCatalogo.swift
git commit -m "docs: seção Agentes no CHANGELOG, novidade e crédito ao codenotch"
```
