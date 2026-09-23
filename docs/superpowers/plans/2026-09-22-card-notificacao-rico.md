# Card de notificação rico — plano de implementação

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** O card de notificação de app mostra o app de verdade (não mais sempre WhatsApp), subtítulo, hora relativa e o texto inteiro no hover; o histórico ganha ícone.

**Architecture:** As decisões novas (nome do app a partir do `AXDescription`, rótulo dos textos, hora relativa) são funções puras em `NotificationRules`, testadas no `sharingcheck`. O `NotificationInterceptor` só coleta atributos AX e chama essas funções. A resolução nome→ícone/clique continua na `NotchView` (já existe), com três correções. A altura do card passa a vir de um único campo do `NotchPresentation.Layout`.

**Tech Stack:** Swift 5, AppKit + SwiftUI, Accessibility (`AXUIElement`), self-checks `tools/*check*.swift`, harness de snapshot `tools/snapshot.sh`.

**Spec:** `docs/superpowers/specs/2026-09-22-card-notificacao-rico-design.md` (dossiê: `docs/superpowers/research/2026-09-22-card-notificacao-rico-research.md`)

## Global Constraints

- Deployment target macOS 14.2; nenhuma API acima disso sem `if #available`.
- Nenhuma permissão nova: só Acessibilidade.
- Comentários e strings de UI em pt-BR; simplificação deliberada marcada com `// ponytail:`.
- Nunca editar `Knobler.xcodeproj`; arquivo novo exige `xcodegen generate` (este plano não cria arquivo novo em `Knobler/`).
- `./tools/check.sh` verde ao fim de cada task.
- **Commits:** `Knobler/NotchView.swift`, `NotchViewModel.swift`, `NotchPresentation.swift`, `tools/main.swift`, `tools/presentationcheck.swift`, `CHANGELOG.md` e outros já têm mudanças não commitadas de outra feature (AirPods/Monitores). Se esse trabalho ainda não estiver commitado quando a execução começar, **não commite** nas tasks — só ao fim, com o usuário decidindo como separar.

## Review Focus

1. Banner cujo `AXDescription` não tem `", "` (ou não existe): card com sino e sem nome, nunca WhatsApp, nunca crash — coberto em `testAppNameDaDescricao` (Task 2).
2. Nome do WhatsApp com U+200E no banner **e** no `localizedName` do processo: ícone e clique têm que casar mesmo assim — coberto em `testLimpo` (Task 2) e na verificação ao vivo (Task 7).
3. Histórico gravado por versão anterior (sem `subtitle`, com `bundleID` do WhatsApp): carrega sem perder linha — coberto em `testSubtitleNoDisco` (Task 3).
4. Texto gigante no hover: card não passa do teto nem da tela — coberto em `presentationcheck` (Task 5).
5. Mouse sai do card expandido: volta ao compacto e o auto-dismiss reagenda; dismiss zera o estado — coberto em Task 5 Step 5 (snapshot + leitura do código) e Task 7 (ao vivo).

---

### Task 1: Gate — ler um banner real ✅ feito em 2026-09-23

Dump de um banner do WhatsApp nesta máquina (macOS 27.0):

- Banner: `AXGroup`, `AXSubrole=AXNotificationCenterBanner`.
- `AXAttributedDescription` = `"\u{200E}WhatsApp, Ana, Grupo, Teste"`.
  **Não há `AXDescription` de texto puro** no banner — a Task 4 lê a formatada.
- Textos: `AXStaticText` com `AXIdentifier` `title` ("Ana"),
  `subtitle` ("Grupo"), `body` ("Teste"). Nenhum texto `date`.
- Ações: `AXPress`, `Mostrar Detalhes`, `\u{200E}Responder`, `Fechar`
  (registro pro sub-projeto de ações).

Para repetir: dumper de atributos completos em
`/private/tmp/claude-501/-Users-luccassilveira-Desktop-Projetos-knobler/b753ad93-d607-484b-b0bc-e29e169fee01/scratchpad/axfull.swift`,
com o Knobler fechado.

---

### Task 2: Regras puras — nome do app, textos do banner, hora

**Files:**
- Modify: `Knobler/NotificationRules.swift` (acrescentar ao fim do `enum`)
- Test: `tools/sharingcheck.swift`

**Interfaces:**
- Produces:
  - `NotificationRules.TextoDoBanner` — `struct { let id: String?; let valor: String }`, `Equatable`
  - `NotificationRules.limpo(_ s: String) -> String`
  - `NotificationRules.appName(fromDescription: String?) -> String?`
  - `NotificationRules.partes(_ textos: [TextoDoBanner]) -> (title: String, subtitle: String?, body: String)?`
  - `NotificationRules.haQuanto(_ data: Date, agora: Date) -> String`

- [ ] **Step 1: Escrever os testes**

Em `tools/sharingcheck.swift`, no `main()`, antes do `print`:

```swift
        testLimpo()
        testAppNameDaDescricao()
        testPartesDoBanner()
        testHaQuanto()
```

E, dentro do `struct SharingCheck`:

```swift
    /// O WhatsApp manda U+200E grudado no nome do app e no texto; sem limpar,
    /// "‎WhatsApp" nunca casa com o processo e o card perde ícone e clique.
    static func testLimpo() {
        assert(NotificationRules.limpo("\u{200E}WhatsApp") == "WhatsApp")
        assert(NotificationRules.limpo("  Mail \n") == "Mail")
        assert(NotificationRules.limpo("\u{200E}📷 \u{200E}Foto") == "📷 Foto")
        assert(NotificationRules.limpo("\u{200E}") == "")
    }

    /// O banner do Tahoe não tem o app nos textos: ele vem no começo do
    /// AXDescription, "App, título, corpo", sem escape de vírgula.
    static func testAppNameDaDescricao() {
        assert(NotificationRules.appName(fromDescription: "WhatsApp, Ana, Oi") == "WhatsApp")
        assert(NotificationRules.appName(fromDescription: "\u{200E}WhatsApp, Ana, Oi") == "WhatsApp")
        assert(NotificationRules.appName(fromDescription: "AirDrop, Recebendo uma foto") == "AirDrop")
        assert(NotificationRules.appName(fromDescription: "Mail, Oi, tudo bem, e aí") == "Mail",
               "vírgula no conteúdo não muda o app")
        assert(NotificationRules.appName(fromDescription: "SemVirgula") == nil,
               "sem separador não dá pra saber o que é app")
        assert(NotificationRules.appName(fromDescription: ", corpo") == nil, "nome vazio")
        assert(NotificationRules.appName(fromDescription: "") == nil)
        assert(NotificationRules.appName(fromDescription: nil) == nil)
    }

    static func testPartesDoBanner() {
        typealias T = NotificationRules.TextoDoBanner
        func p(_ t: [T]) -> (String, String?, String)? {
            NotificationRules.partes(t).map { ($0.title, $0.subtitle, $0.body) }
        }
        // rotulado: a ordem na árvore não importa, a hora some
        let r = p([T(id: "date", valor: "agora"), T(id: "body", valor: "Oi"),
                   T(id: "subtitle", valor: "Grupo da família"), T(id: "title", valor: "Ana")])
        assert(r?.0 == "Ana" && r?.1 == "Grupo da família" && r?.2 == "Oi")
        let semSub = p([T(id: "title", valor: "Ana"), T(id: "body", valor: "Oi")])
        assert(semSub?.0 == "Ana" && semSub?.1 == nil && semSub?.2 == "Oi")
        let soSub = p([T(id: "subtitle", valor: "Grupo"), T(id: "body", valor: "oi")])
        assert(soSub?.0 == "Grupo" && soSub?.1 == nil && soSub?.2 == "oi",
               "sem título, o subtítulo sobe")
        let soCorpo = p([T(id: "body", valor: "oi"), T(id: "date", valor: "agora")])
        assert(soCorpo?.0 == "oi" && soCorpo?.2 == "", "só corpo vira título")
        assert(p([T(id: "date", valor: "agora")]) == nil, "só hora não é notificação")
        assert(p([T(id: "title", valor: "\u{200E}")]) == nil, "texto invisível é vazio")
        let limpo = p([T(id: "title", valor: "\u{200E}Ana"), T(id: "body", valor: "\u{200E}📷 Foto")])
        assert(limpo?.0 == "Ana" && limpo?.2 == "📷 Foto")
        // sem rótulo nenhum: posição
        assert(p([]) == nil)
        let um = p([T(id: nil, valor: "Só título")])
        assert(um?.0 == "Só título" && um?.1 == nil && um?.2 == "")
        let dois = p([T(id: nil, valor: "Ana"), T(id: nil, valor: "Oi")])
        assert(dois?.0 == "Ana" && dois?.1 == nil && dois?.2 == "Oi")
        let quatro = p([T(id: nil, valor: "A"), T(id: nil, valor: "B"),
                        T(id: nil, valor: "C"), T(id: nil, valor: "D")])
        assert(quatro?.0 == "A" && quatro?.1 == "B" && quatro?.2 == "C D")
    }

    static func testHaQuanto() {
        let t0 = Date(timeIntervalSince1970: 1_000_000)
        func h(_ s: TimeInterval) -> String { NotificationRules.haQuanto(t0, agora: t0 + s) }
        assert(h(0) == "agora")
        assert(h(59) == "agora")
        assert(h(60) == "há 1 min")
        assert(h(3599) == "há 59 min")
        assert(h(3600) == "há 1 h")
        assert(h(-30) == "agora", "relógio pra trás não vira número negativo")
    }
```

- [ ] **Step 2: Rodar e ver falhar**

```bash
xcrun swiftc -parse-as-library -swift-version 5 \
  Knobler/Sharing.swift Knobler/NotificationRules.swift tools/sharingcheck.swift \
  -o /tmp/sharingcheck && /tmp/sharingcheck
```

Expected: erro de compilação, `type 'NotificationRules' has no member 'limpo'`.

- [ ] **Step 3: Implementar**

Ao fim do `enum NotificationRules`, antes da `}` final:

