# Card de pergunta com texto integral — plano de implementação

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** o card do `POST /ask` mostra a pergunta inteira sempre e a descrição
inteira da opção sob o cursor, com o card crescendo em altura para caber.

**Architecture:** o `AskCardView` perde os `lineLimit` que truncam; a altura do
card `.question` deixa de ser estimada por fórmula e passa a ser a altura que o
próprio card reporta via `PreferenceKey`; a janela do notch ganha a altura da
tela para que o card tenha para onde crescer.

**Tech Stack:** Swift 5, SwiftUI, AppKit. Sem dependência nova.

## Global Constraints

- Deployment target **macOS 14.2**. `onGeometryChange` é macOS 15 — **não usar**.
  A medição é `GeometryReader` em `.background` alimentando um `PreferenceKey`.
- Comentários e strings de UI em **pt-BR**.
- `Knobler.xcodeproj` é artefato do XcodeGen — nunca editar à mão. Nenhuma tarefa
  aqui adiciona ou remove arquivo, então `xcodegen generate` não é necessário.
- Simplificação deliberada com teto conhecido leva comentário `// ponytail:`.
- Build local: `xcodebuild -project Knobler.xcodeproj -scheme Knobler -configuration Debug build`.
- Nenhum gate novo em `tools/check.sh`. `./tools/check.sh` precisa continuar verde.

## Arquivos

| Arquivo | Responsabilidade nesta mudança |
|---|---|
| `Knobler/Ask.swift` | remover os truncamentos e publicar a altura medida |
| `Knobler/NotchView.swift` | consumir a altura medida em `currentSize`, remover o teto de 500 |
| `Knobler/KnoblerApp.swift` | janela do notch com a altura utilizável da tela |
| `tools/main.swift` | `frameHeight` dos cenários Ask do harness |

Nenhum arquivo novo. Nenhum arquivo removido.

---

### Task 1: Remover os truncamentos do card

**Files:**
- Modify: `Knobler/Ask.swift:70` (header) e `Knobler/Ask.swift:133` (descrição)

**Interfaces:**
- Consumes: nada.
- Produces: nada de API. O card passa a renderizar mais alto que antes, o que a
  Task 3 vai medir.

- [ ] **Step 1: tirar o `lineLimit` da pergunta**

Em `header(question:)`, o `Text(question.question)` está assim:

```swift
            Text(question.question)
                .font(.subheadline.weight(.semibold))
                .lineLimit(2)
```

Fica assim (a pergunta aparece sempre inteira, sem depender de hover):

```swift
            Text(question.question)
                .font(.subheadline.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)
```

O `fixedSize` vertical impede que o `HStack` do header comprima o texto de volta
para uma linha quando o chip e o `source` disputam largura.

- [ ] **Step 2: a descrição da opção sob o cursor não trunca**

Em `optionRow(_:question:)`, a descrição está assim:

```swift
                    if !option.description.isEmpty {
                        Text(option.description)
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.6))
                            .lineLimit(2)
                    }
```

Fica assim:

```swift
                    if !option.description.isEmpty {
                        Text(option.description)
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.6))
                            // a opção sob o cursor mostra a descrição inteira;
                            // as outras seguem em 2 linhas pra lista não inchar
                            .lineLimit(hovered == option.label ? nil : 2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
```

- [ ] **Step 3: compilar**

```bash
xcodebuild -project Knobler.xcodeproj -scheme Knobler -configuration Debug build
```

Esperado: `BUILD SUCCEEDED`.

- [ ] **Step 4: commit**

```bash
git add Knobler/Ask.swift
git commit -m "feat(ask): pergunta e descrição sob o cursor sem truncar"
```

---

### Task 2: Janela do notch com a altura da tela

**Files:**
- Modify: `Knobler/KnoblerApp.swift:1197-1205`

**Interfaces:**
- Consumes: nada.
- Produces: espaço vertical para o card crescer. Sem isso, a Task 3 mede uma
  altura que a janela não consegue exibir.

- [ ] **Step 1: trocar a constante pela altura utilizável da tela**

O trecho atual:

```swift
            // altura comporta o card com espelho; área transparente não intercepta cliques
            let size = NSSize(width: 700, height: 520)
            let frame = NSRect(
                x: screen.frame.midX - size.width / 2,
                y: screen.frame.maxY - size.height,
                width: size.width,
                height: size.height
            )
            notch.window.setFrame(frame, display: true)
```

Fica:

```swift
            // a janela vai até embaixo da tela pro card poder crescer o quanto
            // precisar; a área transparente não intercepta cliques
            let size = NSSize(width: 700, height: screen.visibleFrame.height)
            let frame = NSRect(
                x: screen.frame.midX - size.width / 2,
                y: screen.frame.maxY - size.height,
                width: size.width,
                height: size.height
            )
            notch.window.setFrame(frame, display: true)
```

- [ ] **Step 2: compilar**

```bash
xcodebuild -project Knobler.xcodeproj -scheme Knobler -configuration Debug build
```

