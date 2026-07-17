# Perguntas do Claude Code no notch (v0.9) — Plano de Implementação

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `AskUserQuestion` do Claude Code vira card interativo no notch — botões, multi-select, previews ASCII, texto livre por teclado/ditado — e a resposta volta ao Claude via hook PreToolUse, sem tocar no terminal.

**Architecture:** Hook PreToolUse global intercepta `AskUserQuestion`, faz `POST /ask` no `NotchAPIServer` (4477) e faz polling em `GET /ask/<id>`. O servidor guarda o estado (`pending → answered/cancelled`, TTL 15 min) e emite `onAsk` pro AppDelegate, que faz fan-out do `AskRequest` a todos os monitores. Novo `Mode.question` (prioridade máxima) renderiza `AskCardView`; a resposta volta por callback → `resolveAsk` no servidor → o hook lê e devolve ao Claude com `permissionDecision: deny` + reason. ✕/timeout cancelam e a pergunta cai no terminal.

**Tech Stack:** Swift/AppKit/SwiftUI, Network.framework (servidor existente), bash+curl+jq (hook), xcodegen.

**Spec:** `docs/superpowers/specs/2026-07-17-perguntas-notch-design.md`

## Global Constraints

- Deployment target macOS 14.2 (project.yml); app roda no Tahoe (26).
- Bundle: `com.zoi.knobler`; hardened runtime OFF; assinatura manual Apple Development.
- O repo NÃO tem test target. Validação segue a convenção do projeto: build Release + harness de snapshots (`tools/snapshot.sh`) + E2E manual + `GET /status`.
- Arquivo Swift NOVO exige `xcodegen generate` antes do `xcodebuild` — senão o build falha com símbolos ausentes (gotcha do v0.8).
- Build: `xcodebuild -project Knobler.xcodeproj -scheme Knobler -configuration Release build` (esperar `** BUILD SUCCEEDED **`).
- Comentários e strings de UI em pt-BR, no tom dos arquivos existentes (comentários dizem o porquê, prefixo `ponytail:` para simplificações deliberadas).
- Commits pequenos por task, mensagem em pt-BR.
- A janela do notch NUNCA pode virar key fora do card de pergunta — regressão aqui rouba o teclado do usuário o tempo todo.

---

### Task 1: Modelo Ask + estado no NotchViewModel

**Files:**
- Create: `Knobler/Ask.swift`
- Modify: `Knobler/NotchViewModel.swift`

**Interfaces:**
- Produces: `AskOption(label:description:preview:)`, `AskQuestion(question:header:multiSelect:options:)`, `AskRequest(id:questions:receivedAt:)`, `AskAnswer(labels:text:)`; no view model: `Mode.question`, `ask: AskRequest?`, `askPage: Int`, `askText: String`, `onAskAnswered: ((String, [String: AskAnswer]) -> Void)?`, `onAskCancelled: ((String) -> Void)?`, `enqueueAsk(_:)`, `clearAsk(id:)`, `answerAsk(_:)`, `cancelActiveAsk()`.

- [ ] **Step 1: Criar Knobler/Ask.swift com o modelo**

```swift
//
//  Ask.swift
//  Knobler
//
//  Pergunta interativa do Claude Code (AskUserQuestion) exibida como card
//  no notch. O hook PreToolUse publica via POST /ask; o card responde e o
//  hook devolve a resposta ao Claude. Modelo espelha o payload da tool.
//

import Foundation

struct AskOption: Equatable {
    var label: String
    var description: String
    /// Mockup ASCII exibido no painel direito do card (layout split).
    var preview: String?
}

struct AskQuestion: Equatable {
    var question: String
    /// Chip curto ("Abordagem", "Layout"…) mostrado antes do título.
    var header: String
    var multiSelect: Bool
    var options: [AskOption]
}

struct AskRequest: Equatable {
    var id: String
    /// Uma chamada da tool traz 1–4 perguntas; o card pagina entre elas.
    var questions: [AskQuestion]
    var receivedAt: Date
}

/// Resposta de UMA pergunta: labels clicados e/ou texto livre digitado/ditado.
struct AskAnswer: Equatable {
    var labels: [String]
    var text: String?
}
```

- [ ] **Step 2: Estado e modo no NotchViewModel**

Em `Knobler/NotchViewModel.swift`:

1. Junto de `@Published var dictation` (linha ~43), adicionar:

```swift
    /// Pergunta do Claude Code em exibição (card interativo).
    @Published var ask: AskRequest?
    /// Página corrente do card (chamada com N perguntas).
    @Published var askPage = 0
    /// Texto livre do card — vive aqui (e não em @State) pra receber o
    /// ditado por fan-out do AppDelegate.
    @Published var askText = ""
```

2. Junto de `private var queue: [NotchNotification]` (linha ~76), adicionar:

```swift
    private var askQueue: [AskRequest] = []
```

3. Em `enum Mode`, trocar para:

```swift
    enum Mode: Equatable {
        case closed, music, notification, hud, dictation, question
    }
```

4. Trocar `var mode` por (pergunta bloqueia um processo do usuário → topo):

```swift
    /// Prioridade: pergunta > ditado > notificação > HUD > música (hover).
    var mode: Mode {
        if ask != nil { return .question }
        if dictation != nil { return .dictation }
        if activeNotification != nil { return .notification }
        if hud != nil { return .hud }
        return expanded ? .music : .closed
    }
```

5. No fim da classe (depois de `showHUD`), adicionar:

```swift
    // MARK: - Perguntas do Claude Code

    /// Fiação do AppDelegate: resposta/cancelamento voltam pro servidor
    /// e sincronizam os outros monitores (primeira resposta vence).
    var onAskAnswered: ((String, [String: AskAnswer]) -> Void)?
    var onAskCancelled: ((String) -> Void)?

    func enqueueAsk(_ request: AskRequest) {
        if ask == nil {
            askPage = 0
            askText = ""
            ask = request
        } else if ask?.id != request.id,
                  !askQueue.contains(where: { $0.id == request.id }) {
            askQueue.append(request)
        }
    }

    /// Encerra o ask (respondido/cancelado em qualquer monitor) e promove
    /// o próximo da fila FIFO.
    func clearAsk(id: String) {
        askQueue.removeAll { $0.id == id }
        guard ask?.id == id else { return }
        ask = nil
        askPage = 0
        askText = ""
        if !askQueue.isEmpty {
            let next = askQueue.removeFirst()
            // respiro pra animação de fechar/abrir ler bem (padrão das notificações)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
                self?.enqueueAsk(next)
            }
        }
    }

    /// Chamado pelo card na última página com TODAS as respostas acumuladas.
    func answerAsk(_ answers: [String: AskAnswer]) {
        guard let current = ask else { return }
        onAskAnswered?(current.id, answers)
        clearAsk(id: current.id)
    }

    /// ✕ do card: pergunta volta pro terminal do Claude Code.
    func cancelActiveAsk() {
        guard let current = ask else { return }
        onAskCancelled?(current.id)
        clearAsk(id: current.id)
    }
```

- [ ] **Step 3: Regenerar projeto (arquivo novo!) e buildar**

Run: `xcodegen generate && xcodebuild -project Knobler.xcodeproj -scheme Knobler -configuration Release build 2>&1 | tail -3`
Expected: `** BUILD SUCCEEDED **`. (Vai falhar se `NotchView.swift` não compilar por causa do novo `case question` no switch — nesse caso o erro é "switch must be exhaustive"; adiantar SÓ o caso mínimo no switch de `NotchView.notch` e em `currentSize`: `case .question: EmptyView()` e `case .question: return CGSize(width: 460, height: topInset + 120)`. A UI real vem na Task 3.)

- [ ] **Step 4: Commit**

```bash
git add Knobler/Ask.swift Knobler/NotchViewModel.swift Knobler/NotchView.swift Knobler.xcodeproj
git commit -m "Perguntas: modelo Ask + Mode.question com prioridade máxima no view model"
```

---

### Task 2: Endpoints /ask no NotchAPIServer

**Files:**
- Modify: `Knobler/NotchAPIServer.swift`

**Interfaces:**
- Consumes: `AskRequest`/`AskQuestion`/`AskOption`/`AskAnswer` (Task 1).
- Produces: `onAsk: ((AskRequest) -> Void)?`, `onAskDismiss: ((String) -> Void)?`, `resolveAsk(id:answers:)`, `cancelAsk(id:)`, `askDiagnostics: [String: Any]`; HTTP: `POST /ask`, `GET /ask/<id>`, `POST /ask/<id>/cancel`.

- [ ] **Step 1: Estado e callbacks**

Em `Knobler/NotchAPIServer.swift`, depois de `var onMirror` (linha ~28), adicionar:

```swift
    /// Pergunta interativa (POST /ask): o hook do Claude Code cria, o card
    /// no notch responde, o hook lê via GET /ask/<id> (polling).
    var onAsk: ((AskRequest) -> Void)?
    /// Cancelamento vindo do hook (timeout): tira o card da tela.
    var onAskDismiss: ((String) -> Void)?
```

Depois de `private var activities` (linha ~31), adicionar:

```swift
    private struct PendingAsk {
        enum State { case pending, answered([String: AskAnswer]), cancelled }
        var state: State
        var updatedAt: Date
    }
    /// Respostas ficam retidas até a 1ª leitura do hook (ou TTL).
    private var pendingAsks: [String: PendingAsk] = [:]
    private static let askTTL: TimeInterval = 15 * 60
```

- [ ] **Step 2: TTL e limpeza**

Em `pruneExpired()` (linha ~64), adicionar antes do fechamento da função:

```swift
        // asks órfãos (hook morreu sem cancelar) também expiram
        let askCutoff = Date().addingTimeInterval(-Self.askTTL)
        pendingAsks = pendingAsks.filter { $0.value.updatedAt > askCutoff }
```

Em `stop()` (linha ~55), junto de `activities.removeAll()`:

```swift
        pendingAsks.removeAll()
```

- [ ] **Step 3: API pública pro AppDelegate + diagnóstico**

Depois de `emitActivity()` (linha ~76), adicionar:

```swift
    /// Card respondeu — primeira resposta vence; chamadas repetidas são no-op.
    func resolveAsk(id: String, answers: [String: AskAnswer]) {
        guard case .pending = pendingAsks[id]?.state else { return }
        pendingAsks[id] = PendingAsk(state: .answered(answers), updatedAt: Date())
    }

    /// ✕ no card: o hook lê cancelled e deixa a pergunta cair no terminal.
    func cancelAsk(id: String) {
        guard case .pending = pendingAsks[id]?.state else { return }
        pendingAsks[id] = PendingAsk(state: .cancelled, updatedAt: Date())
    }

    var askDiagnostics: [String: Any] {
        ["pending": pendingAsks.count]
    }
```

- [ ] **Step 4: Rotas HTTP**

Em `respond(to:)`, antes do bloco `GET /status` (linha ~151), adicionar:

```swift
        // ordem importa: "POST /ask " (com espaço) não colide com "POST /ask/<id>/cancel"
        if request.hasPrefix("POST /ask ") {
            guard let json,
                  let id = json["id"] as? String, !id.isEmpty,
                  let rawQuestions = json["questions"] as? [[String: Any]],
                  !rawQuestions.isEmpty
            else { return Self.badRequest("precisa de id e questions") }

            var questions: [AskQuestion] = []
            for raw in rawQuestions {
                guard let text = raw["question"] as? String,
                      let rawOptions = raw["options"] as? [[String: Any]]
                else { return Self.badRequest("question/options malformados") }
                let options: [AskOption] = rawOptions.compactMap { opt in
                    guard let label = opt["label"] as? String else { return nil }
                    return AskOption(
                        label: label,
                        description: opt["description"] as? String ?? "",
                        preview: opt["preview"] as? String
                    )
                }
                guard !options.isEmpty else { return Self.badRequest("opções sem label") }
                questions.append(AskQuestion(
                    question: text,
                    header: raw["header"] as? String ?? "",
                    multiSelect: raw["multiSelect"] as? Bool ?? false,
                    options: options
                ))
            }

            pendingAsks[id] = PendingAsk(state: .pending, updatedAt: Date())
            let ask = AskRequest(id: id, questions: questions, receivedAt: Date())
            DispatchQueue.main.async { [weak self] in self?.onAsk?(ask) }
            return Self.ok
        }

        if request.hasPrefix("GET /ask/") {
            let id = String(request.dropFirst("GET /ask/".count).prefix { $0 != " " })
            guard let entry = pendingAsks[id] else {
                return Self.http(status: "404 Not Found",
                                 body: #"{"ok":false,"error":"ask desconhecido"}"#)
            }
            switch entry.state {
            case .pending:
                return Self.http(status: "200 OK", body: #"{"answered":false}"#)
            case .cancelled:
                pendingAsks[id] = nil
                return Self.http(status: "200 OK", body: #"{"cancelled":true}"#)
            case .answered(let answers):
                pendingAsks[id] = nil // resposta é lida uma única vez
                let payload: [String: Any] = [
                    "answered": true,
                    "answers": answers.mapValues { answer -> [String: Any] in
                        var out: [String: Any] = ["labels": answer.labels]
                        if let text = answer.text { out["text"] = text }
                        return out
                    },
                ]
                let body = (try? JSONSerialization.data(withJSONObject: payload))
                    .flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
                return Self.http(status: "200 OK", body: body)
            }
        }

        if request.hasPrefix("POST /ask/"),
           request.prefix(while: { $0 != "\r" }).contains("/cancel") {
            let id = String(request.dropFirst("POST /ask/".count).prefix { $0 != "/" })
            pendingAsks[id] = nil
            DispatchQueue.main.async { [weak self] in self?.onAskDismiss?(id) }
            return Self.ok
        }
```

E no 404 final, trocar o array `usage` por:

```swift
            body: #"{"ok":false,"usage":["POST /notify {title, body?, app?, supacodeWorktree?, supacodeTab?}","POST /activity {id?, title, detail?, progress?, done?}","POST /mirror {on?}","POST /ask {id, questions}","GET /ask/<id>","POST /ask/<id>/cancel","GET /status"]}"#
```

- [ ] **Step 5: Buildar e commitar**

Run: `xcodebuild -project Knobler.xcodeproj -scheme Knobler -configuration Release build 2>&1 | tail -3`
Expected: `** BUILD SUCCEEDED **`

```bash
git add Knobler/NotchAPIServer.swift
git commit -m "Perguntas: endpoints POST /ask, GET /ask/<id> (polling) e cancel no servidor"
```

---

### Task 3: AskCardView + integração no NotchView + snapshots

**Files:**
- Modify: `Knobler/Ask.swift`
- Modify: `Knobler/NotchView.swift`
- Modify: `tools/main.swift`

**Interfaces:**
- Consumes: `vm.ask`/`askPage`/`askText`/`answerAsk`/`cancelActiveAsk` (Task 1), `vm.dictation` (existente).
- Produces: `AskCardView(vm:ask:)` (View); `case .question` renderizado no `NotchView` com `currentSize` próprio.

- [ ] **Step 1: AskCardView no Ask.swift**

No fim de `Knobler/Ask.swift`, adicionar (`import SwiftUI` junto do `import Foundation` no topo):