```swift
    // MARK: - Conteúdo do banner

    /// Um texto do banner com o rótulo que o macOS dá a ele (`AXIdentifier`:
    /// title, subtitle, body, date). `id` nil = texto sem rótulo.
    struct TextoDoBanner: Equatable {
        let id: String?
        let valor: String
    }

    /// Tira espaço das pontas e caracteres invisíveis. O WhatsApp manda U+200E
    /// grudado no nome do app e no texto: sem isso "‎WhatsApp" nunca casa com o
    /// nome do processo.
    static func limpo(_ s: String) -> String {
        var scalars = String.UnicodeScalarView()
        scalars.append(contentsOf: s.unicodeScalars.filter {
            !$0.properties.isDefaultIgnorableCodePoint
        })
        return String(scalars).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Nome do app de origem. No Tahoe ele não é um dos textos do banner: vem
    /// no começo do `AXDescription`, no formato "App, título, corpo". A vírgula
    /// do conteúdo não tem escape, então só o primeiro trecho é confiável —
    /// e sem separador nenhum não dá pra saber o que é app.
    static func appName(fromDescription descricao: String?) -> String? {
        guard let descricao, let corte = descricao.range(of: ", ") else { return nil }
        let nome = limpo(String(descricao[..<corte.lowerBound]))
        return nome.isEmpty ? nil : nome
    }

    /// Título, subtítulo e corpo. Pelo rótulo quando o banner tem; pela posição
    /// só quando nenhum texto tem rótulo. A hora do banner (`date`) é descartada:
    /// o card calcula a própria.
    static func partes(_ textos: [TextoDoBanner]) -> (title: String, subtitle: String?, body: String)? {
        let t = textos.map { TextoDoBanner(id: $0.id, valor: limpo($0.valor)) }
            .filter { !$0.valor.isEmpty }
        let rotulos: Set<String> = ["title", "subtitle", "body", "date"]
        if t.contains(where: { $0.id.map(rotulos.contains) == true }) {
            func valor(_ id: String) -> String? { t.first { $0.id == id }?.valor }
            let body = valor("body") ?? ""
            switch (valor("title"), valor("subtitle")) {
            case let (title?, sub): return (title, sub, body)
            case let (nil, sub?): return (sub, nil, body)
            case (nil, nil): return body.isEmpty ? nil : (body, nil, "")
            }
        }
        switch t.count {
        case 0: return nil
        case 1: return (t[0].valor, nil, "")
        case 2: return (t[0].valor, nil, t[1].valor)
        default: return (t[0].valor, t[1].valor, t[2...].map(\.valor).joined(separator: " "))
        }
    }

    /// Hora do card: "agora" no primeiro minuto, depois minutos, depois horas.
    static func haQuanto(_ data: Date, agora: Date) -> String {
        let s = max(0, agora.timeIntervalSince(data))
        if s < 60 { return "agora" }
        if s < 3600 { return "há \(Int(s / 60)) min" }
        return "há \(Int(s / 3600)) h"
    }
```

- [ ] **Step 4: Rodar e ver passar**

Mesmo comando do Step 2. Expected: `✅ sharingcheck ok`.

- [ ] **Step 5: Atualizar o cabeçalho do `sharingcheck`**

Linha 2-3 de `tools/sharingcheck.swift` passa a dizer: `self-check do envio (Sharing) e das regras puras do interceptor (NotificationRules): botão de ação, AirDrop, silêncio, e o conteúdo do banner.`

- [ ] **Step 6: Commit** (ver Global Constraints)

```bash
git add Knobler/NotificationRules.swift tools/sharingcheck.swift
git commit -m "feat(notificações): regras puras do conteúdo do banner"
```

---

### Task 3: `subtitle` no `NotchNotification`

**Files:**
- Modify: `Knobler/NotchNotification.swift` (propriedades ~:18, `CodingKeys` :65-69, `init(from:)` :71-92, `encode` :94-117, `init` :121-157)
- Test: `tools/historycheck.swift`

**Interfaces:**
- Produces: `NotchNotification.subtitle: String?`; parâmetro `subtitle: String? = nil` no `init`, logo após `body:`.

- [ ] **Step 1: Escrever o teste**

Em `tools/historycheck.swift`, `main()`, depois de `testPersistencia()`:

```swift
        testSubtitleNoDisco()
```

E a função:

```swift
    /// Arquivo gravado antes do subtítulo existir continua carregando; o
    /// subtítulo novo sobrevive ao disco.
    static func testSubtitleNoDisco() {
        let antigo = """
        [{"id":"\(UUID().uuidString)","appName":"\u{200E}WhatsApp","title":"Ana","body":"Oi",
          "bundleID":"net.whatsapp.WhatsApp","revealsDownloads":false,"date":\(Date().timeIntervalSinceReferenceDate)}]
        """
        let velho = try! JSONDecoder().decode([NotchNotification].self, from: Data(antigo.utf8))
        assert(velho.count == 1 && velho[0].subtitle == nil && velho[0].title == "Ana",
               "histórico sem subtitle carrega")

        let n = NotchNotification(appName: "WhatsApp", title: "Ana", body: "Oi",
                                  subtitle: "Grupo da família")
        let volta = try! JSONDecoder().decode(
            NotchNotification.self, from: try! JSONEncoder().encode(n))
        assert(volta.subtitle == "Grupo da família", "subtitle sobrevive ao disco")
        let semSub = try! JSONDecoder().decode(
            NotchNotification.self,
            from: try! JSONEncoder().encode(NotchNotification(appName: nil, title: "x", body: "")))
        assert(semSub.subtitle == nil)
    }
```

