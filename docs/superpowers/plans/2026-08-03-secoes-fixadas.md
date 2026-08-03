# Seções fixadas no card aberto — plano de implementação

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Permitir que o usuário marque seções do card aberto como "fixadas", fazendo-as aparecer mesmo sem conteúdo.

**Architecture:** A regra mora na parte pura (`NotchSectionOrder.ordenar` ganha o parâmetro `fixadas`, que relaxa o filtro `hasContent`). O `AppSettings` guarda o conjunto; o `NotchViewModel` passa adiante e escolhe o foco inicial na primeira seção **com conteúdo**; a `NotchView` ganha estado vazio nas seções que hoje desenham nada; os Ajustes ganham um pin por linha na lista de ordenação que já existe.

**Tech Stack:** Swift 5, SwiftUI + AppKit, macOS 14.2 target. Sem XCTest — os checks são os harnesses `tools/*check*.swift` listados em `tools/check.sh`.

## Global Constraints

- Comentários e strings de UI em **pt-BR**.
- Deployment target macOS 14.2 — nada de API mais nova sem `if #available`.
- Nunca editar `Knobler.xcodeproj` à mão; ele é gerado por `xcodegen`. Nenhum arquivo novo é criado neste plano, então `xcodegen generate` **não** é necessário.
- `rawValue` de `NotchSection` é contrato salvo em disco — não renomear casos.
- Padrão do ajuste novo é **conjunto vazio**: sem migração, comportamento idêntico ao de hoje para quem não configurar nada.
- Escrever as mudanças em `## [Unreleased]` do `CHANGELOG.md`. Não editar `MARKETING_VERSION` nem criar tag.
- Gate completo: `./tools/check.sh`.

---

### Task 1: `fixadas` na parte pura da ordenação

**Files:**
- Modify: `Knobler/NotchSectionOrder.swift` (`ordenar`, ~linha 80; e uma função nova `sanearFixadas`)
- Test: `tools/sectionordercheck.swift`

**Interfaces:**
- Produces:
  - `NotchSectionOrder.ordenar(base:estados:fixadas:agora:travadaNaNota:) -> [NotchSection]` — o parâmetro `fixadas: Set<NotchSection>` entra **depois** de `estados`.
  - `NotchSectionOrder.sanearFixadas(salvas: [String]) -> Set<NotchSection>`

- [ ] **Step 1: Escrever os testes que falham**

Em `tools/sectionordercheck.swift`, adicionar as três funções abaixo e registrar as chamadas em `main()`, logo depois de `testSemConteudoSai()`:

```swift
    /// Seção fixada aparece mesmo vazia, na posição da ordem-base.
    static func testFixadaVaziaApareceNaPosicaoDaBase() {
        let out = NotchSectionOrder.ordenar(
            base: [.musica, .nota, .shelf],
            estados: [viva(.musica, haSegundos: nil),
                      NotchSectionState(section: .nota, hasContent: false, lastEvent: nil),
                      viva(.shelf, haSegundos: nil)],
            fixadas: [.nota],
            agora: agora, travadaNaNota: false)
        assert(out == [.musica, .nota, .shelf], "fixada vazia fora da posição-base: \(out)")
    }

    /// Não fixada e sem conteúdo continua fora — o padrão não muda.
    static func testNaoFixadaVaziaContinuaFora() {
        let out = NotchSectionOrder.ordenar(
            base: [.musica, .nota, .shelf],
            estados: [viva(.musica, haSegundos: nil),
                      NotchSectionState(section: .nota, hasContent: false, lastEvent: nil),
                      viva(.shelf, haSegundos: nil)],
            fixadas: [],
            agora: agora, travadaNaNota: false)
        assert(out == [.musica, .shelf], "vazia não fixada entrou: \(out)")
    }

    /// `rawValue` desconhecido (versão futura, disco corrompido) é descartado;
    /// duplicata some no Set.
    static func testSanearFixadasDescartaDesconhecida() {
        let out = NotchSectionOrder.sanearFixadas(salvas: ["nota", "chapeu", "nota"])
        assert(out == [.nota], "sanearFixadas não filtrou: \(out)")
    }
```

