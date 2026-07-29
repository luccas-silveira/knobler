# Histórico de notificações + Nota rápida — plano de implementação

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Dar ao notch um histórico das notificações das últimas 24 h, aberto por
um puxão longo pra baixo, e uma nota rápida efêmera ligada pelo menu da barra.

**Architecture:** Dois stores singleton `ObservableObject` (`NotificationHistory`,
`QuickNote`) fora do `NotchViewModel`, porque existe um view model por tela. O
gesto vira uma função pura (`NotchGesture.verticalTarget`) chamada pelo monitor
de scroll que já existe. Nenhuma das duas features toca disco.

**Tech Stack:** Swift 5, AppKit + SwiftUI, XcodeGen, self-checks via `swiftc` +
`assert` (sem framework de teste).

## Global Constraints

- Deployment target **macOS 14.2**. `glassEffect`/Liquid Glass só sob
  `if #available(macOS 26, *)` com fallback — e hoje não é usado.
- Comentários e strings de UI em **pt-BR**.
- Simplificação deliberada leva comentário `// ponytail:`.
- **Nunca** editar `Knobler.xcodeproj` à mão. Arquivo novo em `Knobler/` exige
  `xcodegen generate`.
- **Nunca** editar `MARKETING_VERSION` nem criar tag à mão. Mudanças vão em
  `## [Unreleased]` do `CHANGELOG.md`.
- Arquivo novo em `Knobler/` que a `NotchView` use precisa entrar **também** na
  lista manual de fontes de `tools/snapshot.sh`.
- Nenhuma das duas features persiste em disco: sem `UserDefaults`, sem JSON.

## File Structure

| Arquivo | Responsabilidade |
|---|---|
| `Knobler/NotchNotification.swift` | **novo** — o struct do card, extraído de `NotificationInterceptor.swift` para poder compilar sem `AppSettings`/`NotificationRules` |
| `Knobler/NotificationHistory.swift` | **novo** — store em memória, poda de 24 h, dedupe |
| `Knobler/NotchGesture.swift` | **novo** — `verticalTarget`, função pura do acumulador de scroll |
| `Knobler/HistoryListView.swift` | **novo** — a lista no card expandido |
| `Knobler/QuickNote.swift` | **novo** — estado da nota (`active`, `text`, `editing`) |
| `Knobler/NotchViewModel.swift` | modificado — `historyOpen`, `record()` no `enqueue`, guarda de foco no `setHover` |
| `Knobler/NotchView.swift` | modificado — histórico e nota no `expandedContent`, alcinha, `keyboardAllowed` |
| `Knobler/KnoblerApp.swift` | modificado — `handleScroll` usa `verticalTarget`, item "Nota rápida" no menu |
| `tools/historycheck.swift` | **novo** — self-check do store e do gesto |
| `tools/check.sh`, `tools/snapshot.sh`, `tools/main.swift` | modificados — registrar o check, as fontes e o cenário |

---

### Task 1: Extrair `NotchNotification` para arquivo próprio

Puro movimento de código, sem mudança de comportamento. Existe porque
`NotificationInterceptor.swift` **não compila isolado** (depende de
`AppSettings` e `NotificationRules`, que arrastam o app inteiro), e o self-check
da Task 2 precisa do struct.

**Files:**
- Create: `Knobler/NotchNotification.swift`
- Modify: `Knobler/NotificationInterceptor.swift:15-43` (remover o struct)
- Modify: `tools/snapshot.sh:7` (adicionar a fonte nova)

**Interfaces:**
- Consumes: nada.
- Produces: `struct NotchNotification: Identifiable, Equatable` com os campos
  `id: UUID`, `appName: String?`, `title: String`, `body: String`,
  `bundleID: String?`, `supacodeWorktree: String?`, `supacodeTab: String?`,
  `openURL: String?`, `iconURL: String?`, `iconEmoji: String?`,
  `iconColor: NSColor?`, `actionTitles: [String]`, `actionToken: UUID?`,
  `revealsDownloads: Bool`, `webhookID: String?`, `date: Date`.

- [ ] **Step 1: Criar o arquivo novo com o struct**

Recortar as linhas 15–43 de `Knobler/NotificationInterceptor.swift` (do
`struct NotchNotification: Identifiable, Equatable {` até o `}` que o fecha,
inclusive os comentários de cada campo) e colar em `Knobler/NotchNotification.swift`
com este cabeçalho:

```swift
//
//  NotchNotification.swift
//  Knobler
//
//  O que um card do notch carrega. Mora fora do NotificationInterceptor porque
//  o interceptor depende de AppSettings/NotificationRules e não compila isolado
//  — e o self-check do histórico precisa só do struct.
//

import AppKit

// (struct colado aqui, sem alterar nenhum campo)
```

- [ ] **Step 2: Verificar que o struct compila sozinho**

Run: `xcrun swiftc -parse-as-library -swift-version 5 -typecheck Knobler/NotchNotification.swift`
Expected: sem saída, código de saída 0. (Antes da extração, o mesmo comando em
`NotificationInterceptor.swift` falha com `cannot find 'NotificationRules' in scope`.)

- [ ] **Step 3: Registrar a fonte no harness de snapshot**

