# Quick Actions + seção Cor — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Seção "Ações rápidas" com grade de atalhos para qualquer seção (inclusive ocultas) e seção nova "Cor" com conta-gotas e histórico.

**Architecture:** Regras puras (atalhos, visita a seção oculta, histórico de cores) vivem em arquivos sem AppKit, testados por harness `tools/*check.swift`. O `NotchViewModel` ganha a "visita": foco numa seção fora de `secoes`, encerrada ao fechar o card. Duas views novas entram no `switch` de `NotchView.expandedContent`.

**Tech Stack:** Swift 5, SwiftUI + AppKit, macOS 14.2, XcodeGen, harness `swiftc`.

**Spec:** `docs/superpowers/specs/2026-09-23-quick-actions-design.md`

## Global Constraints

- Deployment target macOS 14.2; nenhuma API acima disso.
- Comentários e strings de UI em pt-BR.
- `rawValue` de `NotchSection` é persistido: `acoesRapidas` e `cor` nunca renomeiam.
- Stores singleton (histórico de cores) injetados em todas as janelas, nunca um por monitor.
- Arquivo `.swift` novo usado pela `NotchView` entra em `tools/notchview-fontes.txt`.
- Check novo entra em `tools/check.sh`.
- Arquivo novo em `Knobler/` exige `xcodegen generate`.
- Nunca editar `Knobler.xcodeproj` nem `MARKETING_VERSION`.
- Mudanças em `## [Unreleased]` do `CHANGELOG.md`; feature nova exige `Knobler/Novidades/<versão>.html` + `NovidadesCatalogo.versoes` na hora do release (fora deste plano).

## Review Focus

1. Atalho para seção de plugin desinstalado depois de salvo: some da grade, não abre card vazio.
2. Quick Actions oculto da barra com atalhos salvos: nada quebra; a lista fica guardada.
3. Fechar e reabrir o card em menos de 30 s estando numa visita: reabre no Quick Actions (a memória de foco de 30 s também grava `acoesRapidas`).
4. Conta-gotas cancelado com Esc: nada entra no histórico.
5. Usuário que já tem `notchSectionsOcultas` salvo: `cor` nasce oculta mesmo assim, uma vez só (reexibir não é desfeito no próximo launch).

---

### Task 1: Casos novos e regras puras de atalho/visita

**Files:**
- Modify: `Knobler/NotchSectionOrder.swift` (enum, `titulo`, `simbolo`, `padrao`, funções novas)
- Modify: `Knobler/NotchPresentation.swift:234-262` (`alturaDaSecao`)
- Modify: `Knobler/NotchView.swift:868-891` (placeholder `EmptyView()` para os dois cases, trocado nas Tasks 3 e 5)
- Test: `tools/sectionordercheck.swift`

**Interfaces:**
- Produces:
  - `NotchSection.acoesRapidas` (`titulo` "Ações rápidas", `simbolo` "square.grid.2x2"), `NotchSection.cor` ("Cor", "eyedropper")
  - `NotchSectionOrder.sanearAtalhos(salvos: [String]) -> [NotchSection]`
  - `NotchSectionOrder.atalhosVisiveis(_ atalhos: [NotchSection], desinstaladas: Set<NotchSection>) -> [NotchSection]`
  - `NotchSectionOrder.vizinho(de atual: NotchSection, em secoes: [NotchSection], avancando: Bool) -> NotchSection?`
  - `NotchSectionOrder.focoParaGuardar(_ foco: NotchSection, secoes: [NotchSection]) -> NotchSection`

- [ ] **Step 1: Testes que falham** — acrescentar em `tools/sectionordercheck.swift` e chamar no `main()`:

```swift
static func testAtalhosSaneados() {
    let r = NotchSectionOrder.sanearAtalhos(salvos: ["cor", "xyz", "monitores", "cor", "acoesRapidas"])
    precondition(r == [.cor, .monitores], "atalhos: \(r)")
}

static func testAtalhoDesinstaladoSome() {
    let r = NotchSectionOrder.atalhosVisiveis([.agentes, .cor], desinstaladas: [.agentes])
    precondition(r == [.cor], "visiveis: \(r)")
}

static func testVizinhoNaVisitaVoltaAoQuickActions() {
    let faixa: [NotchSection] = [.musica, .acoesRapidas, .nota]
    precondition(NotchSectionOrder.vizinho(de: .cor, em: faixa, avancando: true) == .acoesRapidas)
    precondition(NotchSectionOrder.vizinho(de: .cor, em: faixa, avancando: false) == .acoesRapidas)
    precondition(NotchSectionOrder.vizinho(de: .musica, em: faixa, avancando: true) == .acoesRapidas)
    precondition(NotchSectionOrder.vizinho(de: .musica, em: faixa, avancando: false) == .nota)
    precondition(NotchSectionOrder.vizinho(de: .musica, em: [.musica], avancando: true) == nil)
}

static func testFocoGuardadoNaVisitaEhQuickActions() {
    let faixa: [NotchSection] = [.musica, .acoesRapidas]
    precondition(NotchSectionOrder.focoParaGuardar(.cor, secoes: faixa) == .acoesRapidas)
    precondition(NotchSectionOrder.focoParaGuardar(.musica, secoes: faixa) == .musica)
}
```