- [ ] **Step 2: Rodar e ver falhar**

```bash
xcrun swiftc -parse-as-library -swift-version 5 \
  Knobler/NotchNotification.swift Knobler/NotificationHistory.swift Knobler/NotchGesture.swift \
  tools/historycheck.swift -o /tmp/historycheck && /tmp/historycheck
```

Expected: `extra argument 'subtitle' in call`.

- [ ] **Step 3: Implementar**

Propriedade, logo após `let body: String`:

```swift
    /// Linha entre título e corpo (ex.: nome do grupo). Só banner de app tem.
    var subtitle: String? = nil
```

`CodingKeys`: acrescentar `subtitle` à primeira linha (`case id, appName, title, body, subtitle, bundleID, supacodeWorktree, supacodeTab`).

`init(from:)`, após `body = …`:

```swift
        subtitle = try box.decodeIfPresent(String.self, forKey: .subtitle)
```

`encode`, após `try box.encode(body, forKey: .body)`:

```swift
        try box.encodeIfPresent(subtitle, forKey: .subtitle)
```

`init`: parâmetro `subtitle: String? = nil,` logo após `body: String,`, e `self.subtitle = subtitle` após `self.body = body`. No comentário acima do `init`, trocar "pros 22 pontos que constroem notificação no app" por "pros pontos que constroem notificação no app".

- [ ] **Step 4: Rodar e ver passar**

Mesmo comando. Expected: `✅ historycheck ok`. Depois `./tools/check.sh` inteiro (outros checks constroem `NotchNotification`). Expected: todos verdes.

- [ ] **Step 5: Commit**

```bash
git add Knobler/NotchNotification.swift tools/historycheck.swift
git commit -m "feat(notificações): subtítulo no NotchNotification"
```

---

### Task 4: Interceptor lê app e rótulos; sai o WhatsApp fixo

**Files:**
- Modify: `Knobler/NotificationInterceptor.swift` (`process` :120-164, `defaultBundleID` e comentário :202-207, `parse` :235-249, `appName(forBundleID:)` :251-260, `collectStaticTexts` :262-271)

**Interfaces:**
- Consumes: `NotificationRules.TextoDoBanner`, `.partes(_:)`, `.appName(fromDescription:)` (Task 2); `NotchNotification(…subtitle:)` (Task 3).

O interceptor não compila isolado (depende de AX e `AppSettings`); o gate é o build do app e a verificação ao vivo da Task 7.

- [ ] **Step 1: `collectStaticTexts` guarda o rótulo**

```swift
    private func collectStaticTexts(_ element: AXUIElement,
                                    into texts: inout [NotificationRules.TextoDoBanner],
                                    depth: Int = 0) {
        guard depth <= 8, texts.count < 8 else { return }
        if stringAttribute(element, kAXRoleAttribute) == (kAXStaticTextRole as String),
           let value = stringAttribute(element, kAXValueAttribute) {
            texts.append(.init(id: stringAttribute(element, kAXIdentifierAttribute), valor: value))
        }
        for child in children(of: element) {
            collectStaticTexts(child, into: &texts, depth: depth + 1)
        }
    }
```

- [ ] **Step 2: `parse` usa as regras puras**

```swift
    private func parse(_ banner: AXUIElement)
        -> (appName: String?, title: String, subtitle: String?, body: String)? {
        var texts: [NotificationRules.TextoDoBanner] = []
        collectStaticTexts(banner, into: &texts)
        guard let partes = NotificationRules.partes(texts) else { return nil }
        // no Tahoe o app não é um dos textos: vem no começo da descrição do
        // banner. O banner comum só expõe a versão formatada
        // (AXAttributedDescription); o alerta do AirDrop expõe a de texto puro.
        let descricao = (copyAttribute(banner, "AXAttributedDescription") as? NSAttributedString)?.string
            ?? stringAttribute(banner, kAXDescriptionAttribute)
        let app = NotificationRules.appName(fromDescription: descricao)
        return (app, partes.title, partes.subtitle, partes.body)
    }
```

- [ ] **Step 3: `process` passa o que leu**

Chave de dedupe:

```swift
        let key = "\(parsed.appName ?? "")|\(parsed.title)|\(parsed.subtitle ?? "")|\(parsed.body)"
```

Construção do card:

```swift
        onNotification(NotchNotification(
            // sem nome legível fica nil: o card cai no sino em vez de fingir
            // ser de um app que não é
            appName: airdrop ? "AirDrop" : parsed.appName,
            title: parsed.title,
            body: parsed.body,
            subtitle: parsed.subtitle,
            iconEmoji: airdrop ? "📥" : nil,
            actionTitles: buttons.map(\.title),
            actionToken: token,
            // clique no card do AirDrop revela a pasta de destino
            revealsDownloads: airdrop
        ))
```

- [ ] **Step 4: Apagar o que ficou morto**

Remover `defaultBundleID` com o comentário acima dele (:202-207) e `appName(forBundleID:)` (:251-260). Conferir:

```bash
grep -n "defaultBundleID\|appName(forBundleID" Knobler/*.swift
```

Expected: nenhuma linha.

- [ ] **Step 5: Build**

```bash
xcodebuild -project Knobler.xcodeproj -scheme Knobler -configuration Debug build 2>&1 | grep -E "error:|BUILD" | tail -5
```