Em `tools/snapshot.sh`, adicionar a linha logo antes de `Knobler/NotificationInterceptor.swift`:

```bash
  Knobler/NotchNotification.swift \
```

- [ ] **Step 4: Regenerar o projeto e compilar**

Run:
```bash
xcodegen generate
xcodebuild -project Knobler.xcodeproj -scheme Knobler -configuration Debug build
```
Expected: `BUILD SUCCEEDED`. Nenhum outro arquivo precisa de `import` novo — os
arquivos do mesmo alvo já enxergam o struct.

- [ ] **Step 5: Rodar o harness visual pra garantir que nada quebrou**

Run: `./tools/snapshot.sh`
Expected: termina sem erro e regrava `Snapshots/*.png`.

- [ ] **Step 6: Commit**

```bash
git add Knobler/NotchNotification.swift Knobler/NotificationInterceptor.swift tools/snapshot.sh Knobler.xcodeproj
git commit -m "refactor: NotchNotification em arquivo próprio

O interceptor não compila isolado (AppSettings, NotificationRules), então o
struct do card ficava fora do alcance de qualquer self-check. Movido sem
mudança de comportamento."
```

---

### Task 2: `NotificationHistory` + self-check

**Files:**
- Create: `Knobler/NotificationHistory.swift`
- Create: `tools/historycheck.swift`
- Modify: `tools/check.sh:70` (registrar o check)
- Modify: `tools/snapshot.sh:7` (adicionar a fonte)

**Interfaces:**
- Consumes: `NotchNotification` (Task 1).
- Produces:
  - `final class NotificationHistory: ObservableObject`
  - `static let shared: NotificationHistory`
  - `@Published private(set) var items: [NotchNotification]` — mais recente primeiro
  - `func record(_ n: NotchNotification)`
  - `func prune(now: Date = Date())`

As asserções ficam em `tools/historycheck.swift`, não num `selfCheck()` dentro
da classe — o store não precisa carregar código de teste no binário do app.

- [ ] **Step 1: Escrever o teste que falha**

Criar `tools/historycheck.swift`. Ele também vai hospedar o check do gesto
(Task 3); por ora só o histórico:

```swift
//
//  tools/historycheck.swift — self-check do histórico de notificações.
//  NÃO faz parte do alvo do app.
//
//  Rodar:
//  xcrun swiftc -parse-as-library -swift-version 5 \
//    Knobler/NotchNotification.swift Knobler/NotificationHistory.swift \
//    tools/historycheck.swift -o /tmp/historycheck && /tmp/historycheck
//

import AppKit

@main
struct HistoryCheck {
    static func main() {
        testOrdem()
        testPoda()
        testWebhookSubstitui()
        testMesmoIDUmaVez()
        print("✅ historycheck ok")
    }

    /// Mais recente primeiro — a lista é lida de cima pra baixo.
    static func testOrdem() {
        let h = NotificationHistory()
        h.record(NotchNotification(appName: "A", title: "primeira", body: ""))
        h.record(NotchNotification(appName: "B", title: "segunda", body: ""))
        assert(h.items.map(\.title) == ["segunda", "primeira"], "ordem invertida")
    }

    /// Poda por idade: 23 h fica, 25 h sai. `prune(now:)` recebe o agora pra
    /// não precisar esperar um dia dentro do teste.
    static func testPoda() {
        let h = NotificationHistory()
        h.record(NotchNotification(appName: "A", title: "velha", body: ""))
        h.record(NotchNotification(appName: "B", title: "nova", body: ""))
        h.prune(now: Date().addingTimeInterval(24 * 3600 + 60))
        assert(h.items.isEmpty, "tudo com mais de 24 h devia sair")

        let h2 = NotificationHistory()
        h2.record(NotchNotification(appName: "A", title: "recente", body: ""))
        h2.prune(now: Date().addingTimeInterval(23 * 3600))
        assert(h2.items.count == 1, "23 h ainda está dentro da janela")
    }

    /// Barra de progresso que atualiza 40 vezes é UMA linha, não 40.
    static func testWebhookSubstitui() {
        let h = NotificationHistory()
        h.record(NotchNotification(appName: "Deploy", title: "10%", body: "", webhookID: "d1"))
        h.record(NotchNotification(appName: "Deploy", title: "90%", body: "", webhookID: "d1"))
        h.record(NotchNotification(appName: "Outro", title: "x", body: "", webhookID: "d2"))
        assert(h.items.count == 2, "mesmo webhookID devia substituir")
        assert(h.items.first?.title == "90%", "a substituta vai pro topo")
    }

    /// Multi-monitor: o enqueue roda uma vez por tela com a MESMA notificação.
    static func testMesmoIDUmaVez() {
        let h = NotificationHistory()
        let n = NotchNotification(appName: "A", title: "única", body: "")
        h.record(n)
        h.record(n)
        assert(h.items.count == 1, "mesmo id não pode duplicar")
    }
}
```

- [ ] **Step 2: Rodar e ver falhar**

Run:
```bash
xcrun swiftc -parse-as-library -swift-version 5 \
  Knobler/NotchNotification.swift Knobler/NotificationHistory.swift \
  tools/historycheck.swift -o /tmp/historycheck && /tmp/historycheck
```
Expected: FALHA na compilação com
`error: no such file or directory: 'Knobler/NotificationHistory.swift'`.