```swift
// MARK: - Card no notch

/// Card interativo: botões de opção (toggles no multi-select), paginação
/// 1/N, preview ASCII em split e texto livre (teclado ou ditado).
struct AskCardView: View {
    @ObservedObject var vm: NotchViewModel
    let ask: AskRequest

    /// Labels marcados na página corrente (multi-select).
    @State private var selected: Set<String> = []
    /// Respostas acumuladas das páginas anteriores (pergunta → resposta).
    @State private var answers: [String: AskAnswer] = [:]
    @State private var hovered: String?
    @FocusState private var textFocused: Bool

    private var page: Int { min(vm.askPage, ask.questions.count - 1) }
    private var question: AskQuestion { ask.questions[page] }
    private var hasPreview: Bool { question.options.contains { $0.preview != nil } }
    /// Preview exibido: opção sob o mouse; sem hover, a primeira com preview.
    private var previewText: String? {
        question.options.first { $0.label == hovered }?.preview
            ?? question.options.compactMap(\.preview).first
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            if hasPreview {
                HStack(alignment: .top, spacing: 10) {
                    optionList.frame(width: 250)
                    preview
                }
            } else {
                optionList
            }
            footer
        }
        .foregroundStyle(.white)
    }

    private var header: some View {
        HStack(spacing: 8) {
            if !question.header.isEmpty {
                Text(question.header)
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(.white.opacity(0.15)))
            }
            Text(question.question)
                .font(.subheadline.weight(.semibold))
                .lineLimit(2)
            Spacer(minLength: 0)
            if ask.questions.count > 1 {
                Text("\(page + 1)/\(ask.questions.count)")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.5))
            }
            Button { vm.cancelActiveAsk() } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.white.opacity(0.5))
            }
            .buttonStyle(.plain)
            .help("Responder no terminal")
        }
    }

    private var optionList: some View {
        VStack(spacing: 4) {
            ForEach(question.options, id: \.label) { option in
                optionRow(option)
            }
            if question.multiSelect {
                Button { submitPage(labels: Array(selected)) } label: {
                    Text("Confirmar")
                        .font(.footnote.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .background(RoundedRectangle(cornerRadius: 8)
                            .fill(.white.opacity(selected.isEmpty ? 0.08 : 0.25)))
                }
                .buttonStyle(.plain)
                .disabled(selected.isEmpty)
            }
        }
    }

    private func optionRow(_ option: AskOption) -> some View {
        Button {
            if question.multiSelect {
                if selected.contains(option.label) {
                    selected.remove(option.label)
                } else {
                    selected.insert(option.label)
                }
            } else {
                submitPage(labels: [option.label])
            }
        } label: {
            HStack(spacing: 8) {
                if question.multiSelect {
                    Image(systemName: selected.contains(option.label)
                        ? "checkmark.square.fill" : "square")
                        .font(.footnote)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(option.label)
                        .font(.footnote.weight(.semibold))
                    if !option.description.isEmpty {
                        Text(option.description)
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.6))
                            .lineLimit(2)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(RoundedRectangle(cornerRadius: 8)
                .fill(.white.opacity(hovered == option.label ? 0.18 : 0.08)))
        }
        .buttonStyle(.plain)
        .onHover { inside in
            if inside {
                hovered = option.label
            } else if hovered == option.label {
                hovered = nil
            }
        }
    }

    private var preview: some View {
        ScrollView([.vertical, .horizontal]) {
            Text(previewText ?? "")
                .font(.system(size: 9, design: .monospaced))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(6)
        .frame(maxHeight: .infinity)
        .background(RoundedRectangle(cornerRadius: 8).fill(.white.opacity(0.06)))
    }

    private var footer: some View {
        HStack(spacing: 8) {
            if case .recording(let level) = vm.dictation {
                // ditado ativo alimenta este campo: nível DENTRO do card
                Circle().fill(.red).frame(width: 6, height: 6)
                Capsule().fill(.white)
                    .frame(width: max(4, 40 * CGFloat(level)), height: 4)
            }
            TextField("Outra resposta… (Enter envia; ⌥ direita dita)", text: $vm.askText)
                .textFieldStyle(.plain)
                .font(.footnote)
                .focused($textFocused)
                .onSubmit {
                    let text = vm.askText.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !text.isEmpty else { return }
                    submitPage(labels: question.multiSelect ? Array(selected) : [],
                               text: text)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(RoundedRectangle(cornerRadius: 8).fill(.white.opacity(0.08)))
        }
    }

    /// Grava a resposta da página; última página envia tudo de uma vez.
    private func submitPage(labels: [String], text: String? = nil) {
        answers[question.question] = AskAnswer(labels: labels, text: text)
        vm.askText = ""
        selected = []
        hovered = nil
        if page + 1 < ask.questions.count {
            vm.askPage += 1
        } else {
            vm.answerAsk(answers)
        }
    }
}
```

- [ ] **Step 2: Renderizar no NotchView**

Em `Knobler/NotchView.swift`:

1. No `switch vm.mode` do `notch` (linha ~73), o caso (substituindo o `EmptyView()` provisório da Task 1, se existir):

```swift
            case .question:
                questionCard
                    // pergunta desce do notch, como as notificações
                    .transition(.blurReplace.combined(with: .move(edge: .top)))
```

2. Em `currentSize` (linha ~147), o caso (substituindo o provisório da Task 1, se existir):

```swift
        case .question:
            guard let ask = vm.ask else {
                return CGSize(width: 460, height: topInset + 120)
            }
            let question = ask.questions[min(vm.askPage, ask.questions.count - 1)]
            let hasPreview = question.options.contains { $0.preview != nil }
            // título+chip (46) + opções (48 cada) + rodapé com campo de texto (44)
            var height = topInset + 46 + CGFloat(question.options.count) * 48 + 44
            if question.multiSelect { height += 34 }  // botão Confirmar
            if hasPreview { height = max(height, topInset + 320) }
            return CGSize(width: hasPreview ? 660 : 460, height: min(height, 500))
```

3. Depois do bloco `dictationPill` (linha ~252), adicionar:

```swift
    // MARK: - Card de pergunta (Claude Code)

    @ViewBuilder
    private var questionCard: some View {
        if let ask = vm.ask {
            AskCardView(vm: vm, ask: ask)
                .frame(width: currentSize.width - 40)
                .padding(.top, topInset + 6)
                .padding(.bottom, 12)
        }
    }
```

4. Em `interactiveNotch` (linha ~137), junto das outras `.animation`, adicionar (troca de página e chegada/saída do card animam a moldura):

```swift
        .animation(morphAnimation, value: vm.ask)
        .animation(morphAnimation, value: vm.askPage)
```