Em `main()`:

```swift
        testSemConteudoSai()
        testFixadaVaziaApareceNaPosicaoDaBase()
        testNaoFixadaVaziaContinuaFora()
        testSanearFixadasDescartaDesconhecida()
```

Os testes já existentes chamam `ordenar` sem `fixadas`. Adicionar `fixadas: []` em **todas** as chamadas existentes no arquivo (usar busca por `NotchSectionOrder.ordenar(`), sempre entre `estados:` e `agora:`.

- [ ] **Step 2: Rodar e ver falhar**

```bash
xcrun swiftc -parse-as-library -swift-version 5 \
  Knobler/NotchSectionOrder.swift tools/sectionordercheck.swift \
  -o /tmp/sectionordercheck && /tmp/sectionordercheck
```

Esperado: FALHA de compilação — `extra argument 'fixadas' in call` e `type 'NotchSectionOrder' has no member 'sanearFixadas'`.

- [ ] **Step 3: Implementar**

Em `Knobler/NotchSectionOrder.swift`, na assinatura de `ordenar`, inserir o parâmetro e trocar o filtro de visibilidade:

```swift
    ///   - fixadas: seções que o usuário quer ver mesmo vazias.
    static func ordenar(base: [NotchSection],
                        estados: [NotchSectionState],
                        fixadas: Set<NotchSection> = [],
                        agora: Date,
                        travadaNaNota: Bool) -> [NotchSection] {
```

e, algumas linhas abaixo:

```swift
        // fixada aparece vazia, na posição da ordem-base: sem `lastEvent`
        // recente ela não é promovida, então cai onde o usuário a deixou.
        let visiveis = ordemBase.filter {
            porSecao[$0]?.hasContent == true || fixadas.contains($0)
        }
```

No fim do enum, ao lado de `sanear`:

```swift
    /// Lê as fixadas do UserDefaults sem confiar nelas. Diferente de `sanear`,
    /// não completa nada: conjunto vazio é o estado de fábrica.
    static func sanearFixadas(salvas: [String]) -> Set<NotchSection> {
        Set(salvas.compactMap(NotchSection.init(rawValue:)))
    }
```

- [ ] **Step 4: Rodar e ver passar**

```bash
xcrun swiftc -parse-as-library -swift-version 5 \
  Knobler/NotchSectionOrder.swift tools/sectionordercheck.swift \
  -o /tmp/sectionordercheck && /tmp/sectionordercheck
```

Esperado: `✅ sectionordercheck ok`

- [ ] **Step 5: Commit**

```bash
git add Knobler/NotchSectionOrder.swift tools/sectionordercheck.swift
git commit -m "feat: ordenação aceita seções fixadas"
```

---

### Task 2: ajuste persistido e foco inicial

**Files:**
- Modify: `Knobler/AppSettings.swift` (propriedade nova perto de `notchSectionOrder`, ~linha 118; leitura no `init`, ~linha 245)
- Modify: `Knobler/NotchViewModel.swift` (`recalcularSecoes`, ~linha 194)
- Test: `tools/eventoscheck.swift`

**Interfaces:**
- Consumes: `NotchSectionOrder.ordenar(base:estados:fixadas:agora:travadaNaNota:)`, `NotchSectionOrder.sanearFixadas(salvas:)` (Task 1)
- Produces: `AppSettings.shared.notchSectionsFixadas: Set<NotchSection>` (chave UserDefaults `notchSectionsFixadas`, array de `rawValue`)

- [ ] **Step 1: Escrever os testes que falham**

Em `tools/eventoscheck.swift`, adicionar as duas funções abaixo e registrar as chamadas em `main()` logo depois de `testFocoInicialEhAPrimeira()`:

```swift
    /// Fixada vazia entra na ordem, mas não rouba o foco: o card abre no
    /// primeiro conteúdo real.
    static func testFocoInicialPulaFixadaVazia() {
        UserDefaults.standard.set(["nota", "musica"], forKey: "notchSectionOrder")
        UserDefaults.standard.set(["nota"], forKey: "notchSectionsFixadas")
        AppSettings.shared.notchSectionOrder = NotchSectionOrder.sanear(salva: ["nota", "musica"])
        AppSettings.shared.notchSectionsFixadas = [.nota]
        let vm = NotchViewModel()
        vm.recalcularSecoes([
            NotchSectionState(section: .nota, hasContent: false, lastEvent: nil),
            NotchSectionState(section: .musica, hasContent: true, lastEvent: nil),
        ], travadaNaNota: false)
        assert(vm.secoes == [.nota, .musica], "ordem errada: \(vm.secoes)")
        assert(vm.focus == .musica, "foco caiu na fixada vazia: \(String(describing: vm.focus))")
        // restaura o estado de fábrica pros testes seguintes
        AppSettings.shared.notchSectionsFixadas = []
        AppSettings.shared.notchSectionOrder = NotchSectionOrder.padrao
    }

    /// Só fixadas vazias: o card ainda precisa focar alguma coisa.
    static func testFocoCaiNaPrimeiraQuandoNadaTemConteudo() {
        AppSettings.shared.notchSectionsFixadas = [.nota, .musica]
        let vm = NotchViewModel()
        vm.recalcularSecoes([
            NotchSectionState(section: .musica, hasContent: false, lastEvent: nil),
            NotchSectionState(section: .nota, hasContent: false, lastEvent: nil),
        ], travadaNaNota: false)
        assert(vm.focus == vm.secoes.first, "sem conteúdo o foco não é o primeiro")
        AppSettings.shared.notchSectionsFixadas = []
    }
```

Em `main()`:

```swift
        testFocoInicialEhAPrimeira()
        testFocoInicialPulaFixadaVazia()
        testFocoCaiNaPrimeiraQuandoNadaTemConteudo()
```

- [ ] **Step 2: Rodar e ver falhar**

Copiar a linha `eventoscheck` de `tools/check.sh` (linhas 89-96) ou rodar o gate inteiro:

```bash
./tools/check.sh
```

Esperado: FALHA de compilação do `eventoscheck` — `value of type 'AppSettings' has no member 'notchSectionsFixadas'`.

- [ ] **Step 3: Implementar**

Em `Knobler/AppSettings.swift`, logo depois do bloco de `notchSectionOrder`:

```swift
    /// Seções que aparecem no card aberto mesmo sem conteúdo. Vazio = padrão.
    @Published var notchSectionsFixadas: Set<NotchSection> {
        didSet {
            UserDefaults.standard.set(notchSectionsFixadas.map(\.rawValue).sorted(),
                                      forKey: "notchSectionsFixadas")
        }
    }
```

No `init`, ao lado da leitura de `notchSectionOrder`:

```swift
        notchSectionsFixadas = NotchSectionOrder.sanearFixadas(
            salvas: defaults.stringArray(forKey: "notchSectionsFixadas") ?? [])
```

Em `Knobler/NotchViewModel.swift`, dentro de `recalcularSecoes`, passar as fixadas:

```swift
        secoes = NotchSectionOrder.ordenar(base: AppSettings.shared.notchSectionOrder,
                                           estados: estados,
                                           fixadas: AppSettings.shared.notchSectionsFixadas,
                                           agora: Date(),
                                           travadaNaNota: travadaNaNota)
```

e, na escolha do foco inicial, trocar

```swift
        guard !focusLocked, let primeira = secoes.first else {
```

por

```swift
        // uma seção fixada aparece vazia; abrir o card em cima dela mostraria
        // "Nada tocando" com música parada, então o foco procura o primeiro
        // conteúdo real e só cai no primeiro da lista quando não há nenhum.
        let comConteudo = Set(estados.filter(\.hasContent).map(\.section))
        let inicial = secoes.first(where: { comConteudo.contains($0) }) ?? secoes.first
        guard !focusLocked, let primeira = inicial else {
```

- [ ] **Step 4: Rodar e ver passar**

```bash
./tools/check.sh
```

Esperado: todos os gates verdes, incluindo `✅ eventoscheck ok`.