- [ ] **Step 3: Implementação mínima**

Criar `Knobler/NotificationHistory.swift`:

```swift
//
//  NotificationHistory.swift
//  Knobler
//
//  As notificações das últimas 24 h, em memória. Fica fora do NotchViewModel
//  porque existe um view model por tela: lá dentro o histórico seria copiado
//  por monitor e cada cópia podaria sozinha.
//
//  ponytail: sem disco. NotchNotification carrega NSImage e AXUIElement, que
//  não são serializáveis — persistir exigiria um DTO paralelo. Notificação é
//  efêmera; reiniciou o app, zerou. Virar disco se alguém reclamar de perda.
//

import Foundation

final class NotificationHistory: ObservableObject {
    static let shared = NotificationHistory()

    /// Mais recente primeiro.
    @Published private(set) var items: [NotchNotification] = []

    private let janela: TimeInterval = 24 * 3600

    func record(_ n: NotchNotification) {
        // o enqueue roda uma vez por tela com a mesma notificação
        guard !items.contains(where: { $0.id == n.id }) else { return }
        // progresso: mesmo webhookID substitui, igual ao enqueue faz com o card
        if let wid = n.webhookID { items.removeAll { $0.webhookID == wid } }
        items.insert(n, at: 0)
        prune()
    }

    /// Poda na escrita — a lista só muda quando algo entra, então não há timer.
    /// O pior caso é ver um item de 24 h e 1 min se nada chegou desde então.
    func prune(now: Date = Date()) {
        items.removeAll { now.timeIntervalSince($0.date) > janela }
    }
}
```

- [ ] **Step 4: Rodar e ver passar**

Run: o mesmo comando do Step 2.
Expected: `✅ historycheck ok`.

- [ ] **Step 5: Registrar no `check.sh` e no `snapshot.sh`**

Em `tools/check.sh`, depois da linha do `sharingcheck`:

```bash
swift_check historycheck      Knobler/NotchNotification.swift Knobler/NotificationHistory.swift Knobler/NotchGesture.swift tools/historycheck.swift
```

(`NotchGesture.swift` entra agora porque a Task 3 acrescenta asserções nesse
mesmo binário; até lá o arquivo ainda não existe — **a Task 3 é obrigatória
antes do `check.sh` completo passar**. Se quiser rodar o `check.sh` entre as
duas tasks, deixe a linha sem `NotchGesture.swift` e acrescente na Task 3.)

Em `tools/snapshot.sh`, junto das outras fontes:

```bash
  Knobler/NotificationHistory.swift \
```

- [ ] **Step 6: Rodar a suíte**

Run: `./tools/check.sh`
Expected: `historycheck  ok` na lista, nenhum gate quebrado.

- [ ] **Step 7: Commit**

```bash
git add Knobler/NotificationHistory.swift tools/historycheck.swift tools/check.sh tools/snapshot.sh
git commit -m "feat: store do histórico de notificações (24h, em memória)"
```

---

### Task 3: `NotchGesture.verticalTarget` + self-check

**Files:**
- Create: `Knobler/NotchGesture.swift`
- Modify: `tools/historycheck.swift` (novas asserções)
- Modify: `tools/snapshot.sh` (fonte nova, se ainda não entrou)

**Interfaces:**
- Consumes: nada.
- Produces:
  - `enum ScrollTarget: Equatable { case closed, expanded, history }`
  - `enum NotchGesture { static func verticalTarget(accumY: CGFloat) -> ScrollTarget? }`

- [ ] **Step 1: Escrever o teste que falha**

Em `tools/historycheck.swift`, acrescentar a chamada em `main()` e o método:

```swift
    // dentro de main(), antes do print:
        testGesto()
```

```swift
    /// Puxão longo numa passada só: 24 pt abre o card, 120 pt segue pro
    /// histórico. Como o alvo é função pura do acumulado, recuar os dedos
    /// dentro do mesmo gesto desfaz sem precisar de máquina de estados.
    static func testGesto() {
        assert(NotchGesture.verticalTarget(accumY: 10) == nil, "ruído não age")
        assert(NotchGesture.verticalTarget(accumY: -10) == nil, "ruído não age")
        assert(NotchGesture.verticalTarget(accumY: 30) == .expanded, "30 pt abre o card")
        assert(NotchGesture.verticalTarget(accumY: 130) == .history, "130 pt vai ao histórico")
        // mesmo gesto, dedos recuando: 130 → 30 volta ao card
        assert(NotchGesture.verticalTarget(accumY: 30) == .expanded, "recuo volta ao card")
        assert(NotchGesture.verticalTarget(accumY: -30) == .closed, "pra cima fecha")
        // limiares exatos: o limite é aberto (>), não fechado (>=)
        assert(NotchGesture.verticalTarget(accumY: 24) == nil, "24 pt ainda é ruído")
        assert(NotchGesture.verticalTarget(accumY: 120) == .expanded, "120 pt ainda é card")
    }
```

- [ ] **Step 2: Rodar e ver falhar**