- [ ] **Step 3: Cenários no harness**

Em `tools/main.swift`, no fim do array `scenarios` (depois de `"dictation-error"`, linha ~157), adicionar:

```swift
    Scenario(name: "ask-simple", realNotch: true) { vm, _ in
        vm.ask = AskRequest(id: "s1", questions: [
            AskQuestion(
                question: "Qual abordagem seguir?", header: "Abordagem",
                multiSelect: false,
                options: [
                    AskOption(label: "Hook PreToolUse",
                              description: "Intercepta toda pergunta e envia pro notch",
                              preview: nil),
                    AskOption(label: "Servidor MCP",
                              description: "Tool dedicada configurada por projeto",
                              preview: nil),
                ])
        ], receivedAt: Date())
    },
    Scenario(name: "ask-multiselect", realNotch: true) { vm, _ in
        vm.ask = AskRequest(id: "s2", questions: [
            AskQuestion(
                question: "Quais checagens rodar?", header: "Validação",
                multiSelect: true,
                options: [
                    AskOption(label: "Build Release", description: "xcodebuild", preview: nil),
                    AskOption(label: "Snapshots", description: "harness visual", preview: nil),
                    AskOption(label: "E2E manual", description: "roteiro no app real", preview: nil),
                ])
        ], receivedAt: Date())
    },
    Scenario(name: "ask-preview", realNotch: true) { vm, _ in
        vm.ask = AskRequest(id: "s3", questions: [
            AskQuestion(
                question: "Qual layout do card?", header: "Layout",
                multiSelect: false,
                options: [
                    AskOption(label: "Split",
                              description: "opções + preview",
                              preview: "+----------+-----------+\n| opções   | preview   |\n|          |  ascii    |\n+----------+-----------+"),
                    AskOption(label: "Empilhado",
                              description: "preview embaixo",
                              preview: "+----------------------+\n|        opções        |\n+----------------------+\n|       preview        |\n+----------------------+"),
                ])
        ], receivedAt: Date())
    },
    Scenario(name: "ask-paged", realNotch: true) { vm, _ in
        vm.ask = AskRequest(id: "s4", questions: [
            AskQuestion(question: "Pergunta um?", header: "Um", multiSelect: false,
                        options: [AskOption(label: "A", description: "", preview: nil)]),
            AskQuestion(question: "Pergunta dois de três?", header: "Dois", multiSelect: false,
                        options: [
                            AskOption(label: "Sim", description: "segue", preview: nil),
                            AskOption(label: "Não", description: "para", preview: nil),
                        ]),
            AskQuestion(question: "Pergunta três?", header: "Três", multiSelect: false,
                        options: [AskOption(label: "B", description: "", preview: nil)]),
        ], receivedAt: Date())
        vm.askPage = 1
    },
```

- [ ] **Step 4: Rodar o harness e OLHAR os PNGs**

Run: `bash tools/snapshot.sh`
Expected: todos os cenários renderizam. Abrir com Read `Snapshots/ask-simple.png`, `ask-multiselect.png`, `ask-preview.png` e `ask-paged.png` e conferir visualmente: botões com label+descrição legíveis, checkboxes no multi-select + Confirmar, preview mono à direita no split, indicador "2/3" no paginado, ✕ no canto, campo "Outra resposta…" no rodapé — nada cortado pela moldura.

- [ ] **Step 5: Buildar e commitar**

Run: `xcodebuild -project Knobler.xcodeproj -scheme Knobler -configuration Release build 2>&1 | tail -3`
Expected: `** BUILD SUCCEEDED **`

```bash
git add Knobler/Ask.swift Knobler/NotchView.swift tools/main.swift Snapshots
git commit -m "Perguntas: AskCardView (botões, multi-select, preview split, paginação) + snapshots"
```

---

### Task 4: Teclado condicional na janela + fiação no AppDelegate

**Files:**
- Modify: `Knobler/NotchWindow.swift`
- Modify: `Knobler/KnoblerApp.swift`

**Interfaces:**
- Consumes: `apiServer.onAsk`/`onAskDismiss`/`resolveAsk`/`cancelAsk`/`askDiagnostics` (Task 2), `vm.enqueueAsk`/`clearAsk`/`onAskAnswered`/`onAskCancelled` (Task 1).
- Produces: `NotchWindow.allowsKeyboard: Bool` (default false).

- [ ] **Step 1: canBecomeKey condicional**

Em `Knobler/NotchWindow.swift`, trocar as duas overrides do fim (linhas 38–39) por:

```swift
    /// true SÓ enquanto um card de pergunta está na tela (setado por Combine
    /// no AppDelegate). Fora disso o notch nunca rouba o foco do teclado —
    /// clicar no campo de texto do card torna a janela key sem ativar o app
    /// (nonactivatingPanel), então o terminal continua frontmost.
    var allowsKeyboard = false

    override var canBecomeKey: Bool { allowsKeyboard }
    override var canBecomeMain: Bool { false }
```

- [ ] **Step 2: Fan-out, resposta, som e teclado no AppDelegate**

Em `Knobler/KnoblerApp.swift`:

1. Junto de `private var apiCancellable` (linha ~39), adicionar:

```swift
    private var askKeyCancellables = Set<AnyCancellable>()
```

2. Em `applicationDidFinishLaunching`, depois do bloco `apiServer.onMirror` (linha ~179), adicionar:

```swift
        // perguntas do Claude Code: card em TODAS as telas; primeira resposta vence
        apiServer.onAsk = { [weak self] request in
            NSSound(named: "Pop")?.play()  // uma vez, na chegada — sem lembretes
            self?.notches.values.forEach { $0.viewModel.enqueueAsk(request) }
        }
        apiServer.onAskDismiss = { [weak self] id in
            self?.notches.values.forEach { $0.viewModel.clearAsk(id: id) }
        }
```

3. Em `placeWindows()`, dentro do `else` que cria o notch novo (depois de `notches[id] = notch`, linha ~320), adicionar:

```swift
                // resposta/cancelamento de QUALQUER monitor volta pro servidor
                // e limpa os demais (primeira resposta vence)
                viewModel.onAskAnswered = { [weak self] id, answers in
                    self?.apiServer.resolveAsk(id: id, answers: answers)
                    self?.notches.values.forEach { $0.viewModel.clearAsk(id: id) }
                }
                viewModel.onAskCancelled = { [weak self] id in
                    self?.apiServer.cancelAsk(id: id)
                    self?.notches.values.forEach { $0.viewModel.clearAsk(id: id) }
                }
                // janela só aceita teclado enquanto o card existe — CRÍTICO
                // reverter, senão o notch rouba foco pra sempre
                viewModel.$ask
                    .map { $0 != nil }
                    .removeDuplicates()
                    .sink { [weak panel] active in
                        panel?.allowsKeyboard = active
                        if !active, panel?.isKeyWindow == true { panel?.resignKey() }
                    }
                    .store(in: &askKeyCancellables)
```

4. No `statusProvider` (linha ~196), junto de `status["dictation"]`, adicionar:

```swift
            status["ask"] = self?.apiServer.askDiagnostics ?? [:]
```

- [ ] **Step 3: Buildar e commitar**

Run: `xcodebuild -project Knobler.xcodeproj -scheme Knobler -configuration Release build 2>&1 | tail -3`
Expected: `** BUILD SUCCEEDED **`

```bash
git add Knobler/NotchWindow.swift Knobler/KnoblerApp.swift
git commit -m "Perguntas: fan-out multi-monitor, som de chegada e teclado condicional na janela"
```

---

### Task 5: Ditado alimenta o campo do card

**Files:**
- Modify: `Knobler/Dictation.swift`
- Modify: `Knobler/KnoblerApp.swift`

**Interfaces:**
- Consumes: `vm.ask`/`vm.askText` (Task 1).
- Produces: `DictationController.transcriptSink: ((String) -> Bool)?` — retorna true quando o texto foi consumido (não colar no app ativo).

- [ ] **Step 1: Sink no DictationController**

Em `Knobler/Dictation.swift`:

1. Junto de `var onState` (linha ~163), adicionar:

```swift
    /// Desvio da transcrição: retorna true se alguém consumiu o texto
    /// (card de pergunta na tela) — aí NÃO cola no app ativo.
    var transcriptSink: ((String) -> Bool)?
```

2. Em `finish()`, trocar a linha `if !trimmed.isEmpty { Self.insert(trimmed) }` (linha ~269) por:

```swift
                    if !trimmed.isEmpty, self.transcriptSink?(trimmed) != true {
                        Self.insert(trimmed)
                    }
```

- [ ] **Step 2: Roteamento no AppDelegate**

Em `Knobler/KnoblerApp.swift`, depois de `dictation.start()` (linha ~88), adicionar:

```swift
        // ditado durante uma pergunta alimenta o campo do card, não o app ativo
        dictation.transcriptSink = { [weak self] text in
            guard let self else { return false }
            let asking = self.notches.values.filter { $0.viewModel.ask != nil }
            guard !asking.isEmpty else { return false }
            asking.forEach {
                let vm = $0.viewModel
                vm.askText = vm.askText.isEmpty ? text : vm.askText + " " + text
            }
            return true
        }
```

- [ ] **Step 3: Buildar e commitar**

Run: `xcodebuild -project Knobler.xcodeproj -scheme Knobler -configuration Release build 2>&1 | tail -3`
Expected: `** BUILD SUCCEEDED **`

```bash
git add Knobler/Dictation.swift Knobler/KnoblerApp.swift
git commit -m "Perguntas: ditado (⌥ direita) alimenta o campo do card em vez do app ativo"
```

---

### Task 6: Hook PreToolUse + instalador + knobler ask

**Files:**
- Create: `tools/claude-hook/knobler-ask.sh`
- Create: `tools/claude-hook/install.sh`
- Modify: `tools/knobler`

**Interfaces:**
- Consumes: HTTP `POST /ask`, `GET /ask/<id>`, `POST /ask/<id>/cancel` (Task 2).
- Produces: hook instalado em `~/.claude/hooks/knobler-ask.sh`, matcher `AskUserQuestion` com `timeout: 600` em `~/.claude/settings.json`; subcomando `knobler ask` pra teste manual.

- [ ] **Step 1: Criar tools/claude-hook/knobler-ask.sh**