- [ ] **Step 2: Rodar e ver falhar**

Run: `xcrun swiftc -parse-as-library -swift-version 5 Knobler/NotchSectionOrder.swift tools/sectionordercheck.swift -o /tmp/sectionordercheck && /tmp/sectionordercheck`
Expected: erro de compilação, `acoesRapidas`/`sanearAtalhos` inexistentes.

- [ ] **Step 3: Implementar** em `NotchSectionOrder.swift`:

```swift
case musica, atividade, pomodoro, shelf, espelho, mensagens, historico, nota, link,
     anotacao, agenda, lembretesApple, monitores, agentes, acoesRapidas, cor
// titulo:  case .acoesRapidas: return "Ações rápidas"   case .cor: return "Cor"
// simbolo: case .acoesRapidas: return "square.grid.2x2" case .cor: return "eyedropper"
// padrao: acrescentar .acoesRapidas e .cor no fim

/// Atalhos do Quick Actions lidos do UserDefaults: ordem preservada, sem
/// duplicata, sem desconhecido e sem o próprio Quick Actions. Não completa
/// nada — vazio é o estado de fábrica.
static func sanearAtalhos(salvos: [String]) -> [NotchSection] {
    var vistos: [NotchSection] = []
    for raw in salvos {
        guard let s = NotchSection(rawValue: raw), s != .acoesRapidas, !vistos.contains(s) else { continue }
        vistos.append(s)
    }
    return vistos
}

static func atalhosVisiveis(_ atalhos: [NotchSection],
                            desinstaladas: Set<NotchSection>) -> [NotchSection] {
    atalhos.filter { !desinstaladas.contains($0) }
}

/// Swipe. Foco fora da faixa é visita aberta pelo Quick Actions: qualquer
/// direção volta pra ele.
static func vizinho(de atual: NotchSection, em secoes: [NotchSection],
                    avancando: Bool) -> NotchSection? {
    guard let i = secoes.firstIndex(of: atual) else { return .acoesRapidas }
    guard secoes.count > 1 else { return nil }
    return secoes[(i + (avancando ? 1 : -1) + secoes.count) % secoes.count]
}

/// O que gravar como foco da sessão: a visita nunca é lembrada, quem volta é
/// o Quick Actions que a abriu.
static func focoParaGuardar(_ foco: NotchSection, secoes: [NotchSection]) -> NotchSection {
    secoes.contains(foco) ? foco : .acoesRapidas
}
```

Em `NotchPresentation.alturaDaSecao`: `case .acoesRapidas: return 132` (duas linhas de 4 atalhos de 56 pt + espaçamento) e `case .cor: return 110`. Em `NotchView.expandedContent`: `case .acoesRapidas, .cor: EmptyView()`.

- [ ] **Step 4: Rodar check e build**

Run: o comando do Step 2, depois `./tools/check.sh` e `xcodebuild -project Knobler.xcodeproj -scheme Knobler -configuration Debug build CODE_SIGNING_ALLOWED=NO`
Expected: check sem falha; `BUILD SUCCEEDED`. Os asserts de `sectionordercheck.swift:205,213` comparam `padrao` com `allCases` e passam porque `padrao` recebeu os dois.

- [ ] **Step 5: Commit** — `feat(notch): seções acoesRapidas e cor e regras puras de atalho`

---

### Task 2: Persistência dos atalhos, `cor` oculta de fábrica e visita no VM

**Files:**
- Modify: `Knobler/AppSettings.swift:196-212,337-342`
- Modify: `Knobler/NotchViewModel.swift:287-310,322-331,386-432,529-541`