Run:
```bash
xcrun swiftc -parse-as-library -swift-version 5 \
  Knobler/NotchNotification.swift Knobler/NotificationHistory.swift \
  Knobler/NotchGesture.swift tools/historycheck.swift -o /tmp/historycheck && /tmp/historycheck
```
Expected: FALHA com `no such file or directory: 'Knobler/NotchGesture.swift'`.

- [ ] **Step 3: Implementação mínima**

Criar `Knobler/NotchGesture.swift`:

```swift
//
//  NotchGesture.swift
//  Knobler
//
//  A parte pura do gesto de scroll sobre o notch, separada do monitor de
//  eventos pra poder ser testada sem NSEvent.
//

import CoreGraphics

enum ScrollTarget: Equatable { case closed, expanded, history }

enum NotchGesture {
    /// Dedos pra baixo (deltaY positivo, natural scrolling): 24 pt abre o card,
    /// 120 pt — mesma passada, sem soltar — puxa o histórico. Pra cima fecha.
    ///
    /// ponytail: alvo é função do acumulado, não uma máquina de estados. Sai
    /// mais barato que o scrollActed que existia aqui e o recuo dentro do
    /// mesmo gesto passa a funcionar de graça.
    ///
    /// Com o histórico já aberto esta função não é consultada: o monitor
    /// entrega o evento à lista pra ela rolar de verdade.
    static func verticalTarget(accumY: CGFloat) -> ScrollTarget? {
        if accumY > 120 { return .history }
        if accumY > 24 { return .expanded }
        if accumY < -24 { return .closed }
        return nil
    }
}
```

- [ ] **Step 4: Rodar e ver passar**

Run: o comando do Step 2.
Expected: `✅ historycheck ok`.

- [ ] **Step 5: Garantir a fonte no `check.sh` e no `snapshot.sh`**

`tools/check.sh` deve ter `Knobler/NotchGesture.swift` na linha do `historycheck`
(ver Task 2, Step 5). Em `tools/snapshot.sh`, acrescentar:

```bash
  Knobler/NotchGesture.swift \
```

Run: `./tools/check.sh`
Expected: `historycheck  ok`.

- [ ] **Step 6: Commit**

```bash
git add Knobler/NotchGesture.swift tools/historycheck.swift tools/check.sh tools/snapshot.sh
git commit -m "feat: alvo do gesto vertical como função pura do acumulado"
```

---

### Task 4: Gravar no `enqueue` e abrir espaço pro histórico no view model

**Files:**
- Modify: `Knobler/NotchViewModel.swift:245-263` (`enqueue`), `:148-180` (`setHover`), e a lista de `@Published`

**Interfaces:**
- Consumes: `NotificationHistory.shared` (Task 2).
- Produces: `@Published var historyOpen: Bool` no `NotchViewModel`.

- [ ] **Step 1: Adicionar o estado**

Em `Knobler/NotchViewModel.swift`, junto dos outros `@Published` (perto da linha 42):

```swift
    /// Cortina do histórico puxada. Implica `expanded`; fecha junto com ele.
    @Published var historyOpen = false
```

- [ ] **Step 2: Gravar toda notificação que vira card**

No topo de `func enqueue(_ notification: NotchNotification)` (linha 245), como
**primeira** linha do corpo — antes de qualquer `return` do caminho de webhook,
senão a atualização de progresso não entra no histórico:

```swift
        NotificationHistory.shared.record(notification)
```

- [ ] **Step 3: Fechar o histórico junto com o card**

Dentro do `DispatchWorkItem` do ramo `guard inside else` do `setHover`
(linha 153-158), acrescentar após `self.peeking = false`:

```swift
                self.historyOpen = false
```

- [ ] **Step 4: Compilar**

Run: `xcodebuild -project Knobler.xcodeproj -scheme Knobler -configuration Debug build`
Expected: `BUILD SUCCEEDED`.

- [ ] **Step 5: Commit**

```bash
git add Knobler/NotchViewModel.swift
git commit -m "feat: todo card do notch entra no histórico"
```

---

### Task 5: `HistoryListView` + cenário de snapshot

**Files:**
- Create: `Knobler/HistoryListView.swift`
- Modify: `Knobler/NotchView.swift:967` (`openSourceApp` → `static`),
  `:616-630` (`expandedContent`), `:634-650` (alcinha ao lado dos `pageDots`)
- Modify: `tools/snapshot.sh` (fonte nova)
- Modify: `tools/main.swift:103+` (cenário novo)

**Interfaces:**
- Consumes: `NotificationHistory` (Task 2), `NotchViewModel.historyOpen` (Task 4).
- Produces:
  - `struct HistoryListView: View` com `init(history:)`
  - `NotchView.openSourceApp(_:)` promovido de método privado de instância para
    `static func` **internal** — o corpo já só usa `Self.`/`NSWorkspace`, então
    a promoção não muda comportamento e a lista passa a poder reusar o clique.

**Nota de desvio do spec:** a linha da lista mostra o **nome do app como texto**,
não o ícone. O ícone viria de `RemoteAvatarView`/`NSWorkspace.icon(forFile:)`,
que o `CLAUDE.md` lista como não renderizável no `ImageRenderer` offscreen — o
cenário de snapshot da Task 5 viraria o ícone de "proibido". Texto também lê
melhor numa lista densa.

- [ ] **Step 1: Promover `openSourceApp` a estático**