Esperado: `BUILD SUCCEEDED`.

- [ ] **Step 3: provar que a janela transparente não roubou clique**

Rode o app da build Debug e confirme, na área abaixo do notch fechado e fora do
card, que um clique chega na janela que está por baixo (por exemplo, clicar num
ícone do Desktop ou numa janela do Finder posicionada ali).

Isto é o único risco real da tarefa: se o clique for engolido, a janela está
interceptando e a mudança precisa voltar atrás — reporte antes de seguir.

- [ ] **Step 4: commit**

```bash
git add Knobler/KnoblerApp.swift
git commit -m "feat(notch): janela ocupa a altura utilizável da tela"
```

---

### Task 3: O card se mede e a fórmula vira valor de partida

**Files:**
- Modify: `Knobler/Ask.swift` (novo `PreferenceKey` + `.background` de medição)
- Modify: `Knobler/NotchView.swift:400-418` (`currentSize`, caso `.question`) e
  `Knobler/NotchView.swift:675-694` (`questionCard`)

**Interfaces:**
- Consumes: o card mais alto da Task 1, a janela maior da Task 2.
- Produces:
  - `struct AlturaDoAskKey: PreferenceKey` em `Knobler/Ask.swift`, com
    `static var defaultValue: CGFloat = 0` e
    `static func reduce(value: inout CGFloat, nextValue: () -> CGFloat)`.
  - `@State private var askHeight: CGFloat = 0` em `NotchView`.

- [ ] **Step 1: declarar o `PreferenceKey` e publicar a altura**

No fim de `Knobler/Ask.swift`, fora da `AskCardView`:

```swift
// MARK: - Altura medida

/// O card do Ask não tem altura previsível: a pergunta e a descrição sob o
/// cursor variam de linhas. Ele mede a si mesmo e o `NotchView` usa esse
/// valor no lugar da estimativa por número de opções.
struct AlturaDoAskKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
```

E no `body` da `AskCardView`, logo após `.foregroundStyle(.white)`:

```swift
        .background(
            GeometryReader { proxy in
                Color.clear.preference(key: AlturaDoAskKey.self, value: proxy.size.height)
            }
        )
```

O `.background` mede sem influir no layout, e `GeometryReader` é o caminho
disponível no macOS 14.2 — `onGeometryChange` só existe a partir do 15.

- [ ] **Step 2: `NotchView` guarda a altura**

Junto dos outros `@State` de `NotchView`, adicione:

```swift
    /// Altura que o card do Ask reportou no último layout. 0 = ainda não mediu.
    @State private var askHeight: CGFloat = 0
```

E em `questionCard`, o ramo do `AskCardView` passa a escutar a preferência:

```swift
        if askStore.state.active != nil {
            AskCardView(vm: vm, askStore: askStore)
                .frame(width: currentSize.width - 40)
                .padding(.top, topInset + 6)
                .padding(.bottom, 12)
                .onPreferenceChange(AlturaDoAskKey.self) { askHeight = $0 }
        } else if let request = agentRequestStore.state.active {
```

O `.onPreferenceChange` fica **depois** dos `padding` porque a preferência sobe
inalterada por eles; o que importa é que o valor medido é só o conteúdo do card,
sem os paddings — a soma acontece no passo seguinte.

- [ ] **Step 3: `currentSize` usa a medida quando existir**

No `case .question` de `currentSize`, o trecho do Ask está assim:

```swift
            let question = ask.questions[min(askStore.state.page, ask.questions.count - 1)]
            let hasPreview = question.options.contains { $0.preview != nil }
            // título+chip (46) + opções (48 cada) + rodapé com campo de texto (44)
            var height = topInset + 46 + CGFloat(question.options.count) * 48 + 44
            if question.multiSelect { height += 34 }  // botão Confirmar
            if hasPreview { height = max(height, topInset + 200) }
            return CGSize(width: hasPreview ? 540 : 460, height: min(height, 500))
```

Fica assim:

```swift
            let question = ask.questions[min(askStore.state.page, ask.questions.count - 1)]
            let hasPreview = question.options.contains { $0.preview != nil }
            // Estimativa só do primeiro frame, antes do card se medir:
            // título+chip (46) + opções (48 cada) + rodapé com campo de texto (44)
            var height = topInset + 46 + CGFloat(question.options.count) * 48 + 44
            if question.multiSelect { height += 34 }  // botão Confirmar
            if hasPreview { height = max(height, topInset + 200) }
            // A altura real vem do próprio card (AlturaDoAskKey); os 18 são os
            // paddings que o `questionCard` acrescenta em volta dele.
            if askHeight > 0 { height = topInset + 6 + askHeight + 12 }
            // ponytail: o card para de crescer na tela e o excedente é cortado
            // pela máscara. Sem rolagem — só ocorre com pergunta e opções
            // descomunais ao mesmo tempo; se aparecer de verdade, entra scroll.
            let teto = NSScreen.main?.visibleFrame.height ?? 900
            return CGSize(width: hasPreview ? 540 : 460, height: min(height, teto))
```