Expected: `** BUILD SUCCEEDED **`. `./tools/check.sh` verde.

- [ ] **Step 6: Commit**

```bash
git add Knobler/NotificationInterceptor.swift
git commit -m "fix(notificações): banner mostra o app de origem em vez de sempre WhatsApp"
```

---

### Task 5: Card — resolução por nome, subtítulo, hora e texto inteiro no hover

**Files:**
- Modify: `Knobler/NotchPresentation.swift` (`Layout` :121-132, `.notification` :152-153)
- Modify: `Knobler/NotchViewModel.swift` (hold/dismiss da notificação :609-629)
- Modify: `Knobler/NotchView.swift` (layout :73, frame do card :174-178, `notificationCard` :1298-1343, `openSourceApp` :1377-1383, `runningApp` :1409-1414, `appPath` :1416-1427)
- Test: `tools/presentationcheck.swift`, `tools/main.swift` (cenários)

**Interfaces:**
- Consumes: `NotificationRules.limpo`, `.haQuanto` (Task 2); `NotchNotification.subtitle` (Task 3).
- Produces: `NotchPresentation.Layout.notificationExtra: CGFloat`; `NotchPresentation.notificationExtraMax: CGFloat = 200`; `NotchViewModel.notificationHeld: Bool` (`@Published private(set)`); `NotchView.appPath(bundleID:named:)` e `RemoteAvatarView` deixam de ser `private` (Task 6 usa).

- [ ] **Step 1: Teste da altura**

Em `tools/presentationcheck.swift`, depois do bloco `do { … }` dos AirPods:

```swift
        do {
            var layout = NotchPresentation.Layout()
            layout.realNotch = true
            let base = NotchPresentation(content: NotchContentState(notification: true), layout: layout)
            assert(base.size == CGSize(width: 380, height: 32 + 56))
            layout.notificationExtra = 40
            let aberto = NotchPresentation(content: NotchContentState(notification: true), layout: layout)
            assert(aberto.size.height == base.size.height + 40, "hover soma a altura do texto")
            layout.notificationActions = true
            let comBotao = NotchPresentation(content: NotchContentState(notification: true), layout: layout)
            assert(comBotao.size.height == 32 + 92 + 40, "botões e texto somam")
            layout.notificationActions = false
            layout.notificationExtra = 5_000
            let gigante = NotchPresentation(content: NotchContentState(notification: true), layout: layout)
            assert(gigante.size.height == 32 + 56 + NotchPresentation.notificationExtraMax,
                   "texto gigante para no teto")
        }
```

Rodar (`check.sh:64`):

```bash
xcrun swiftc -parse-as-library -swift-version 5 Knobler/NotchSectionOrder.swift \
  Knobler/NotchPresentation.swift tools/presentationcheck.swift -o /tmp/presentationcheck && /tmp/presentationcheck
```

Expected: `value of type 'NotchPresentation.Layout' has no member 'notificationExtra'`.

- [ ] **Step 2: `NotchPresentation`**

No `Layout`, após `var notificationActions = false`:

```swift
        /// Altura a mais do card de notificação: subtítulo e, com o mouse em
        /// cima, o texto inteiro. Medida pela NotchView; teto em `notificationExtraMax`.
        var notificationExtra: CGFloat = 0
```

No `struct NotchPresentation` (junto de `airpodsCardWidth`):

```swift
    /// Teto do texto aberto no hover: o resto é cortado, o card não cresce além.
    static let notificationExtraMax: CGFloat = 200
```

No `case .notification:`:

```swift
            target = CGSize(width: 380, height: topInset + (layout.notificationActions ? 92 : 56)
                            + min(max(layout.notificationExtra, 0), Self.notificationExtraMax))
```

Rodar o Step 1 de novo. Expected: `presentationcheck` passa.

- [ ] **Step 3: `NotchViewModel` publica o hover**

Junto de `@Published var activeNotification`:

```swift
    /// Mouse sobre o card de notificação: o timer para e o texto abre inteiro.
    @Published private(set) var notificationHeld = false
```

`holdNotification`:

```swift
    func holdNotification(_ hovering: Bool) {
        guard activeNotification != nil else { return }
        notificationHeld = hovering
        if hovering {
            dismissWork?.cancel()
        } else {
            scheduleDismiss()
        }
    }
```

`dismissActiveNotification`, logo após `activeNotification = nil`:

```swift
        notificationHeld = false
```

- [ ] **Step 4: `NotchView` — altura, card e resolução por nome**

Layout (junto de `layout.notificationActions = …`, :73):

```swift
        layout.notificationExtra = Self.alturaExtra(vm.activeNotification, aberto: vm.notificationHeld)
```

Frame do card (:174-178) passa a seguir a apresentação — uma fonte só de altura:

```swift
            case .notification:
                notificationCard
                    .frame(width: currentSize.width - 48,
                           height: currentSize.height - topInset, alignment: .top)
```

Medida (na `MARK: - Notificação`):