Em `Knobler/NotchView.swift:967`, trocar a assinatura:

```swift
    private func openSourceApp(_ notification: NotchNotification) {
```

por:

```swift
    /// Estático e internal: a linha do histórico reusa o mesmo clique. O corpo
    /// já só usava `Self.` e NSWorkspace, então a promoção não muda nada.
    static func openSourceApp(_ notification: NotchNotification) {
```

As chamadas existentes dentro da própria `NotchView` continuam compilando
(`openSourceApp(x)` resolve pro estático dentro do tipo). Compile antes de
seguir: `xcodebuild -project Knobler.xcodeproj -scheme Knobler -configuration Debug build`.

- [ ] **Step 2: Criar a view**

Criar `Knobler/HistoryListView.swift`:

```swift
//
//  HistoryListView.swift
//  Knobler
//
//  A cortina do histórico: o que virou card nas últimas 24 h.
//

import SwiftUI

struct HistoryListView: View {
    @ObservedObject var history: NotificationHistory

    private static let hora: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()

    var body: some View {
        Group {
            if history.items.isEmpty {
                Text("Nada nas últimas 24 h")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.45))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 6) {
                        ForEach(history.items) { item in
                            linha(item)
                        }
                    }
                }
            }
        }
        .frame(height: 260)
    }

    private func linha(_ item: NotchNotification) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(Self.hora.string(from: item.date))
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.white.opacity(0.4))
                .frame(width: 38, alignment: .leading)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 5) {
                    if let app = item.appName {
                        Text(app)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.5))
                    }
                    Text(item.title)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.9))
                        .lineLimit(1)
                }
                if !item.body.isEmpty {
                    Text(item.body)
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.55))
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
        .onTapGesture { NotchView.openSourceApp(item) }
    }
}
```

⚠ Sem ícone de app na linha, de propósito — ver a nota de desvio no bloco
**Interfaces** desta task.

- [ ] **Step 3: Mostrar a cortina no card expandido**

Em `Knobler/NotchView.swift`, trocar o corpo de `expandedContent` (linha 617) por:

```swift
    private var expandedContent: some View {
        VStack(spacing: 8) {
            Group {
                if vm.historyOpen {
                    HistoryListView(history: NotificationHistory.shared)
                } else if vm.tab == .messages {
                    MessagesView(vm: vm)
                } else {
                    musicContent
                }
            }
            .transition(.blurReplace)
            Spacer(minLength: 0)
            if vm.historyOpen { grabber } else { pageDots }
        }
    }

    /// Alcinha do Dynamic Island: a única dica de que há mais coisa abaixo —
    /// o puxão longo não se anuncia sozinho.
    private var grabber: some View {
        Capsule()
            .fill(.white.opacity(0.25))
            .frame(width: 28, height: 3)
    }
```

E na `musicContent`, no fim do `VStack` (depois da `musicSection`, linha 675),
mostrar a mesma alcinha quando há histórico pra puxar:

```swift
            if !NotificationHistory.shared.items.isEmpty {
                grabber.padding(.top, 2)
            }
```

- [ ] **Step 4: Registrar a fonte no harness**

Em `tools/snapshot.sh`:

```bash
  Knobler/HistoryListView.swift \
```

- [ ] **Step 5: Adicionar os cenários de snapshot**

Em `tools/main.swift`, dentro do array `scenarios` (depois do cenário
`"notification"`, linha 183):

```swift
    Scenario(name: "expanded-history", realNotch: true) { vm, _, _ in
        let h = NotificationHistory.shared
        h.record(NotchNotification(appName: "Slack", title: "Ana Paula",
                                   body: "revisei o PR, pode subir"))
        h.record(NotchNotification(appName: "Knobler", title: "Deploy concluído",
                                   body: "produção · 2m14s"))
        h.record(NotchNotification(appName: "Lembretes", title: "Alongar",
                                   body: "a cada 50 min"))
        vm.expanded = true
        vm.historyOpen = true
    },
    Scenario(name: "expanded-history-empty", realNotch: true) { vm, _, _ in
        vm.expanded = true
        vm.historyOpen = true
    },
```

⚠ `NotificationHistory.shared` é singleton e o harness roda os cenários em
sequência no mesmo processo: coloque `expanded-history-empty` **antes** de
`expanded-history` no array, senão ele herda os itens do vizinho.

- [ ] **Step 6: Renderizar e olhar**

Run: `./tools/snapshot.sh`
Expected: gera `Snapshots/expanded-history.png` e
`Snapshots/expanded-history-empty.png`.

**Abra os dois PNGs e confira**: as três linhas legíveis com hora à esquerda, a
alcinha no rodapé, o texto vazio centralizado no segundo. Se aparecer o ícone de
"proibido" no lugar do conteúdo, alguma subview depende de `NSView` real — a
lista não deveria, mas é o sintoma a procurar.

- [ ] **Step 7: Commit**

```bash
git add Knobler/HistoryListView.swift Knobler/NotchView.swift tools/snapshot.sh tools/main.swift
git commit -m "feat: cortina do histórico no card expandido"
```

---

### Task 6: Ligar o gesto no monitor de scroll