**Interfaces:**
- Consumes: Task 1.
- Produces:
  - `AppSettings.shared.acoesRapidas: [NotchSection]` (chave `"acoesRapidas"`)
  - `NotchViewModel.abrirAtalho(_ s: NotchSection)`
  - `NotchViewModel.emVisita: Bool` (computada: `focus` não nil e fora de `secoes`)
  - `NotchViewModel.onAbrirAjustesDoNotch: (() -> Void)?`

- [ ] **Step 1: AppSettings**

```swift
/// Atalhos do Quick Actions, em ordem. Independente da barra.
@Published var acoesRapidas: [NotchSection] {
    didSet { UserDefaults.standard.set(acoesRapidas.map(\.rawValue), forKey: "acoesRapidas") }
}
```

No `init`, depois de `notchSectionsOcultas`:

```swift
acoesRapidas = NotchSectionOrder.sanearAtalhos(
    salvos: defaults.stringArray(forKey: "acoesRapidas") ?? [])
// a Cor nasce fora da barra (é pra ser usada pelo Quick Actions). Uma vez só:
// se o usuário reexibir, o próximo launch não a esconde de novo.
if !defaults.bool(forKey: "corOcultaDeFabrica") {
    notchSectionsOcultas.insert(.cor)
    defaults.set(true, forKey: "corOcultaDeFabrica")
}
```

- [ ] **Step 2: Conteúdo** — em `estadoDasSecoes`, `.acoesRapidas: true` e `.cor: true` (páginas fixas, como `.anotacao`).

- [ ] **Step 3: Visita** em `NotchViewModel`:

```swift
/// Foco numa seção fora da faixa, aberta por atalho do Quick Actions. Dura
/// até o card fechar.
var emVisita: Bool { focus.map { !secoes.contains($0) } ?? false }

func abrirAtalho(_ s: NotchSection) {
    if secoes.contains(s) { focar(s); return }
    if focus == .nota, typingNote { QuickNote.shared.editing = false }
    focoPendente = nil
    focoTrocadoEm = ProcessInfo.processInfo.systemUptime
    NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
    focus = s
    focusLocked = true
}
```

- `focus.didSet`: gravar `NotchSectionOrder.focoParaGuardar(focus, secoes: secoes).rawValue`.
- `focarVizinho`: `guard let atual = focus, let destino = NotchSectionOrder.vizinho(de: atual, em: secoes, avancando: avancando) else { return }; focar(destino)`.
- Ao fechar (`:539`): `focoAoFechar = focusLocked ? focus.map { (NotchSectionOrder.focoParaGuardar($0, secoes: secoes), ProcessInfo.processInfo.systemUptime) } : nil`.
- `onAbrirAjustesDoNotch` declarado junto de `onMonitoresSettings` (`:108`) e ligado em `KnoblerApp.swift` ao lado de `:1290`: `viewModel.onAbrirAjustesDoNotch = { [weak self] in self?.showSettings(pane: .notch) }`.

A regra "foco travado fora de `secoes`" de `recalcularSecoes` (`:398-401`) fica: o recálculo só roda na abertura, e fechar encerra a visita.

- [ ] **Step 4: Build + checks** — `./tools/check.sh` e build Debug; esperado sem falha.

- [ ] **Step 5: Commit** — `feat(notch): visita a seção oculta pelo Quick Actions`

---

### Task 3: View do Quick Actions + Ajustes

**Files:**
- Create: `Knobler/AcoesRapidasView.swift`
- Modify: `Knobler/NotchView.swift` (case `.acoesRapidas`)
- Modify: `Knobler/SettingsView.swift:354-400` (bloco novo depois de "Ordem das seções do card"; palavras-chave `"ações rápidas", "atalhos"` em `:77`)
- Modify: `tools/notchview-fontes.txt`, `tools/main.swift` (cenários)

**Interfaces:**
- Consumes: `AppSettings.shared.acoesRapidas`, `NotchSectionOrder.atalhosVisiveis`, `NotchSection.desinstaladas()`, `vm.abrirAtalho`, `vm.onAbrirAjustesDoNotch`.

- [ ] **Step 1: View**

```swift
import SwiftUI

/// Grade do Quick Actions: cada célula abre a seção, esteja ela na barra ou não.
struct AcoesRapidasView: View {
    @ObservedObject var vm: NotchViewModel
    @ObservedObject var settings = AppSettings.shared

    var body: some View {
        let atalhos = NotchSectionOrder.atalhosVisiveis(settings.acoesRapidas,
                                                        desinstaladas: NotchSection.desinstaladas())
        if atalhos.isEmpty {
            VStack(spacing: 8) {
                Text("Nenhum atalho ainda").foregroundStyle(.secondary)
                Button("Escolher nos Ajustes") { vm.onAbrirAjustesDoNotch?() }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                ForEach(atalhos, id: \.self) { s in
                    Button { vm.abrirAtalho(s) } label: {
                        VStack(spacing: 4) {
                            Image(systemName: s.simbolo).font(.system(size: 18))
                            Text(s.titulo).font(.caption2).lineLimit(1)
                        }
                        .frame(maxWidth: .infinity, minHeight: 56)
                        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(s.titulo)
                }
            }
        }
    }
}
```

