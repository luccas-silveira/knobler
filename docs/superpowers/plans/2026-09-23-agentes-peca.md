# Agentes como peça do marketplace — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A seção Agentes vira peça do marketplace, instalada por padrão para todos e desinstalável com custo zero.

**Architecture:** Nova ficha `.agentes` no `PluginRegistry` com `AgentesEfeitos { nascer }` (padrão de `MonitoresEfeitos`). `AgentesUso` ganha `parar()` e conforma `PluginServico`. Um passo único de migração com chave própria acrescenta `.agentes` a quem já migrou.

**Tech Stack:** Swift 5, AppKit/SwiftUI, harnesses `tools/*check*.swift` via `xcrun swiftc`.

**Spec:** `docs/superpowers/specs/2026-09-23-agentes-peca-design.md` (ler a seção "Decisões do grill").

## Global Constraints

- Deployment target macOS 14.2.
- `Knobler/Plugin.swift` só importa Foundation (compile isolado do `plugincheck`); nada de `AgentesUso` lá.
- Comentários e UI em pt-BR. Simplificação deliberada marcada `// ponytail:`.
- Não editar `Knobler.xcodeproj`; nenhum arquivo novo (não precisa `xcodegen`).
- Não subir `PluginsInstalados.versaoMigracao`.
- Gate: `./tools/check.sh` verde.

## Review Focus

1. Quem já usa o Knobler (migração v1 feita, sem `.agentes`) abre o build novo: Agentes aparece instalada. Coberto na Task 1.
2. Instalação nova, desinstala Agentes, relança: continua desinstalada. Coberto na Task 1.
3. Desinstalar com sessões vivas e reinstalar: nenhum card "Concluiu" de sessão antiga. Coberto pelo `parar()` recriar o watcher (Task 2, verificação manual).
4. Desinstalar durante a leitura de uso de 60 s: o anel não reaparece. Coberto pela guarda `timer != nil` (Task 2).
5. Peça desinstalada: nenhum `claude` lançado e nenhum pedido de Keychain, mesmo com `agentesClaudeUso` ligado. Coberto na Task 2 (verificação manual com `ps`).

---

### Task 1: Ficha, passo único de migração e plugincheck

**Files:**
- Modify: `Knobler/Plugin.swift` (`PluginID` :23, efeitos ~:183-189, `PluginDeps` :194-207, registro após `.conversao` ~:335, `PluginsInstalados` :372-400, `PluginHost` :452-467)
- Modify: `Knobler/PluginsSettingsPane.swift:26-40` (cor), `:~229` (ABRIR)
- Test: `tools/plugincheck.swift`

**Interfaces:**
- Produces: `PluginID.agentes`; `struct AgentesEfeitos { var nascer: () -> PluginServico? }`; `PluginHost.agentesEfeitos`; `PluginsInstalados.acrescentarAgentesSePreciso(_ d:, instalacaoNova: Bool)`; `PluginsInstalados.chaveAgentes = "plugins.agentes.migrado"`.

- [ ] **Step 1: Testes que falham** — em `tools/plugincheck.swift`, junto de `testMigracaoRodaUmaVezSo`, e registrar no `main` do harness como os vizinhos:

```swift
    /// Quem já tinha migrado (v1, sem Agentes) ganha Agentes uma vez.
    static func testAgentesChegaPraQuemJaUsava() {
        let d = defaultsLimpo("plugincheck.agentes.antigo")
        d.set(1, forKey: PluginsInstalados.chaveMigracao)
        d.set(["pomodoro"], forKey: PluginsInstalados.chave)
        _ = PluginHost(defaults: d)
        assert(PluginsInstalados.ler(d) == [.pomodoro, .agentes], "\(PluginsInstalados.ler(d))")
    }

    /// Desinstalou, relançou: não volta. Vale pra instalação nova também.
    static func testAgentesDesinstaladaNaoVolta() {
        for nova in [true, false] {
            let d = defaultsLimpo("plugincheck.agentes.volta.\(nova)")
            if !nova { d.set(1, forKey: PluginsInstalados.chaveMigracao) }
            let host = PluginHost(defaults: d)
            assert(host.estaInstalado(.agentes), "Agentes precisa começar instalada (nova=\(nova))")
            host.desinstalar(.agentes)
            assert(!PluginHost(defaults: d).estaInstalado(.agentes), "Agentes voltou (nova=\(nova))")
        }
    }
```