**Files:**
- Modify: `Knobler/KnoblerApp.swift:633-676` (`handleScroll`), e a declaração de
  `scrollAccumX`/`scrollAccumY`/`scrollActed` (perto da linha 105)

**Interfaces:**
- Consumes: `NotchGesture.verticalTarget` (Task 3), `vm.historyOpen` (Task 4).
- Produces: nada consumido por tasks posteriores.

- [ ] **Step 1: Adicionar a flag de gesto iniciado com o histórico aberto**

Junto de `scrollActed` (perto da linha 105) em `Knobler/KnoblerApp.swift`:

```swift
    /// Gesto que COMEÇOU com o histórico aberto rola a lista, não age no notch.
    /// Sem isso, o mesmo puxão que abre o histórico seguiria rolando a lista.
    private var scrollStartedInHistory = false
```

- [ ] **Step 2: Reescrever o miolo do `handleScroll`**

Substituir da linha 639 (`// zona do gesto:`) até o `return nil` final (linha 675) por:

```swift
        // zona do gesto: o notch fechado, o card aberto, ou o card com a cortina
        let expanded = vm.mode == .music
        let zoneWidth: CGFloat = expanded ? 460 : 400
        let zoneHeight: CGFloat = vm.historyOpen ? 420 : (expanded ? 200 : vm.notchSize.height + 10)
        let inZone = abs(mouse.x - screen.frame.midX) <= zoneWidth / 2
            && mouse.y >= screen.frame.maxY - zoneHeight
        guard inZone else { return event }

        // inércia não conta como gesto; ainda assim é engolida na zona
        guard event.momentumPhase.isEmpty else { return nil }

        if event.phase == .began {
            scrollAccumX = 0
            scrollAccumY = 0
            scrollActed = false
            scrollStartedInHistory = vm.historyOpen
        }

        // cortina aberta: o vertical é da lista, pra ela rolar de verdade
        if scrollStartedInHistory, abs(event.scrollingDeltaY) >= abs(event.scrollingDeltaX) {
            return event
        }

        scrollAccumX += event.scrollingDeltaX
        scrollAccumY += event.scrollingDeltaY

        // vertical: alvo é função do acumulado, então recuar dentro do mesmo
        // gesto desfaz. Idempotente — aplicar o mesmo alvo duas vezes não custa.
        if let target = NotchGesture.verticalTarget(accumY: scrollAccumY) {
            switch target {
            case .closed:
                vm.historyOpen = false
                vm.setExpandedDirect(false)
            case .expanded:
                vm.historyOpen = false
                vm.setExpandedDirect(true)
            case .history:
                vm.setExpandedDirect(true)
                vm.historyOpen = true
            }
        } else if !scrollActed, abs(scrollAccumX) > 50 {
            scrollActed = true
            if expanded {
                // card aberto: horizontal navega entre as telas (Música/Mensagens)
                withAnimation(.easeOut(duration: 0.22)) {
                    vm.tab = scrollAccumX < 0 ? .messages : .music
                }
            } else if media.state != nil {
                if scrollAccumX < 0 { media.nextTrack() } else { media.previousTrack() }
            }
        }
        return nil // engole o scroll na zona — a janela de trás não rola junto
```

- [ ] **Step 3: Compilar**

Run: `xcodebuild -project Knobler.xcodeproj -scheme Knobler -configuration Debug build`
Expected: `BUILD SUCCEEDED`.

- [ ] **Step 4: Verificar ao vivo**

Run:
```bash
pkill -x Knobler; open build/Debug/Knobler.app 2>/dev/null || \
  xcodebuild -project Knobler.xcodeproj -scheme Knobler -configuration Debug \
    -showBuildSettings | grep -m1 BUILT_PRODUCTS_DIR
```

Depois, com o cursor sobre o notch, confira **cada** item:
1. Puxão curto pra baixo (~2 linhas) → abre o card de música, como antes.
2. Puxão longo pra baixo numa passada → chega no histórico.
3. Com o histórico aberto, rolar pra baixo → **a lista rola**, o notch não muda.
4. Tirar o mouse do notch → fecha tudo; voltar → abre no card de música, não no histórico.
5. Swipe horizontal com o card aberto → ainda troca Música/Mensagens.
6. Swipe horizontal com o notch fechado e música tocando → ainda pula faixa.

Se o item 3 falhar (a lista não rola), o culpado é o `scrollStartedInHistory`
não ter sido setado — o `event.phase == .began` não chega em todo trackpad;
nesse caso trocar a condição por `if vm.historyOpen, event.phase == .began { … }`.

- [ ] **Step 5: Commit**

```bash
git add Knobler/KnoblerApp.swift
git commit -m "feat: puxão longo pra baixo abre o histórico"
```

---

### Task 7: `QuickNote` + interruptor no menu da barra

**Files:**
- Create: `Knobler/QuickNote.swift`
- Modify: `Knobler/KnoblerApp.swift:924-928` (menu), e um `@objc` novo perto do `pickColor` (linha 944)
- Modify: `tools/snapshot.sh` (fonte nova)

**Interfaces:**
- Consumes: nada.
- Produces:
  - `final class QuickNote: ObservableObject`
  - `static let shared: QuickNote`
  - `@Published var active: Bool` (desligar limpa `text`)
  - `@Published var text: String`
  - `@Published var editing: Bool`