```bash
#!/bin/bash
# Hook PreToolUse do Claude Code: intercepta AskUserQuestion e manda a
# pergunta pro card do Knobler. Respondida lá → devolve ao Claude via
# permissionDecision deny + reason (o modelo continua com a resposta).
# Knobler fechado, ✕ no card ou timeout → sai sem output e a pergunta
# aparece no terminal como sempre. Nunca falha a sessão: exit 0 em tudo.
set -uo pipefail
PORT="${KNOBLER_PORT:-4477}"
INPUT="$(cat)"
ID="ask-$$-$(date +%s)"

PAYLOAD="$(printf '%s' "$INPUT" | jq -c --arg id "$ID" \
    '{id: $id, questions: .tool_input.questions}')" || exit 0

# Knobler fora do ar → curl falha em ms → fluxo normal do terminal
curl -sf -m 1 -X POST "localhost:$PORT/ask" -d "$PAYLOAD" >/dev/null 2>&1 || exit 0

DEADLINE=$(( $(date +%s) + 570 ))  # < timeout de 600s do hook, folga pro cancel
while [ "$(date +%s)" -lt "$DEADLINE" ]; do
    STATE="$(curl -sf -m 2 "localhost:$PORT/ask/$ID" 2>/dev/null)" || exit 0
    if [ "$(printf '%s' "$STATE" | jq -r '.cancelled // false')" = "true" ]; then
        exit 0  # ✕ no card → pergunta vai pro terminal
    fi
    if [ "$(printf '%s' "$STATE" | jq -r '.answered // false')" = "true" ]; then
        printf '%s' "$STATE" | jq -c '{
            hookSpecificOutput: {
                hookEventName: "PreToolUse",
                permissionDecision: "deny",
                permissionDecisionReason: (
                    "O usuário respondeu via Knobler (card no notch): "
                    + (.answers | to_entries | map(
                        "\"" + .key + "\" = " + (
                            if (.value.text // "") != ""
                            then "\"" + .value.text + "\""
                            else (.value.labels | map("\"" + . + "\"") | join(", "))
                            end
                        )) | join("; "))
                    + ". Prossiga considerando essas respostas como a resposta "
                    + "do usuário; NÃO repita a pergunta."
                )
            }
        }'
        exit 0
    fi
    sleep 0.3
done
# timeout: remove o card órfão e devolve ao terminal
curl -sf -m 1 -X POST "localhost:$PORT/ask/$ID/cancel" >/dev/null 2>&1 || true
exit 0
```

- [ ] **Step 2: Criar tools/claude-hook/install.sh**

```bash
#!/bin/bash
# Instala o hook do Knobler no Claude Code (global, idempotente):
# copia o script pra ~/.claude/hooks/ e registra o matcher AskUserQuestion
# com timeout de 600s em ~/.claude/settings.json.
set -euo pipefail
HOOK="$HOME/.claude/hooks/knobler-ask.sh"
SETTINGS="$HOME/.claude/settings.json"

mkdir -p "$HOME/.claude/hooks"
cp "$(dirname "$0")/knobler-ask.sh" "$HOOK"
chmod +x "$HOOK"

[ -f "$SETTINGS" ] || echo '{}' > "$SETTINGS"
TMP="$(mktemp)"
jq --arg cmd "$HOOK" '
    .hooks.PreToolUse = (
        ((.hooks.PreToolUse // [])
            | map(select(((.hooks // []) | any(.command == $cmd)) | not)))
        + [{matcher: "AskUserQuestion",
            hooks: [{type: "command", command: $cmd, timeout: 600}]}]
    )
' "$SETTINGS" > "$TMP" && mv "$TMP" "$SETTINGS"
echo "hook instalado: $HOOK (matcher AskUserQuestion, timeout 600s)"
echo "vale a partir da PRÓXIMA sessão do Claude Code"
```

- [ ] **Step 3: Subcomando ask no tools/knobler**

Em `tools/knobler`:

1. No comentário de uso do topo (linhas 4–6), adicionar após a linha do `done`:

```bash
#   knobler ask "Pergunta?" "Opção A" "Opção B" [...]   (espera e imprime a resposta)
```

2. Antes do `*)` final do `case`, adicionar:

```bash
ask)
    q="${1:?uso: knobler ask \"Pergunta?\" \"Opção A\" \"Opção B\" [...]}"
    shift
    [ $# -ge 2 ] || { echo "knobler: ask precisa de 2+ opções" >&2; exit 2; }
    id="cli-$$"
    opts="$(python3 -c '
import json, sys
print(json.dumps([{"label": a, "description": ""} for a in sys.argv[1:]]))' "$@")"
    post /ask "{\"id\":\"$id\",\"questions\":[{\"question\":$(esc "$q"),\"header\":\"CLI\",\"multiSelect\":false,\"options\":$opts}]}"
    while :; do
        state="$(curl -sf -m 2 "localhost:$PORT/ask/$id")" \
            || { echo "knobler: API caiu no meio" >&2; exit 1; }
        case "$state" in
        *'"answered":true'* | *'"cancelled":true'*)
            echo "$state"
            exit 0
            ;;
        esac
        sleep 0.3
    done
    ;;
```

- [ ] **Step 4: Checar sintaxe e instalar**

Run: `chmod +x tools/claude-hook/knobler-ask.sh tools/claude-hook/install.sh && bash -n tools/claude-hook/knobler-ask.sh && bash -n tools/claude-hook/install.sh && bash -n tools/knobler && bash tools/claude-hook/install.sh && jq '.hooks.PreToolUse' ~/.claude/settings.json`
Expected: sem erros de sintaxe; o `jq` final mostra exatamente UMA entrada com matcher `AskUserQuestion`, command apontando pra `~/.claude/hooks/knobler-ask.sh` e `timeout: 600`. Rodar `install.sh` DUAS vezes e conferir que não duplica.

- [ ] **Step 5: Commit**

```bash
git add tools/claude-hook tools/knobler
git commit -m "Perguntas: hook PreToolUse (AskUserQuestion → notch) + instalador + knobler ask"
```

---

### Task 7: Deploy + validação E2E

**Files:** nenhum novo — deploy e teste do app real.

- [ ] **Step 1: Reinstalar e relançar**