- [ ] **Step 5: Commit**

```bash
git add Knobler/AppSettings.swift Knobler/NotchViewModel.swift tools/eventoscheck.swift
git commit -m "feat: ajuste de seções fixadas e foco no primeiro conteúdo real"
```

---

### Task 3: estados vazios das seções

**Files:**
- Modify: `Knobler/NotchView.swift` (`expandedContent` ~linha 834; `musicSection` ~linha 1086; `activityRow`/`pomodoroSection` chamadas)

**Interfaces:**
- Consumes: nada das tarefas anteriores (mudança puramente de view)
- Produces: `NotchView.vazio(_ simbolo: String, _ texto: String) -> some View` — o desenho comum de seção vazia.

- [ ] **Step 1: Adicionar o helper de estado vazio**

Em `Knobler/NotchView.swift`, ao lado de `activityRow` (~linha 1030):

```swift
    /// Desenho comum de seção fixada e vazia. Mesma altura da seção cheia:
    /// uma altura só evita um segundo eixo de casos no `alturaDaSecao`.
    private func vazio(_ simbolo: String, _ texto: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: simbolo)
                .font(.title2)
                .foregroundStyle(.white.opacity(0.4))
            Text(texto)
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.4))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
```

- [ ] **Step 2: Ligar o helper nas seções que hoje não desenham nada**

No `switch vm.focus` de `expandedContent`:

```swift
                case .espelho: if vm.mirrorOn { mirrorSection } else { espelhoDesligado }
                case .link: if linkPreview.url != nil { LinkPreviewView(preview: linkPreview) }
                           else { vazio("globe", "Nenhum link copiado") }
                case .atividade:
                    if let a = vm.activity { activityRow(a) }
                    else { vazio("arrow.triangle.2.circlepath", "Nenhuma atividade") }
                case .pomodoro:
                    // ponytail: texto, não botão. `Pomodoro.startNext()` só sai
                    // de `.waiting`; não existe "iniciar do zero" no VM hoje.
                    // Vira ação quando alguém pedir.
                    if let p = vm.pomodoro { pomodoroSection(p) }
                    else { vazio("timer", "Pomodoro parado") }
```

E os dois desenhos com ação, ao lado de `vazio`:

```swift
    /// Espelho fixado e desligado: o botão que já existe, centralizado.
    private var espelhoDesligado: some View {
        VStack(spacing: 6) {
            Image(systemName: "person.crop.square")
                .font(.title2)
                .foregroundStyle(.white.opacity(0.4))
            mirrorButton
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

```

`LinkPreview.url` já é `@Published private(set) var url: URL?` (`Knobler/LinkPreview.swift:23`) — nada novo a criar ali.

- [ ] **Step 3: Soltar a condição do vazio da música**

Em `musicSection` (~linha 1086), o `else if` amarra o "Nada tocando" ao resto do card:

```swift
        } else if vm.activity == nil, shelf.items.isEmpty, !vm.mirrorOn {
```

Trocar por `} else {` — quando a Música é a seção renderizada, o vazio dela é o que deve aparecer. O `mirrorButton` que mora dentro desse bloco fica onde está.

- [ ] **Step 4: Compilar e ver na tela**

```bash
xcodebuild -project Knobler.xcodeproj -scheme Knobler -configuration Debug build
./tools/snapshot.sh
```

Esperado: build sem erro; os PNGs de `Snapshots/` regenerados. Ler os PNGs afetados (`closed-music`, `foco-*`) para confirmar que nada quebrou de layout. Os quatro PNGs não determinísticos (`closed-music`, `closed-music-external`, `foco-atividade-indeterminada`, `update-installing`) mudam de hash sempre — ignorar o diff deles.

- [ ] **Step 5: Commit**

```bash
git add Knobler/NotchView.swift
git commit -m "feat: estados vazios das seções fixáveis"
```

---

### Task 4: pin nos Ajustes

**Files:**
- Modify: `Knobler/SettingsView.swift:234-248` (`NotchSettingsPane`, seção "Ordem das seções do card")

**Interfaces:**
- Consumes: `AppSettings.shared.notchSectionsFixadas` (Task 2)