- [ ] **Step 1: Criar o store**

Criar `Knobler/QuickNote.swift`:

```swift
//
//  QuickNote.swift
//  Knobler
//
//  Nota rápida: um campo de texto que vive no card aberto enquanto o
//  interruptor do menu estiver ligado. Desligar apaga.
//
//  ponytail: sem persistência e sem timer de expiração. O interruptor é a
//  regra de fim de vida inteira — nota que morre em minutos não precisa de
//  arquivo nem de Ajuste de intervalo.
//

import Foundation

final class QuickNote: ObservableObject {
    static let shared = QuickNote()

    @Published var active = false {
        didSet { if !active { text = ""; editing = false } }
    }
    @Published var text = ""
    /// Campo com foco de teclado — segura o card aberto contra o hover-out.
    @Published var editing = false
}
```

- [ ] **Step 2: Adicionar o item de menu**

Em `Knobler/KnoblerApp.swift`, dentro de `menuNeedsUpdate`, logo depois do
`menu.addItem(.separator())` da linha 924 e antes do item do conta-gotas:

```swift
        let nota = menu.addItem(
            withTitle: "✎ Nota rápida", action: #selector(toggleQuickNote), keyEquivalent: "")
        nota.target = self
        nota.state = QuickNote.shared.active ? .on : .off
```

E o handler, junto do `pickColor` (perto da linha 944):

```swift
    /// Interruptor da nota. Ligar abre o card na hora — esperar o hover
    /// depois de escolher no menu seria um passo a mais sem motivo.
    @objc private func toggleQuickNote() {
        let note = QuickNote.shared
        note.active.toggle()
        if note.active {
            notches.values.forEach { $0.viewModel.setExpandedDirect(true) }
        }
    }
```

- [ ] **Step 3: Registrar a fonte no harness**

Em `tools/snapshot.sh`:

```bash
  Knobler/QuickNote.swift \
```

- [ ] **Step 4: Compilar e verificar o menu**

Run:
```bash
xcodegen generate
xcodebuild -project Knobler.xcodeproj -scheme Knobler -configuration Debug build
```
Expected: `BUILD SUCCEEDED`.

Com o app rodando, abrir o menu do ◐: "✎ Nota rápida" aparece sem marca; clicar
marca com ✓ e o notch abre. Clicar de novo desmarca. (O card ainda não mostra
nada — é a Task 8.)

- [ ] **Step 5: Commit**

```bash
git add Knobler/QuickNote.swift Knobler/KnoblerApp.swift tools/snapshot.sh Knobler.xcodeproj
git commit -m "feat: interruptor da nota rápida no menu da barra"
```

---

### Task 8: A nota no card + foco de teclado + guarda de hover

**Files:**
- Modify: `Knobler/NotchView.swift:33-38` (`keyboardAllowed`), `:195-202` (`onChange`), `:617` (`expandedContent`)
- Modify: `Knobler/NotchViewModel.swift:152-161` (`setHover`)

**Interfaces:**
- Consumes: `QuickNote.shared` (Task 7), `expandedContent` (Task 5).
- Produces: nada.

- [ ] **Step 1: Mostrar a nota no card**

Em `Knobler/NotchView.swift`, declarar o estado junto dos outros `@State`
(perto da linha 25):

```swift
    @ObservedObject private var note = QuickNote.shared
    @FocusState private var noteFocused: Bool
```

E ajustar o `Group` do `expandedContent` — a nota tem prioridade sobre tudo,
porque foi pedida explicitamente pelo menu:

```swift
            Group {
                if note.active {
                    noteSection
                } else if vm.historyOpen {
                    HistoryListView(history: NotificationHistory.shared)
                } else if vm.tab == .messages {
                    MessagesView(vm: vm)
                } else {
                    musicContent
                }
            }
```

E a seção, junto das outras `// MARK: -`:

```swift
    // MARK: - Nota rápida

    /// ponytail: texto simples, não rich text. Negrito e itálico exigiriam
    /// NSAttributedString e uma barra de formatação pra uma nota que vive
    /// minutos.
    private var noteSection: some View {
        TextEditor(text: $note.text)
            .font(.system(size: 13))
            .foregroundStyle(.white.opacity(0.92))
            .scrollContentBackground(.hidden)
            .background(.clear)
            .focused($noteFocused)
            .frame(height: 120)
            .padding(.horizontal, 4)
            .onAppear { noteFocused = true }
            .onChange(of: noteFocused) { _, focused in note.editing = focused }
    }
```

- [ ] **Step 2: Deixar o notch aceitar teclado**

Ainda em `NotchView.swift`, acrescentar a condição em `keyboardAllowed` (linha 33):

```swift
    private var keyboardAllowed: Bool {
        askStore.state.active != nil
            || agentRequestStore.state.active != nil
            || vm.incoming?.allowReply == true
            || (vm.tab == .messages && vm.expanded)
            || (note.active && vm.expanded)
    }
```

E o gatilho, junto dos outros `onChange` (linha 202):

```swift
        .onChange(of: note.active) { _, _ in notifyKeyboardEligibility() }
```

- [ ] **Step 3: Impedir que o hover-out feche no meio da digitação**