```bash
osascript -e 'tell application "Knobler" to quit'; sleep 1
ditto "$(ls -d ~/Library/Developer/Xcode/DerivedData/Knobler-*/Build/Products/Release/Knobler.app | head -1)" /Applications/Knobler.app
open /Applications/Knobler.app && sleep 2 && pgrep -x Knobler
```

Expected: PID impresso.

- [ ] **Step 2: Ciclo completo via curl (sem Claude)**

```bash
curl -s -X POST localhost:4477/ask -d '{"id":"t1","questions":[{"question":"Funciona?","header":"Teste","multiSelect":false,"options":[{"label":"Sim","description":"tudo certo"},{"label":"Não","description":"algo quebrou"}]}]}'
curl -s localhost:4477/ask/t1
```

Expected: primeiro retorna `{"ok":true}` e o card aparece no notch com som; segundo retorna `{"answered":false}`. Então PEDIR AO USUÁRIO para clicar "Sim" no card, e rodar `curl -s localhost:4477/ask/t1` de novo → `{"answered":true,"answers":{"Funciona?":{"labels":["Sim"]}}}`; um segundo GET → 404 (lida uma vez). Conferir `curl -s localhost:4477/status | python3 -m json.tool | grep -A2 '"ask"'` → `"pending": 0`.

- [ ] **Step 3: Fila FIFO e cancel via curl**

```bash
curl -s -X POST localhost:4477/ask -d '{"id":"f1","questions":[{"question":"Primeira?","header":"1","multiSelect":false,"options":[{"label":"A","description":""},{"label":"B","description":""}]}]}'
curl -s -X POST localhost:4477/ask -d '{"id":"f2","questions":[{"question":"Segunda?","header":"2","multiSelect":false,"options":[{"label":"C","description":""},{"label":"D","description":""}]}]}'
curl -s -X POST localhost:4477/ask/f1/cancel
curl -s -X POST localhost:4477/ask/f2/cancel
```

Expected: card mostra "Primeira?" (f2 na fila); o primeiro cancel faz o card trocar para "Segunda?"; o segundo limpa o notch.

- [ ] **Step 4: E2E manual (pedir ao usuário)**

O agente não tem como clicar no card — pedir ao usuário este roteiro:

1. `tools/knobler ask "Qual opção?" "Alfa" "Beta"` num terminal → card no notch → clicar "Beta" → o comando imprime `{"answered":true,...}` com `Beta`.
2. De novo, mas digitar no campo "Outra resposta…" e Enter → resposta com `text`. Conferir que ao clicar no campo o TERMINAL CONTINUA com a barra de título ativa (janela do notch vira key sem ativar o app) e que depois de responder o teclado volta ao terminal (digitar no terminal funciona sem clicar).
3. De novo, mas segurar ⌥ direita e ditar → texto aparece no campo com o nível dentro do card → Enter.
4. Abrir uma sessão NOVA do Claude Code em qualquer projeto → `/grill-me` em algum tema → as perguntas aparecem no notch → responder botão e texto → o Claude continua com as respostas SEM repetir a pergunta no terminal.
5. ✕ num card vindo do Claude → a pergunta aparece no terminal normalmente (fallback).
6. Fechar o Knobler → pergunta do Claude vai direto pro terminal (regressão zero).
7. Ditado normal (sem card na tela) continua colando no cursor do app ativo.

Se no passo 4 o Claude tratar o deny como recusa em vez de usar a resposta (comportamento do harness com AskUserQuestion), ajustar SÓ o texto do reason no `knobler-ask.sh` (ele é a interface com o modelo) — a mecânica não muda.

- [ ] **Step 5: Fechar a versão**

Depois do OK do usuário no E2E:

```bash
git add -A && git status --short
```

Conferir que só entraram arquivos da feature; atualizar `HANDOFF.md` (nova seção v0.9: feature, decisões, pendências) e a seção v0.9 no MEMORY.md do projeto; commitar:

```bash
git commit -m "Perguntas do Claude Code no notch v0.9: hook PreToolUse → card interativo → resposta ao Claude"
```

---

## Self-review (feito na escrita)

- **Cobertura da spec:** endpoints+TTL+fila-de-leitura (T2), modelo+prioridade+FIFO (T1), card com botões/multi-select/paginação/preview/✕ (T3), teclado condicional+fan-out+som+/status (T4), ditado no campo (T5), hook+instalador+CLI (T6), validação completa incluindo regressão com Knobler fechado (T7). Esc como atalho de cancelar ficou de fora do v1 (✕ cobre) — simplificação deliberada; anotar no HANDOFF se incomodar.
- **Placeholders:** nenhum; todo step tem código ou comando completo com expected.
- **Consistência de tipos:** `AskRequest/AskQuestion/AskOption/AskAnswer` (T1) usados em T2 (parse/serialização), T3 (view), T4 (fan-out); `resolveAsk(id:answers:)`/`cancelAsk(id:)` (T2) casam com `onAskAnswered`/`onAskCancelled` (T1→T4); `transcriptSink: ((String) -> Bool)?` (T5) consumido no AppDelegate (T5 Step 2); JSON do hook (`labels`/`text`) casa com a serialização do GET (T2 Step 4).
- **Riscos declarados:** (1) comportamento do deny+reason com `AskUserQuestion` é a única parte não testável antes do E2E — T7 Step 4 tem o plano B (ajustar só o reason). (2) `canBecomeKey` condicional é a mudança mais sensível — constraint global + revert automático via Combine em T4, validado explicitamente no E2E passo 2.