- [ ] **Step 4: zerar a medida quando o card sai**

Sem isso, a altura do card anterior sobra e o próximo Ask abre com o tamanho
errado no primeiro frame. Em `questionCard`, no mesmo ramo do `AskCardView`,
acrescente depois do `.onPreferenceChange`:

```swift
                .onDisappear { askHeight = 0 }
```

- [ ] **Step 5: compilar**

```bash
xcodebuild -project Knobler.xcodeproj -scheme Knobler -configuration Debug build
```

Esperado: `BUILD SUCCEEDED`.

- [ ] **Step 6: provar no app rodando**

Com a build Debug rodando, mande uma pergunta com texto longo:

```bash
curl -s -X POST http://127.0.0.1:4477/ask -H 'Content-Type: application/json' -d '{
  "id":"plano-1","source":"plano",
  "questions":[{"question":"A spec chama de ticket 006 o que na verdade é Embedded Signup, e o 006 é o modelo de dados — fecho os três de uma vez, corrijo só o número, ou deixo 008 aberto?","header":"Tickets 006/7/8","multiSelect":false,
  "options":[
    {"label":"Fecha os três, corrige o número","description":"A spec passa a dizer que responde 006, 007 e 008; os três tickets ganham linha de fechamento no mesmo commit e o wayfinder para de apontar decisão pendente onde já existe decisão tomada."},
    {"label":"Só corrige o número","description":"Troca a citação errada e deixa os tickets abertos. Menos escrita agora, mas o wayfinder continua dizendo que 006/007/008 estão por decidir quando já estão."}
  ]}]}'
```

Confirme, olhando o notch: a pergunta aparece nas três linhas que ela ocupa, sem
`…`; passando o mouse sobre cada opção, a descrição daquela opção abre inteira e
o card cresce; tirando o mouse, ele recolhe. Nenhum texto sai pela borda.

Feche com `curl -s -X POST http://127.0.0.1:4477/ask/plano-1/cancel`.

- [ ] **Step 7: commit**

```bash
git add Knobler/Ask.swift Knobler/NotchView.swift
git commit -m "feat(ask): altura do card vem da medida real, não da estimativa"
```

---

### Task 4: Harness visual e documentação

**Files:**
- Modify: `tools/main.swift:316` e `tools/main.swift:331` (cenários Ask)
- Modify: `CHANGELOG.md` (seção `## [Unreleased]`)

**Interfaces:**
- Consumes: o comportamento das Tasks 1–3.
- Produces: nada consumido por outra tarefa.

- [ ] **Step 1: subir o `frameHeight` dos cenários Ask**

O `frameHeight` default é 240 (`tools/main.swift:64`) e já cortava o card antes
desta mudança. Nos dois cenários, acrescente o parâmetro:

```swift
    // frameHeight maior que o default 240: a pergunta agora ocupa as linhas que
    // precisar e o card mede a própria altura — com 240 o PNG cortava a lista.
    Scenario(name: "ask-simple", realNotch: true, frameHeight: 420) { _, _, askStore in
```

```swift
    Scenario(name: "ask-multiselect", realNotch: true, frameHeight: 420) { _, _, askStore in
```

- [ ] **Step 2: regenerar os snapshots**

```bash
./tools/snapshot.sh
```

Esperado: termina sem erro e regrava os PNGs.

- [ ] **Step 3: olhar os PNGs**

Leia `Snapshots/ask-simple.png` e `Snapshots/ask-multiselect.png`. A lista de
opções tem que aparecer inteira. O rodapé continua cortado — o `TextField` não
renderiza no `ImageRenderer` offscreen, é comportamento conhecido e documentado
em `CLAUDE.md`. O harness não simula cursor, então nenhum PNG mostra a descrição
expandida; essa parte foi provada no Step 6 da Task 3.

- [ ] **Step 4: rodar todos os gates**

```bash
./tools/check.sh
```

Esperado: todos os checks passam, incluindo `askcheck` (que cobre só o reducer e
não deveria ser afetado por nenhuma mudança deste plano).

- [ ] **Step 5: CHANGELOG**

Em `## [Unreleased]`, sob `### Adicionado` (crie a subseção se não existir):

```markdown
- O card de pergunta mostra a pergunta inteira e abre a descrição completa da
  opção sob o cursor; o card cresce em altura para caber.
```

- [ ] **Step 6: commit**

```bash
git add tools/main.swift CHANGELOG.md
git commit -m "chore(ask): harness comporta o card mais alto; CHANGELOG"
```

---

## Nota sobre a novidade da versão

Se esta mudança for publicada com `./tools/release.sh minor`, o release exige
`Knobler/Novidades/<versão>.html` e a versão em `NovidadesCatalogo.versoes` —
`release.sh` aborta sem isso. Como o tamanho do bump e o momento do release são
decisão de quem publica, este plano não escreve a página; ela entra no momento
do release. Publicando como `patch`, nada disso é exigido.