`NotchView.expandedContent`: `case .acoesRapidas: AcoesRapidasView(vm: vm)`.

- [ ] **Step 2: Ajustes** — `Section("Ações rápidas")` com `List` de `NotchSection.allCases.filter { $0 != .acoesRapidas }` na ordem: primeiro os atalhos marcados (na ordem salva), depois os demais. Cada linha tem `Label(s.titulo, systemImage: s.simbolo)` e um `Toggle` `.checkbox` que insere/remove em `settings.acoesRapidas`. O `.onMove` reordena só os marcados. Texto de apoio: "Atalhos que aparecem na seção Ações rápidas. Valem também para seções escondidas do card."

- [ ] **Step 3: Snapshot** — `Knobler/AcoesRapidasView.swift` em `tools/notchview-fontes.txt`. Em `tools/main.swift`: cenário `expanded-acoes-rapidas` (com `AppSettings.shared.acoesRapidas = [.cor, .monitores, .nota]`) e `expanded-acoes-rapidas-vazio` (`[]`), com `vm.secoes = [.acoesRapidas]` e `vm.focus = .acoesRapidas`. Resetar `acoesRapidas = []` no laço de reset junto do `NotificationHistory.shared.prune`.

- [ ] **Step 4: Validar** — `xcodegen generate`, `./tools/snapshot.sh`, ler os dois PNGs novos; build Debug.

- [ ] **Step 5: Commit** — `feat(notch): seção Ações rápidas e escolha de atalhos nos Ajustes`

---

### Task 4: Histórico de cores

**Files:**
- Create: `Knobler/CoresRecentes.swift`
- Create: `tools/corescheck.swift`
- Modify: `Knobler/ColorPicker.swift:24-41`
- Modify: `tools/check.sh` (entrada nova; `colorpickercheck` passa a compilar `CoresRecentes.swift`)

**Interfaces:**
- Produces:
  - `CoresRecentes.registrar(_ hex: String, em lista: [String]) -> [String]` (pura)
  - `CoresRecentes.shared.lista: [String]` (`@Published`, chave `"coresRecentes"`), `CoresRecentes.shared.adicionar(_ hex: String)`

- [ ] **Step 1: Teste que falha** — `tools/corescheck.swift`:

```swift
//  Rodar:
//  xcrun swiftc -parse-as-library -swift-version 5 \
//    Knobler/CoresRecentes.swift tools/corescheck.swift -o /tmp/corescheck && /tmp/corescheck
import Foundation

@main
struct CoresCheck {
    static func main() {
        var l: [String] = []
        for i in 0..<10 { l = CoresRecentes.registrar(String(format: "#%06X", i), em: l) }
        precondition(l.count == 8 && l.first == "#000009", "limite: \(l)")
        l = CoresRecentes.registrar("#000005", em: l)
        precondition(l.first == "#000005" && l.filter { $0 == "#000005" }.count == 1, "dedupe: \(l)")
        print("corescheck ok")
    }
}
```

- [ ] **Step 2: Rodar e ver falhar** — comando do cabeçalho; esperado erro de `CoresRecentes` inexistente.

- [ ] **Step 3: Implementar**

```swift
import Foundation

/// Últimas cores tiradas pelo conta-gotas, HEX, mais recente primeiro.
/// Singleton: uma lista só pra todas as telas.
final class CoresRecentes: ObservableObject {
    static let shared = CoresRecentes()
    static let limite = 8
    @Published private(set) var lista: [String]

    private init() { lista = UserDefaults.standard.stringArray(forKey: "coresRecentes") ?? [] }

    static func registrar(_ hex: String, em lista: [String]) -> [String] {
        Array(([hex] + lista.filter { $0 != hex }).prefix(limite))
    }

    func adicionar(_ hex: String) {
        lista = Self.registrar(hex, em: lista)
        UserDefaults.standard.set(lista, forKey: "coresRecentes")
    }
}
```