Em `Knobler/NotchViewModel.swift`, dentro do `DispatchWorkItem` do ramo
`guard inside else` do `setHover` (linha 153), como primeira linha do bloco:

```swift
                // digitar na nota não pode ser interrompido por um mouse que
                // saiu da área — Esc solta o foco e aí o hover-out volta a valer
                guard !QuickNote.shared.editing else { return }
```

- [ ] **Step 4: Compilar**

Run: `xcodebuild -project Knobler.xcodeproj -scheme Knobler -configuration Debug build`
Expected: `BUILD SUCCEEDED`.

- [ ] **Step 5: Verificar ao vivo**

Com o app rodando, confira **cada** item:
1. Menu → "✎ Nota rápida" → o card abre com o campo já focado; digitar funciona.
2. Digitando, mover o mouse pra longe do notch → **continua aberto**.
3. Esc → o campo perde o foco; mover o mouse pra longe → agora fecha.
4. Voltar o mouse ao notch → reabre com o texto ainda lá.
5. Digitar na nota **não** rouba o foco do app da frente (o cursor do terminal
   atrás continua piscando).
6. Menu → desmarcar "Nota rápida" → o texto some; abrir de novo vem vazio.
7. Reiniciar o app com a nota ligada → volta desligada e vazia.

- [ ] **Step 6: Screenshot manual pra doc**

`TextEditor` depende de `NSView` real e vira o ícone de "proibido" no
`ImageRenderer` offscreen — igual ao `TextField` do `AskCardView`. Por isso a
nota **não** entra em `tools/snapshot.sh`.

Com a nota aberta e algum texto, capturar a janela do notch e salvar em
`docs/images/nota-rapida.png`.

- [ ] **Step 7: Commit**

```bash
git add Knobler/NotchView.swift Knobler/NotchViewModel.swift docs/images/nota-rapida.png
git commit -m "feat: nota rápida no card, com foco que segura o hover"
```

---

### Task 9: Documentação

**Files:**
- Create: `docs/nota-rapida.md`
- Modify: `docs/notifications.md` (seção do histórico)
- Modify: `docs/index.md` (entrada nova)
- Modify: `docs/IDEIAS.md` (remover as duas ideias entregues)
- Modify: `CHANGELOG.md` (`## [Unreleased]`)

- [ ] **Step 1: Documentar o histórico**

Em `docs/notifications.md`, acrescentar uma seção "Histórico (24 h)" cobrindo:
o puxão longo pra baixo numa passada só; a alcinha no rodapé do card como dica;
que o fechamento é tirar o mouse, não gesto; que entra tudo que virou card
(banner do sistema, webhook, lembrete, atividade da API); que **não** sobrevive
ao restart do app e por quê (`NSImage`/`AXUIElement` não serializáveis).
Incluir `![...](images/expanded-history.png)` se o PNG do snapshot for copiado
pra `docs/images/`.

- [ ] **Step 2: Documentar a nota rápida**

Criar `docs/nota-rapida.md` cobrindo: ligar pelo menu do ◐; o card abre já
focado; digitar segura o card aberto mesmo com o mouse fora; Esc solta o foco;
o texto volta a cada hover enquanto o interruptor estiver ligado; desligar
apaga; não sobrevive ao restart; texto simples, sem formatação. Usar
`![...](images/nota-rapida.png)`.

- [ ] **Step 3: Registrar no índice**

Em `docs/index.md`, adicionar a linha de `nota-rapida.md` seguindo o formato das
entradas vizinhas.

- [ ] **Step 4: Podar o backlog**

Em `docs/IDEIAS.md`, remover o item **"Nota rápida no notch"** (seção
"Notch & UI") e o item **"Persistência de notificações"** (seção "Lembretes &
Notificações"), que acabaram de ser entregues.

- [ ] **Step 5: CHANGELOG**

Em `CHANGELOG.md`, sob `## [Unreleased]` → `### Adicionado`:

```markdown
- Histórico das notificações das últimas 24 h no notch: puxe o card pra baixo
  numa passada só pra abrir a cortina. Não sobrevive ao restart do app.
- Nota rápida: um interruptor no menu da barra abre um campo de texto no card.
  Digitar segura o card aberto; desligar apaga a nota.
```

- [ ] **Step 6: Rodar a suíte inteira**

Run: `./tools/check.sh && ./tools/snapshot.sh`
Expected: todos os checks `ok` (15 agora, com o `historycheck`), snapshots
regravados sem erro.

- [ ] **Step 7: Commit**

```bash
git add docs CHANGELOG.md
git commit -m "docs: histórico de notificações e nota rápida"
```

---

## Ordem e dependências

```
Task 1 (extrair struct)
  └─ Task 2 (store + check) ──┐
  └─ Task 3 (gesto + check) ──┤
                              ├─ Task 4 (enqueue + estado)
                              │    └─ Task 5 (lista + snapshot)
                              │         └─ Task 6 (monitor de scroll)
                              └─ Task 7 (QuickNote + menu)
                                   └─ Task 8 (nota no card)
                                        └─ Task 9 (docs)
```

Tasks 2 e 3 são independentes entre si. As tasks 7 e 8 (nota) só dependem da 1
indiretamente — podem ir em paralelo com a trilha do histórico.