```swift
    /// Quanto o card cresce além do compacto (título 1 linha + corpo 2).
    /// ponytail: estimativa por métrica de fonte, não medida do layout real;
    /// errar por uma linha só sobra ou corta um pouco. Trocar por medição via
    /// PreferenceKey se incomodar.
    static func alturaExtra(_ n: NotchNotification?, aberto: Bool) -> CGFloat {
        guard let n else { return 0 }
        // card 380 − padding 48 − ícone 32 − espaço 12
        let largura: CGFloat = 288
        func altura(_ texto: String, _ fonte: NSFont, max linhas: Int?) -> CGFloat {
            guard !texto.isEmpty else { return 0 }
            let linha = ceil(fonte.ascender - fonte.descender + fonte.leading)
            let total = (texto as NSString).boundingRect(
                with: CGSize(width: largura, height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin], attributes: [.font: fonte]).height
            let n = Swift.max(1, Int((total / linha).rounded(.up)))
            return CGFloat(linhas.map { Swift.min(n, $0) } ?? n) * linha
        }
        let tituloF = NSFont.systemFont(ofSize: NSFont.preferredFont(forTextStyle: .subheadline).pointSize,
                                        weight: .semibold)
        let corpoF = NSFont.preferredFont(forTextStyle: .caption1)
        let compacto = altura("x", tituloF, max: 1) + altura("x\nx", corpoF, max: 2)
        let agora = altura(n.title, tituloF, max: aberto ? nil : 1)
            + altura(n.subtitle ?? "", corpoF, max: aberto ? nil : 1)
            + altura(n.body, corpoF, max: aberto ? nil : 2)
        return Swift.max(0, agora - compacto)
    }
```

`notificationCard`: o `VStack` de textos passa a ser:

```swift
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text(notification.title)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.white)
                                .lineLimit(vm.notificationHeld ? nil : 1)
                            Spacer(minLength: 0)
                            Text(NotificationRules.haQuanto(notification.date, agora: Date()))
                                .font(.caption2)
                                .foregroundStyle(.white.opacity(0.45))
                                .fixedSize()
                        }
                        if let subtitle = notification.subtitle, !subtitle.isEmpty {
                            Text(subtitle)
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.white.opacity(0.8))
                                .lineLimit(vm.notificationHeld ? nil : 1)
                        }
                        if !notification.body.isEmpty {
                            Text(notification.body)
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.65))
                                .lineLimit(vm.notificationHeld ? nil : 2)
                        }
                    }
```

A largura da hora sai do título; a estimativa de `alturaExtra` ignora isso de propósito (cabe no `ponytail:`).

Resolução por nome — `runningApp` compara limpo dos dois lados (o `localizedName` do WhatsApp também traz U+200E):

```swift
    private static func runningApp(named name: String?) -> NSRunningApplication? {
        guard let name else { return nil }
        let alvo = NotificationRules.limpo(name)
        guard !alvo.isEmpty else { return nil }
        return NSWorkspace.shared.runningApplications.first {
            NotificationRules.limpo($0.localizedName ?? "")
                .localizedCaseInsensitiveCompare(alvo) == .orderedSame
        }
    }
```

`appPath` — internal (Task 6 usa) e olha `~/Applications` (web apps do Safari, PWAs do Chrome):

```swift
    /// Caminho do app pro ícone: bundle ID exato, senão app rodando pelo nome,
    /// senão instalado em /Applications ou ~/Applications.
    static func appPath(bundleID: String?, named name: String?) -> String? {
        if let bundleID,
           let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            return url.path
        }
        if let path = runningApp(named: name)?.bundleURL?.path { return path }
        guard let name else { return nil }
        let nome = NotificationRules.limpo(name)
        guard !nome.isEmpty else { return nil }
        let pastas = ["/Applications", NSHomeDirectory() + "/Applications"]
        return pastas.map { "\($0)/\(nome).app" }
            .first { FileManager.default.fileExists(atPath: $0) }
    }
```

`openSourceApp` — fim da função (troca a última linha, :1383):

```swift
        if let app = Self.runningApp(named: notification.appName) {
            app.activate()
            return
        }
        // app instalado e fechado: abre, em vez de o clique não fazer nada.
        // Só procura em pastas de apps — nome vindo da API local não vira
        // caminho arbitrário.
        if let path = Self.appPath(bundleID: notification.bundleID, named: notification.appName) {
            NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: path),
                                               configuration: NSWorkspace.OpenConfiguration())
        }
```

`nome` com `/` ou `..` escaparia da pasta: acrescentar em `appPath`, logo após `guard !nome.isEmpty`:

```swift
        guard !nome.contains("/") else { return nil }
```

`RemoteAvatarView`: trocar `private struct RemoteAvatarView` por `struct RemoteAvatarView`.

- [ ] **Step 5: Cenários de snapshot**

Em `tools/main.swift`, logo após o cenário `"notification"`:

```swift
    Scenario(name: "notification-subtitulo", realNotch: true) { vm, _, _ in
        vm.activeNotification = NotchNotification(
            appName: "Finder", title: "Ana Souza",
            body: "Bagulho tava em mais de 60% última vez que eu vi",
            subtitle: "Grupo da família")
    },
    // hover: o texto abre inteiro e o card cresce junto
    Scenario(name: "notification-aberta", realNotch: true, frameHeight: 360) { vm, _, _ in
        vm.activeNotification = NotchNotification(
            appName: "Finder", title: "Carlos Lima",
            body: "Caso estranho. Durante o atendimento que já estava sendo realizado, a IA entrou e mandou essa mensagem. Como podemos corrigir? Já tentei desligar e ligar a automação de novo e continua acontecendo com outros contatos também.")
        vm.holdNotification(true)
    },
    // app que não se identifica: sino, nunca WhatsApp
    Scenario(name: "notification-sem-app", realNotch: true) { vm, _, _ in
        vm.activeNotification = NotchNotification(
            appName: nil, title: "Acesso aos dados bloqueado",
            body: "O app Instagram tentou acessar seus dados a partir de outros apps e foi bloqueado.")
    },
```

```bash
./tools/snapshot.sh
```

Ler `Snapshots/notification-subtitulo.png`, `notification-aberta.png`, `notification-sem-app.png`, `notification.png`. Expected: subtítulo em linha própria e "agora" à direita do título; a aberta mostra o corpo inteiro sem sair do card nem cortar embaixo; a sem-app mostra o sino. `notification.png` igual ao anterior exceto pela hora.

Ler o código: `notificationHeld` volta a `false` em `holdNotification(false)` e em `dismissActiveNotification` (Review Focus 5).

- [ ] **Step 6: Build + checks**

```bash
xcodebuild -project Knobler.xcodeproj -scheme Knobler -configuration Debug build 2>&1 | grep -E "error:|BUILD" | tail -5
./tools/check.sh
```

Expected: `BUILD SUCCEEDED`, checks verdes (inclui `cortecheck`, que lê a mesma lista de fontes).

- [ ] **Step 7: Commit**

```bash
git add Knobler/NotchPresentation.swift Knobler/NotchViewModel.swift Knobler/NotchView.swift \
  tools/presentationcheck.swift tools/main.swift Snapshots/notification*.png
git commit -m "feat(notificações): subtítulo, hora e texto inteiro no hover do card"
```

---

### Task 6: Ícone na linha do histórico

**Files:**
- Modify: `Knobler/HistoryListView.swift` (`linha(_:)` :67-110 vira `HistoryRow`)
- Modify: `tools/main.swift` (render isolado da linha, no molde de `renderOverlay` :875)

**Interfaces:**
- Consumes: `RemoteAvatarView`, `NotchView.appPath(bundleID:named:)` (Task 5).
- Produces: `struct HistoryRow: View { let item: NotchNotification; let mostraX: Bool; let onRemove: () -> Void }`.

- [ ] **Step 1: Extrair a linha**

Em `HistoryListView.swift`, abaixo do `HistoryListView`:

```swift
/// Uma linha do histórico. Separada da lista pra renderizar sozinha no
/// harness: a lista vive num ScrollView, que sai preto offscreen.
struct HistoryRow: View {
    let item: NotchNotification
    /// O X só aparece na linha sob o ponteiro.
    let mostraX: Bool
    let onRemove: () -> Void

    private static let hora: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(Self.hora.string(from: item.date))
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.white.opacity(0.4))
                .frame(width: 38, alignment: .leading)
            RemoteAvatarView(iconURL: item.iconURL, iconEmoji: item.iconEmoji,
                             iconColor: item.iconColor,
                             fallbackPath: NotchView.appPath(bundleID: item.bundleID,
                                                             named: item.appName))
                .frame(width: 16, height: 16)
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
                let resto = [item.subtitle, item.body].compactMap { $0 }
                    .filter { !$0.isEmpty }.joined(separator: " · ")
                if !resto.isEmpty {
                    Text(resto)
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.55))
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            // o `frame` fixo segura o lugar do X pra linha não dançar no hover
            Button(action: onRemove) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white.opacity(0.5))
            }
            .buttonStyle(.plain)
            .opacity(mostraX ? 1 : 0)
            .frame(width: 12)
        }
    }
}
```

`linha(_:)` no `HistoryListView` vira:

```swift
    private func linha(_ item: NotchNotification) -> some View {
        HistoryRow(item: item, mostraX: hovered == item.id) { history.remover(item.id) }
            .contentShape(Rectangle())
            .onHover { hovered = $0 ? item.id : (hovered == item.id ? nil : hovered) }
            .onTapGesture {
                NotchView.openSourceApp(item)
                onOpen()
            }
    }
```

Remover o `static let hora` do `HistoryListView` (foi pra `HistoryRow`).

- [ ] **Step 2: Render isolado no harness**

Em `tools/main.swift`, depois de `renderOverlay`:

```swift
// Linhas do histórico fora da lista: a lista é um ScrollView e sai preta
// offscreen, mas a linha sozinha renderiza — é o gate do ícone.
@MainActor func renderHistoryRows(_ name: String, _ itens: [NotchNotification]) {
    let view = VStack(alignment: .leading, spacing: 6) {
        ForEach(itens) { HistoryRow(item: $0, mostraX: false, onRemove: {}) }
    }
    .padding(16)
    .frame(width: 430, alignment: .leading)
    .background(Color.black)
    let renderer = ImageRenderer(content: view)
    renderer.scale = 2
    guard let nsImage = renderer.nsImage,
          let tiff = nsImage.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:])
    else { print("FALHOU: \(name)"); exit(1) }
    let path = "\(outputDir)/\(name).png"
    try? png.write(to: URL(fileURLWithPath: path))
    print("ok \(path)")
}
```