Em `ColorPicker.pick`, dentro do `if let color`: `CoresRecentes.shared.adicionar(hex(color))`. Cobre menu, Anotação e a seção Cor; Esc (`color == nil`) não registra.

`tools/check.sh`: `swift_check corescheck Knobler/CoresRecentes.swift tools/corescheck.swift` e `swift_check colorpickercheck Knobler/ColorPicker.swift Knobler/CoresRecentes.swift tools/colorpickercheck.swift` (atualizar o cabeçalho de `colorpickercheck.swift` igual).

- [ ] **Step 4: Rodar** — `./tools/check.sh`; esperado `corescheck ok` e nenhum check falhando.

- [ ] **Step 5: Commit** — `feat(cor): histórico das últimas 8 cores do conta-gotas`

---

### Task 5: Seção Cor

**Files:**
- Create: `Knobler/CorView.swift`
- Modify: `Knobler/NotchView.swift` (case `.cor`), `tools/notchview-fontes.txt` (+ `CorView.swift`, `CoresRecentes.swift`), `tools/main.swift`

**Interfaces:**
- Consumes: `CoresRecentes.shared`, `ColorPicker.pick(format:completion:)`, `AnnotationColor(hex:)` (`Knobler/AnnotationModel.swift:108`).

- [ ] **Step 1: View**

```swift
import SwiftUI
import AppKit

/// Conta-gotas + últimas cores. Tocar numa cor recopia o HEX.
struct CorView: View {
    @ObservedObject var cores = CoresRecentes.shared

    var body: some View {
        HStack(spacing: 12) {
            Button { ColorPicker.pick(format: .hex) { _ in } } label: {
                Image(systemName: "eyedropper").font(.system(size: 22))
                    .frame(width: 56, height: 56)
                    .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Selecionar cor")
            if cores.lista.isEmpty {
                Text("As cores escolhidas aparecem aqui").foregroundStyle(.secondary)
            } else {
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(28), spacing: 8), count: 4), spacing: 8) {
                    ForEach(cores.lista, id: \.self) { hex in
                        Button {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(hex, forType: .string)
                        } label: {
                            RoundedRectangle(cornerRadius: 6).fill(Color(hex: hex))
                                .frame(width: 28, height: 28)
                        }
                        .buttonStyle(.plain)
                        .help("Copiar \(hex)")
                        .accessibilityLabel("Copiar \(hex)")
                    }
                }
            }
            Spacer(minLength: 0)
        }
    }
}
```

`Color(hex: hex)` acima é esboço: reusar `AnnotationColor(hex:)` (`Knobler/AnnotationModel.swift:108`) e a conversão dela pra `Color` que já existe no mesmo arquivo; `AnnotationModel.swift` entra em `tools/notchview-fontes.txt` se ainda não estiver.

`NotchView.expandedContent`: `case .cor: CorView()`.

- [ ] **Step 2: Snapshot** — cenários `expanded-cor-vazio` e `expanded-cor` (histórico com 5 cores gravadas via `CoresRecentes.shared.adicionar`). Acrescentar `func limpar() { lista = [] }` em `CoresRecentes` (só memória, não toca o UserDefaults de quem roda) e chamá-la no reset do laço de `tools/main.swift`. Nos cenários, popular com `CoresRecentes.registrar` atribuído via um `func carregar(_:)` só-memória pelo mesmo motivo — `adicionar` gravaria no UserDefaults real.

- [ ] **Step 3: Validar** — `xcodegen generate`, `./tools/snapshot.sh`, ler PNGs; `./tools/check.sh`; build Debug.

- [ ] **Step 4: Commit** — `feat(cor): seção Cor com conta-gotas e histórico`

---

### Task 6: Docs e verificação ao vivo

**Files:**
- Modify: `docs/architecture.md:141-170` (visita a seção oculta: foco fora da faixa, swipe volta, fechar encerra, foco salvo vira `acoesRapidas`)
- Modify: `CHANGELOG.md` (`## [Unreleased]` → Added: Ações rápidas; seção Cor)

- [ ] **Step 1:** Escrever os dois trechos acima.
- [ ] **Step 2: Ao vivo** — build Release instalado em `/Applications`: marcar Cor e Monitores como atalhos; abrir Cor pelo Quick Actions (nenhum ícone aceso na barra); deslizar volta ao Quick Actions; fechar e reabrir cai no Quick Actions; tirar cor pelo menu e pela Anotação e ver as duas no histórico; tocar numa cor e colar o HEX.
- [ ] **Step 3: Commit** — `docs: Ações rápidas e visita a seção oculta`