- [ ] **Step 1: Trocar a linha da lista por linha com pin**

```swift
            Section("Ordem das seções do card") {
                Text("A ordem em repouso. Algo que acabou de acontecer sobe sozinho por alguns segundos. O alfinete mantém a seção no card mesmo sem conteúdo.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                List {
                    ForEach(settings.notchSectionOrder, id: \.self) { s in
                        HStack {
                            Label(s.titulo, systemImage: s.simbolo)
                            Spacer()
                            Button {
                                if settings.notchSectionsFixadas.contains(s) {
                                    settings.notchSectionsFixadas.remove(s)
                                } else {
                                    settings.notchSectionsFixadas.insert(s)
                                }
                            } label: {
                                Image(systemName: settings.notchSectionsFixadas.contains(s)
                                      ? "pin.fill" : "pin.slash")
                            }
                            .buttonStyle(.borderless)
                            .help(settings.notchSectionsFixadas.contains(s)
                                  ? "Sempre no card" : "Só quando tem conteúdo")
                        }
                    }
                    .onMove { origem, destino in
                        settings.notchSectionOrder.move(fromOffsets: origem, toOffset: destino)
                    }
                }
                .frame(height: 220)
            }
```

- [ ] **Step 2: Compilar e abrir o painel**

```bash
xcodebuild -project Knobler.xcodeproj -scheme Knobler -configuration Debug build
```

Esperado: build sem erro. Abrir o painel real e conferir que o pin alterna e que arrastar a linha ainda reordena:

```bash
"$(ls -d ~/Library/Developer/Xcode/DerivedData/Knobler-*/Build/Products/Debug/Knobler.app | head -1)/Contents/MacOS/Knobler" --ajustes=notch
```

- [ ] **Step 3: Recapturar o screenshot do painel**

`docs/images/settings-notch.png` é mantido à mão (o harness de snapshot não gera painéis de Ajustes). Com a janela aberta pelo passo anterior, capturar por `screencapture -l<windowID>` e cortar pra `802x554+55+37` antes de salvar por cima do arquivo existente.

- [ ] **Step 4: Commit**

```bash
git add Knobler/SettingsView.swift docs/images/settings-notch.png
git commit -m "feat: alfinete por seção nos Ajustes do notch"
```

---

### Task 5: documentação e changelog

**Files:**
- Modify: `docs/settings.md` (seção do painel Notch)
- Modify: `docs/architecture.md` (onde `notchSectionOrder` é citado)
- Modify: `docs/specs/card-foco.md` (regra de visibilidade)
- Modify: `CHANGELOG.md` (`## [Unreleased]`)

- [ ] **Step 1: Achar os pontos que citam a regra atual**

```bash
grep -rn "notchSectionOrder\|hasContent" docs/
```

Em cada ocorrência que afirma "seção só aparece com conteúdo", acrescentar a exceção: "…ou quando está fixada nos Ajustes".

- [ ] **Step 2: Documentar o ajuste em `docs/settings.md`**

Na descrição do painel Notch, depois da lista de ordenação, acrescentar:

```markdown
O alfinete de cada linha fixa a seção: ela aparece no card mesmo sem conteúdo
(Nota rápida vazia, Pomodoro parado, Música sem tocar). Sem alfinete — o padrão
— a seção só entra quando tem algo a mostrar. Fixada e vazia, a seção fica na
posição escolhida aqui, mas não recebe o foco na abertura do card: o foco vai
pra primeira seção com conteúdo real.
```

- [ ] **Step 3: Changelog**

Em `CHANGELOG.md`, dentro de `## [Unreleased]`, em `### Adicionado`:

```markdown
- Seções fixadas: o alfinete em Ajustes › Notch mantém uma seção no card aberto
  mesmo sem conteúdo.
```

- [ ] **Step 4: Gate completo**

```bash
./tools/check.sh
```

Esperado: todos os gates verdes.

- [ ] **Step 5: Commit**

```bash
git add docs CHANGELOG.md
git commit -m "docs: seções fixadas do card"
```