E, junto das chamadas `renderOverlay(…)` (:932):

```swift
renderHistoryRows("historico-linhas", [
    NotchNotification(appName: "Finder", title: "Backup concluído", body: "Time Machine terminou."),
    NotchNotification(appName: "Finder", title: "Ana Souza", body: "Oi", subtitle: "Grupo da família"),
    NotchNotification(appName: nil, title: "Webhook", body: "deploy ok", iconEmoji: "🚀"),
    NotchNotification(appName: nil, title: "Sem origem", body: "cai no sino"),
])
```

- [ ] **Step 3: Rodar e ler**

```bash
./tools/snapshot.sh
```

Ler `Snapshots/historico-linhas.png`. Expected: ícone do Finder nas duas primeiras, 🚀 na terceira, sino na quarta; "Grupo da família · Oi" na segunda. Nenhuma área preta.

- [ ] **Step 4: Build + checks**

```bash
xcodebuild -project Knobler.xcodeproj -scheme Knobler -configuration Debug build 2>&1 | grep -E "error:|BUILD" | tail -5
./tools/check.sh
```

- [ ] **Step 5: Commit**

```bash
git add Knobler/HistoryListView.swift tools/main.swift Snapshots/historico-linhas.png
git commit -m "feat(notificações): ícone do app no histórico"
```

---

### Task 7: Docs, CHANGELOG e verificação ao vivo

**Files:**
- Modify: `docs/notifications.md` (:7-10, :105-111)
- Modify: `.claude/skills/snapshot-ui/SKILL.md` (:39-42)
- Modify: `CHANGELOG.md` (`## [Unreleased]`)
- Modify: `Knobler/Novidades/0.30.0.html`

- [ ] **Step 1: `docs/notifications.md`**

Em "O que faz", depois do parágrafo atual:

```markdown
O card mostra o app de origem (ícone e nome), o subtítulo quando o banner tem
um (nome do grupo, por exemplo) e há quanto tempo a notificação chegou. Com o
mouse em cima, o timer para e o texto abre inteiro.

O nome do app vem da descrição que o macOS dá ao banner pela Acessibilidade.
Quando o banner não diz de onde veio, o card mostra um sino e o clique não abre
nada — melhor que atribuir a notificação ao app errado.
```

Em "O que aparece em cada linha", trocar o parágrafo que começa com "Horário à esquerda" por:

```markdown
Horário, ícone do app, nome do app, título, e subtítulo e corpo truncados numa
linha. Clicar numa linha faz o mesmo que clicar no card original teria feito
(abre a URL, foca ou abre o app, revela a pasta do AirDrop) e recolhe o notch.
```

- [ ] **Step 2: Skill `snapshot-ui`**

Em `.claude/skills/snapshot-ui/SKILL.md:39-42`, trocar a entrada que diz que `NSWorkspace.icon(forFile:)` não renderiza por: o ícone renderiza normalmente em `Image(nsImage:)`; o que sai com o ícone de "proibido" é o `NSView` de `ShelfThumbnailDragView` (`imageView.image`, `ShelfThumbnailDragView.swift:92`).

- [ ] **Step 3: CHANGELOG e Novidades**

Em `CHANGELOG.md`, `## [Unreleased]`, sob `### Added`:

```markdown
- Notificações mais completas: o card mostra o subtítulo (nome do grupo, por
  exemplo) e há quanto tempo chegou; com o mouse em cima, o texto abre inteiro.
  O histórico ganhou o ícone do app em cada linha.
```

Sob `### Fixed`:

```markdown
- Toda notificação de app aparecia no notch como se fosse do WhatsApp, com o
  ícone dele, e clicar abria o WhatsApp. Agora o card mostra o app de verdade,
  ou um sino quando o banner não diz de onde veio.
```

Em `Knobler/Novidades/0.30.0.html`, acrescentar ao fim:

```html
<section class="novidade">
  <h3>Notificações com a cara do app certo</h3>
  <p>Cada notificação aparece com o ícone e o nome do app que mandou, o subtítulo
     e há quanto tempo chegou. Passe o mouse para ler o texto inteiro.
     O histórico agora mostra o ícone de cada app.</p>
</section>
```

- [ ] **Step 4: Verificação ao vivo**

Instalar o build (mesmo caminho do release local usado na sessão anterior; conferir `codesign -dvv /Applications/Knobler.app` com `Knobler Local Signing`) e pedir ao usuário uma mensagem de WhatsApp. Conferir:

1. Card com ícone e nome do WhatsApp; clique abre o WhatsApp.
2. Mensagem de grupo: subtítulo separado do corpo (se o WhatsApp mandar subtítulo).
3. Mouse em cima de uma mensagem longa: texto inteiro, card não sai da tela, some depois de tirar o mouse.
4. Histórico: a linha nova com ícone.

Se o item 1 falhar, olhar `log stream --predicate 'process == "Knobler"' | grep intercepted` e repetir o dump da Task 1.

- [ ] **Step 5: Commit**

```bash
git add docs/notifications.md .claude/skills/snapshot-ui/SKILL.md CHANGELOG.md Knobler/Novidades/0.30.0.html
git commit -m "docs(notificações): card rico, ícone no histórico"
```