Atualizar a lista literal (~:338-341) acrescentando `.agentes` no fim e o comentário para "As 11 peças convertidas mais Monitores e Agentes".

- [ ] **Step 2: Rodar e ver falhar** — comando do cabeçalho de `tools/plugincheck.swift`. Esperado: erro de compilação `type 'PluginID' has no member 'agentes'`.

- [ ] **Step 3: Implementar em `Plugin.swift`**

`PluginID`: acrescentar `agentes` ao fim do `case` da linha 23.

Após `MonitoresEfeitos`:

```swift
/// Os efeitos de Agentes. `AgentesUso` é `@MainActor` e arrasta o vendor do
/// codenotch, então fica fora deste arquivo (constraint 1); `nascer` liga o
/// singleton e devolve ele.
struct AgentesEfeitos {
    var nascer: () -> PluginServico? = { nil }
}
```

`PluginDeps`: `var agentes = AgentesEfeitos()`. `PluginHost`: `var agentesEfeitos = AgentesEfeitos()` e `agentes: agentesEfeitos` no `deps()`.

Registro, depois de `.conversao`:

```swift
        Plugin(id: .agentes, nome: "Agentes",
               descricao: "Sessões e limites de Claude Code e Codex.",
               simbolo: "sparkles", secao: "agentes", painel: nil,
               rotas: [], permissao: nil, pronta: true,
               nascer: { $0.agentes.nascer() }),
```

(Conferir a ordem dos argumentos de `Plugin` com a ficha de `.monitores`, :260-264.)

`PluginsInstalados`: comentário de :385 passa a "Todo mundo atravessa com as peças instaladas, menos Monitores". Acrescentar:

```swift
    /// Agentes entrou depois da migração v1: quem já tinha migrado não a
    /// ganharia. Passo único com chave própria — rodou, não roda mais, então
    /// desinstalar depois cola. Em instalação nova a v1 já incluiu Agentes;
    /// o passo só marca a chave.
    static let chaveAgentes = "plugins.agentes.migrado"

    static func acrescentarAgentesSePreciso(_ d: UserDefaults = .standard, instalacaoNova: Bool) {
        guard !d.bool(forKey: chaveAgentes) else { return }
        if !instalacaoNova { gravar(ler(d).union([.agentes]), d) }
        d.set(true, forKey: chaveAgentes)
    }
```

`PluginHost.init`:

```swift
        let nova = defaults.integer(forKey: PluginsInstalados.chaveMigracao) < PluginsInstalados.versaoMigracao
        PluginsInstalados.migrarSePreciso(defaults)
        PluginsInstalados.acrescentarAgentesSePreciso(defaults, instalacaoNova: nova)
        instalados = PluginsInstalados.ler(defaults)
```

- [ ] **Step 4: `PluginsSettingsPane.swift`** — em `corDaPeca` acrescentar `case .agentes: return .purple` (conferir que a cor não repete; se repetir, escolher uma livre). No `switch` do ABRIR, antes do `default`:

```swift
            case .agentes:
                // Sem painel: o ABRIR mostra a própria seção no notch.
                if let vm = KnoblerMain.delegate.viewModelPrincipal() {
                    vm.setExpandedDirect(true)
                    vm.focar(.agentes)
                }
```

- [ ] **Step 5: Rodar o plugincheck** — esperado: passa. Se `testDefaultsVazioViraOsOnze` quebrar, é porque ela agora inclui `.agentes` (esperado pela spec); ela usa `allCases` menos Monitores, então deve seguir verde.

- [ ] **Step 6: Commit** — `feat: Agentes vira peça do marketplace, instalada por padrão`.

### Task 2: Ciclo de vida do `AgentesUso` e fiação no launch

**Files:**
- Modify: `Knobler/AgentesUso.swift` (:46-69 `iniciar`, :109-115 `atualizarUso`, extensão nova no fim)
- Modify: `Knobler/KnoblerApp.swift:1591-1605` (`configureAgentes`)
- Modify: `Knobler/SettingsView.swift:320-325` (toggle)

**Interfaces:**
- Consumes: `AgentesEfeitos`, `PluginHost.agentesEfeitos`, `PluginID.agentes` (Task 1).
- Produces: `AgentesUso.parar()`; `extension AgentesUso: PluginServico`.

- [ ] **Step 1: `parar()` e conformidade** — em `AgentesUso.swift`, depois de `iniciar()`:

```swift
    /// Desinstalar: nenhum monitor, timer, Keychain ou subprocesso novo.
    /// ponytail: renovação do token já em curso termina sozinha (timeout do
    /// refresher); matar exigiria mexer no vendor.
    func parar() {
        timer?.invalidate()
        timer = nil
        bag.removeAll()
        claudeUso(false)
        coordinator.stop()
        porFonte = [:]
        sessoes = []
        uso = [:]
        lidoEm = [:]
        // Watcher novo: reinstalar não anuncia de novo sessão que já tinha terminado.
        watcher = SessionCompletionWatcher()
    }
```

No fim do arquivo:

```swift
extension AgentesUso: PluginServico {}
```

(`parar()` já satisfaz o protocolo. Se o compilador reclamar de isolamento, seguir `LinkPreview.swift:182-184`.)

Atenção: `coordinator.stop()` emite `onSessions(id, [])`, que passa por `receber` e pelo watcher. Por isso `porFonte`/`sessoes`/`watcher` são zerados **depois** do `stop()`.

- [ ] **Step 2: Leitura em curso descartada** — `atualizarUso`:

```swift
    private func atualizarUso() async {
        if let s = try? await codex.fetchSnapshot(), timer != nil { uso["codex"] = s; lidoEm["codex"] = Date() }
        guard let claude, AppSettings.shared.agentesClaudeUso else { return }
        if let s = try? await claude.fetchSnapshot(), self.claude === claude, timer != nil {
            uso["claude"] = s; lidoEm["claude"] = Date()
        }
    }
```

Conferir que o primeiro `Task { await atualizarUso() }` de `iniciar()` roda depois de `timer` atribuído (hoje roda; manter a ordem).

- [ ] **Step 3: Launch** — em `configureAgentes()` trocar `AgentesUso.shared.iniciar()` por:

```swift
        plugins.agentesEfeitos = AgentesEfeitos(nascer: {
            AgentesUso.shared.iniciar()
            return AgentesUso.shared
        })
```

Confirmar que `plugins` está acessível ali e que `configureAgentes()` (:231) roda antes de `plugins.subir()` (:632).

- [ ] **Step 4: Toggle do Claude** — envolver a `Section("Agentes")` de `SettingsView.swift:320` em `if host.estaInstalado(.agentes) { ... }`. Se a struct desse painel não tiver `host`, acrescentar `@ObservedObject private var host = PluginHost.shared` (padrão de :95) para o toggle sumir na hora.

- [ ] **Step 5: Build e checks**

```bash
xcodebuild -project Knobler.xcodeproj -scheme Knobler -configuration Debug build 2>&1 | tail -3
./tools/check.sh
./tools/snapshot.sh   # os cenários de agentes usam injetar(); conferir que a seção segue no PNG
```

Esperado: `BUILD SUCCEEDED`, todos os gates verdes. Se o snapshot perder a seção Agentes, o harness está lendo `pluginsInstalados` do UserDefaults sem `.agentes`: ajustar o reset do harness em `tools/main.swift` para instalar `.agentes`.

- [ ] **Step 6: Verificação manual** — instalar o build, em Ajustes › Plugins desinstalar Agentes com `agentesClaudeUso` ligado; seção some do notch e o toggle some de Ajustes › Notch; `ps ax | grep -c "[c]laude.*usage"` não cresce em 2 minutos. Reinstalar: seção volta, sem card "Concluiu" repetido. ABRIR na vitrine abre o notch na seção.

- [ ] **Step 7: Commit** — `feat: Agentes nasce e morre com a peça`.

### Task 3: Documentação

**Files:**
- Modify: `docs/plugins.md:5,25,35`, `docs/architecture.md:56,78,102`, `CHANGELOG.md` ([Unreleased], linha da seção Agentes), `Knobler/Novidades/0.33.0.html`

- [ ] **Step 1:** "onze peças" vira "doze peças", e Agentes entra na lista de nomes de `docs/plugins.md:25`. Em `docs/architecture.md:102`, a linha de `AgentesUso.shared` diz que nasce pela peça (`PluginHost`) e não no launch.
- [ ] **Step 2:** No CHANGELOG, a linha da seção Agentes diz que ela é uma peça do marketplace, instalada por padrão e desinstalável em Ajustes › Plugins. Na novidade 0.33.0, uma frase com a mesma informação.
- [ ] **Step 3:** `./tools/check.sh` (o `novidadescheck` lê o HTML). Commit `docs: Agentes como peça`.
