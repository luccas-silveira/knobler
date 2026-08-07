# Página de novidades — plano de implementação

> **Para agentes:** SUB-SKILL OBRIGATÓRIA — use `superpowers:subagent-driven-development`
> (recomendado) ou `superpowers:executing-plans` pra executar tarefa a tarefa. Os passos
> usam checkbox (`- [ ]`) pra acompanhamento.

**Goal:** trocar o wizard de boas-vindas por uma página HTML local que abre no
primeiro launch de cada versão nova, com texto, print, vídeo curto e tutorial de
cada novidade, e botões que agem no app.

**Arquitetura:** uma `NSWindow` com `WKWebView` carregando `shell.html` do bundle
por `loadFileURL(_:allowingReadAccessTo:)`; o Swift lê os corpos das versões
pendentes e injeta por `WKUserScript`; ações do HTML voltam por
`WKScriptMessageHandler` num enum fechado. Quais versões entram é decisão de
`NovidadesCatalogo.swift`, arquivo sem dependência que o gate compila isolado.

**Stack:** Swift 5, AppKit, WebKit, XcodeGen (`project.yml`), gates `swiftc` avulsos
em `tools/`.

**Spec:** `docs/superpowers/specs/2026-08-06-novidades-design.md`
**Dossiê:** `docs/superpowers/research/2026-08-06-novidades-research.md`

## Global Constraints

- Deployment target **macOS 14.2**. `WKScriptMessageHandlerWithReply`,
  `allowsContentJavaScript` e `WKContentRuleList` existem desde macOS 11 — sem
  `#available`.
- Comentários e strings de UI em **pt-BR**.
- **Nunca** editar `Knobler.xcodeproj` à mão: alvos e recursos vivem em
  `project.yml`, seguido de `xcodegen generate`.
- **Nunca** editar `MARKETING_VERSION` à mão nem criar tag: `tools/release.sh` é o
  único escritor.
- Check novo **tem** que entrar em `tools/check.sh`, senão a CI não o vê.
- Simplificação deliberada com teto conhecido leva comentário `// ponytail:`.
- Vocabulário fixo: **página** = a janela; **versão** = um arquivo `0.25.0.html`;
  **novidade** = uma feature demonstrada dentro de uma versão.
- Chave de UserDefaults nova: `novidades.versaoVista` (String SemVer).
- O app **não** é sandboxed (`tools/knobler.entitlements`); nenhum entitlement novo
  é necessário.

## Estrutura de arquivos

| Arquivo | Responsabilidade |
|---|---|
| `Knobler/NovidadesCatalogo.swift` (novo) | quais versões exibir, migração da chave antiga. Só `Foundation`. |
| `Knobler/NovidadesWindow.swift` (novo) | a janela, a `WKWebView` endurecida, a injeção do corpo e a ponte de ações |
| `Knobler/Novidades/` (novo, recurso) | `shell.html`, `estilo.css`, `ponte.js`, `boas-vindas.html`, `0.25.0.html`, `midia/` |
| `tools/novidadescheck.swift` (novo) | gate único: filtro de versão + varredura do HTML |
| `Knobler/KnoblerApp.swift` (modificar) | abertura, flag `--novidades`, item de menu, ações da ponte |
| `Knobler/Onboarding.swift`, `Knobler/OnboardingView.swift`, `tools/onboardingcheck.swift` | **removidos** |
| `project.yml` | `Knobler/Novidades` como folder resource |
| `tools/check.sh`, `tools/release.sh` | entrada do gate novo, abort de MINOR |

---

### Task 1: Catálogo de versões e migração

**Files:**
- Create: `Knobler/NovidadesCatalogo.swift`
- Create: `tools/novidadescheck.swift`
- Modify: `tools/check.sh:110` (troca a entrada do `onboardingcheck`)

**Interfaces:**
- Consome: `isNewer(_:than:)` e `versionComponents(_:)` de `Knobler/Updater.swift`
  (internal de propósito — `DevAvisos` já as usa).
- Produz: `enum NovidadesCatalogo` com `versoes: [String]`, `boasVindas: String`,
  `aExibir(instalada:vista:versoes:) -> [String]`,
  `versaoVista(_:) -> String?`, `marcarVisto(_:_:)`, `chaveVersao: String`.

- [ ] **Passo 1: escrever o gate que falha**

Crie `tools/novidadescheck.swift`:

```swift
// Gate da página de novidades — o filtro de versões, a migração da base
// instalada e a integridade do HTML embarcado.
//
// O erro que este check existe pra pegar é silencioso nos dois sentidos: um
// filtro errado ou nunca abre a página, ou a abre em todo launch. E uma novidade
// que aponta pra mídia inexistente só aparece como figura quebrada na tela de
// quem atualizou.
//
// Arrasta o Updater (comparação de SemVer, como o avisoscheck) e o bloco do
// plugincheck (o PluginID de verdade, pra validar data-alvo).
//
// xcrun swiftc -parse-as-library -swift-version 5 \
//   Knobler/Updater.swift Knobler/NovidadesCatalogo.swift Knobler/Plugin.swift \
//   Knobler/Pomodoro.swift Knobler/Reminders.swift Knobler/Descanso.swift \
//   Knobler/NotchSectionOrder.swift Knobler/Peer.swift Knobler/Wire.swift \
//   Knobler/LANMessaging.swift Knobler/MessageStore.swift Knobler/Permissions.swift \
//   Knobler/WebhookClient.swift Knobler/WebhookKeychainStore.swift \
//   Knobler/NotchNotification.swift Knobler/FileConverter.swift \
//   Knobler/ImageConverter.swift Knobler/DocumentConverter.swift \
//   Knobler/VideoConverter.swift tools/novidadescheck.swift \
//   -o /tmp/novidadescheck && /tmp/novidadescheck

import Foundation

@main
struct NovidadesCheck {
    static func check(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else { fatalError("novidadescheck: \(message)") }
    }

    /// Lista fixa do teste — a de produção muda, as asserções não deviam.
    static let lista = ["0.25.0", "0.26.0", "0.30.0"]

    static func main() {
        // instalação limpa: só a boas-vindas, nunca o histórico
        check(NovidadesCatalogo.aExibir(instalada: "0.30.0", vista: nil, versoes: lista)
              == [NovidadesCatalogo.boasVindas],
              "instalação limpa deve ver só a boas-vindas")

        // quem viu o wizard parcial (migração de 0/1) também só vê a boas-vindas
        check(NovidadesCatalogo.aExibir(instalada: "0.30.0", vista: "0.0.0", versoes: lista)
              == [NovidadesCatalogo.boasVindas],
              "vista 0.0.0 deve ver só a boas-vindas")

        // quem pulou versões vê todas as pendentes, mais nova primeiro
        check(NovidadesCatalogo.aExibir(instalada: "0.30.0", vista: "0.24.0", versoes: lista)
              == ["0.30.0", "0.26.0", "0.25.0"],
              "vista 0.24.0 deve ver as três, decrescente")

        // versão mais nova que a instalada não aparece (build velha, arquivo novo)
        check(NovidadesCatalogo.aExibir(instalada: "0.26.0", vista: "0.24.0", versoes: lista)
              == ["0.26.0", "0.25.0"],
              "não mostrar versão acima da instalada")

        // em dia: nada a mostrar
        check(NovidadesCatalogo.aExibir(instalada: "0.30.0", vista: "0.30.0", versoes: lista).isEmpty,
              "quem está em dia não vê nada")

        // ordem por componente, não lexicográfica
        check(NovidadesCatalogo.aExibir(instalada: "0.10.0", vista: "0.8.0",
                                        versoes: ["0.9.0", "0.10.0"]) == ["0.10.0", "0.9.0"],
              "0.10.0 é mais nova que 0.9.0")

        // --- migração da chave antiga -------------------------------------
        let limpo = UserDefaults(suiteName: "novidadescheck.limpo")!
        limpo.removePersistentDomain(forName: "novidadescheck.limpo")
        check(NovidadesCatalogo.versaoVista(limpo) == nil, "sem chave nenhuma = instalação limpa")

        let wizard = UserDefaults(suiteName: "novidadescheck.wizard")!
        wizard.removePersistentDomain(forName: "novidadescheck.wizard")
        wizard.set(2, forKey: "onboarding.versao")
        check(NovidadesCatalogo.versaoVista(wizard) == NovidadesCatalogo.versaoDoWizard,
              "quem viu o wizard inteiro migra pra versão do wizard")

        let parcial = UserDefaults(suiteName: "novidadescheck.parcial")!
        parcial.removePersistentDomain(forName: "novidadescheck.parcial")
        parcial.set(1, forKey: "onboarding.versao")
        check(NovidadesCatalogo.versaoVista(parcial) == "0.0.0", "versão 1 do wizard migra pra 0.0.0")

        let legado = UserDefaults(suiteName: "novidadescheck.legado")!
        legado.removePersistentDomain(forName: "novidadescheck.legado")
        legado.set(true, forKey: "onboarding.permissoes.apresentado")
        check(NovidadesCatalogo.versaoVista(legado) == "0.0.0", "chave legada de permissões migra pra 0.0.0")

        // a chave nova ganha da antiga
        wizard.set("0.27.0", forKey: NovidadesCatalogo.chaveVersao)
        check(NovidadesCatalogo.versaoVista(wizard) == "0.27.0", "chave nova tem precedência")

        NovidadesCatalogo.marcarVisto("0.31.0", limpo)
        check(NovidadesCatalogo.versaoVista(limpo) == "0.31.0", "marcarVisto grava a versão")

        print("novidadescheck ok")
    }
}
```

- [ ] **Passo 2: rodar o gate e ver falhar**

Exporte a lista uma vez (é a mesma do `plugincheck`, `tools/check.sh:79-84`) —
todos os comandos deste plano a reusam:

```bash
export PLUGIN_SRC="Knobler/Plugin.swift Knobler/Pomodoro.swift Knobler/Reminders.swift \
Knobler/Descanso.swift Knobler/NotchSectionOrder.swift Knobler/Peer.swift Knobler/Wire.swift \
Knobler/LANMessaging.swift Knobler/MessageStore.swift Knobler/Permissions.swift \
Knobler/WebhookClient.swift Knobler/WebhookKeychainStore.swift Knobler/NotchNotification.swift \
Knobler/FileConverter.swift Knobler/ImageConverter.swift Knobler/DocumentConverter.swift \
Knobler/VideoConverter.swift"

xcrun swiftc -parse-as-library -swift-version 5 \
  Knobler/Updater.swift Knobler/NovidadesCatalogo.swift $PLUGIN_SRC \
  tools/novidadescheck.swift -o /tmp/novidadescheck && /tmp/novidadescheck
```

Esperado: FALHA de compilação, `no such file or directory: 'Knobler/NovidadesCatalogo.swift'`.

- [ ] **Passo 3: escrever o catálogo**

Crie `Knobler/NovidadesCatalogo.swift`:

```swift
//
//  NovidadesCatalogo.swift
//  Knobler
//
//  Quais versões da página de novidades esta instalação ainda não viu. Vive num
//  arquivo sem dependência de SwiftUI nem AppSettings de propósito — assim o
//  `novidadescheck` compila o filtro isolado (mesma razão do `CalendarAviso` e
//  do `DevAvisos`).
//
//  A comparação de SemVer é a do `Updater` (`isNewer`/`versionComponents`), a
//  mesma que o `DevAvisos` usa pra faixa de versão. Uma terceira cópia no repo
//  não se justifica.
//

import Foundation

enum NovidadesCatalogo {
    /// Versões com arquivo em `Knobler/Novidades/`. Escrita à mão junto do HTML;
    /// o `novidadescheck` confere que arquivo e lista batem.
    static let versoes: [String] = ["0.25.0"]

    /// A página da primeira abertura. Não é uma versão: nunca entra na
    /// comparação de SemVer.
    static let boasVindas = "boas-vindas"

    static let chaveVersao = "novidades.versaoVista"
    /// Chaves do wizard de boas-vindas, anterior à página.
    static let chaveLegado = "onboarding.versao"
    static let chaveLegadoPermissoes = "onboarding.permissoes.apresentado"

    /// Versão em que o wizard morreu: quem o viu inteiro já conhece tudo até
    /// aqui e só deve ver o que vier depois.
    static let versaoDoWizard = "0.24.0"

    /// Versões a exibir, mais nova primeiro. Instalação limpa vê só a
    /// boas-vindas — o histórico inteiro é longo demais pra primeira impressão.
    static func aExibir(instalada: String,
                        vista: String?,
                        versoes: [String] = versoes) -> [String] {
        guard let vista, vista != "0.0.0" else { return [boasVindas] }
        return versoes
            .filter { isNewer($0, than: vista) && !isNewer($0, than: instalada) }
            .sorted { isNewer($0, than: $1) }
    }

    /// Tudo, na ordem da página: o que o item de menu e a flag `--novidades`
    /// mostram.
    static func tudo(versoes: [String] = versoes) -> [String] {
        versoes.sorted { isNewer($0, than: $1) } + [boasVindas]
    }

    /// `nil` = instalação limpa (nunca viu nada).
    static func versaoVista(_ d: UserDefaults = .standard) -> String? {
        if let versao = d.string(forKey: chaveVersao) { return versao }
        if let wizard = d.object(forKey: chaveLegado) as? Int {
            return wizard >= 2 ? versaoDoWizard : "0.0.0"
        }
        return d.bool(forKey: chaveLegadoPermissoes) ? "0.0.0" : nil
    }

    static func marcarVisto(_ versao: String, _ d: UserDefaults = .standard) {
        d.set(versao, forKey: chaveVersao)
    }
}
```

- [ ] **Passo 4: rodar o gate e ver passar**

```bash
xcrun swiftc -parse-as-library -swift-version 5 \
  Knobler/Updater.swift Knobler/NovidadesCatalogo.swift $PLUGIN_SRC \
  tools/novidadescheck.swift -o /tmp/novidadescheck && /tmp/novidadescheck
```

Esperado: `novidadescheck ok`.

- [ ] **Passo 5: registrar em `tools/check.sh`**

Troque a linha 110 (`swift_check onboardingcheck …`) por:

```bash
# arrasta o Updater (a comparação de versão da página é o isNewer/versionComponents
# dele, mesmo caminho do avisoscheck) e o bloco do plugincheck: o gate cruza o
# data-alvo do HTML contra o PluginID de verdade, não contra uma cópia.
swift_check novidadescheck        Knobler/Updater.swift Knobler/NovidadesCatalogo.swift \
  Knobler/Plugin.swift Knobler/Pomodoro.swift Knobler/Reminders.swift Knobler/Descanso.swift \
  Knobler/NotchSectionOrder.swift Knobler/Peer.swift Knobler/Wire.swift \
  Knobler/LANMessaging.swift Knobler/MessageStore.swift Knobler/Permissions.swift \
  Knobler/WebhookClient.swift Knobler/WebhookKeychainStore.swift \
  Knobler/NotchNotification.swift Knobler/FileConverter.swift Knobler/ImageConverter.swift \
  Knobler/DocumentConverter.swift Knobler/VideoConverter.swift tools/novidadescheck.swift
```

- [ ] **Passo 6: rodar a suíte**

```bash
./tools/check.sh
```

Esperado: todos ok, com `novidadescheck` no lugar de `onboardingcheck`. O
`onboardingcheck.swift` ainda existe em disco mas não é mais chamado — some na
Task 6.

- [ ] **Passo 7: commit**

```bash
git add Knobler/NovidadesCatalogo.swift tools/novidadescheck.swift tools/check.sh
git commit -m "feat(novidades): catálogo de versões e migração da chave do wizard"
```

---

### Task 2: Conteúdo estático no bundle

**Files:**
- Create: `Knobler/Novidades/shell.html`, `estilo.css`, `ponte.js`,
  `boas-vindas.html`, `midia/.gitkeep`
- Modify: `project.yml:13-18` (folder resource)
- Modify: `tools/novidadescheck.swift` (varredura do HTML)

**Interfaces:**
- Consome: `NovidadesCatalogo.boasVindas` (nome do arquivo sem extensão).
- Produz: `shell.html` com `<main id="conteudo">` vazio, que a Task 3 preenche
  via `window.KNOBLER_CORPO`; `ponte.js` expondo o listener de clique.

- [ ] **Passo 1: estender o gate com a varredura de conteúdo**

Acrescente a `tools/novidadescheck.swift`, antes do `print` final do `main()`:

```swift
        conferirConteudo()
```

E o método, dentro do `struct`:

```swift
    /// Raiz do repo: o gate roda de qualquer lugar, então sobe a partir do
    /// arquivo-fonte em vez de confiar no diretório corrente.
    static var raiz: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    }

    /// Ações que a ponte aceita. Espelha o enum de `NovidadesWindow`; o teste de
    /// que os dois não divergem é o próprio app não compilar com ação
    /// desconhecida.
    static let acoes = ["abrirAjustes", "instalarPeca", "abrirCard"]

    static func conferirConteudo() {
        let pasta = raiz.appendingPathComponent("Knobler/Novidades")
        let fm = FileManager.default
        let arquivos = (try? fm.contentsOfDirectory(atPath: pasta.path)) ?? []

        check(arquivos.contains("shell.html"), "falta shell.html")
        check(arquivos.contains("estilo.css"), "falta estilo.css")
        check(arquivos.contains("ponte.js"), "falta ponte.js")
        check(arquivos.contains("\(NovidadesCatalogo.boasVindas).html"),
              "falta \(NovidadesCatalogo.boasVindas).html")

        let shell = (try? String(contentsOf: pasta.appendingPathComponent("shell.html"),
                                 encoding: .utf8)) ?? ""
        check(shell.contains("id=\"conteudo\""),
              "shell.html precisa do container id=\"conteudo\" — é onde o corpo é injetado")

        // toda versão da lista tem arquivo, e todo arquivo de versão está na lista
        let deDisco = arquivos
            .filter { $0.hasSuffix(".html") && $0 != "shell.html"
                      && $0 != "\(NovidadesCatalogo.boasVindas).html" }
            .map { String($0.dropLast(5)) }
            .sorted()
        check(deDisco == NovidadesCatalogo.versoes.sorted(),
              "versoes do catálogo (\(NovidadesCatalogo.versoes.sorted())) != arquivos em disco (\(deDisco))")

        for versao in deDisco {
            check(versionComponents(versao) != nil, "nome de arquivo não é SemVer: \(versao).html")
        }

        let midia = Set((try? fm.contentsOfDirectory(atPath: pasta.appendingPathComponent("midia").path)) ?? [])

        for nome in deDisco.map({ "\($0).html" }) + ["\(NovidadesCatalogo.boasVindas).html"] {
            let html = (try? String(contentsOf: pasta.appendingPathComponent(nome),
                                    encoding: .utf8)) ?? ""
            check(!html.contains("<html"), "\(nome) deve conter só o corpo, sem <html>")
            check(!html.contains("<style"), "\(nome) não deve trazer <style> — o estilo é do estilo.css")

            for src in valores(de: "src", em: html) {
                check(src.hasPrefix("midia/"), "\(nome): src fora de midia/: \(src)")
                check(midia.contains(String(src.dropFirst("midia/".count))),
                      "\(nome): mídia inexistente: \(src)")
            }
            for acao in valores(de: "data-acao", em: html) {
                check(acoes.contains(acao), "\(nome): ação desconhecida: \(acao)")
            }
            if html.contains("data-acao=\"instalarPeca\"") {
                for alvo in valores(de: "data-alvo", em: html) where !alvo.isEmpty {
                    // ponytail: o gate não distingue qual data-alvo pertence a
                    // qual data-acao — aceita alvo válido pra qualquer uma das
                    // duas listas. Refinar se um alvo errado escapar.
                    check(pecas.contains(alvo) || paineis.contains(alvo),
                          "\(nome): alvo desconhecido: \(alvo)")
                }
            }
        }
    }

    /// As peças vêm do `PluginID` de verdade (`Plugin.swift`), que o gate
    /// compila junto — é o que faz renomear um caso lá quebrar aqui.
    static let pecas = PluginID.allCases.map(\.rawValue)
    /// Painéis são cópia: `SettingsPane` mora em `SettingsView.swift`, que
    /// arrasta SwiftUI e meia janela de Ajustes pro compile.
    /// ponytail: cópia de 11 strings; o custo de errar é um botão que não abre
    /// painel, e a flag `--ajustes=<painel>` já exercita a lista real.
    static let paineis = ["geral", "notch", "desenho", "ditado", "pomodoro", "lembretes",
                          "descanso", "webhooks", "mensagens", "plugins", "permissoes"]

    /// Valores de um atributo HTML, sem parser: os arquivos são nossos e o
    /// vocabulário é fechado.
    static func valores(de atributo: String, em html: String) -> [String] {
        var saida: [String] = []
        var resto = Substring(html)
        while let inicio = resto.range(of: "\(atributo)=\"") {
            resto = resto[inicio.upperBound...]
            guard let fim = resto.firstIndex(of: "\"") else { break }
            saida.append(String(resto[..<fim]))
            resto = resto[fim...]
        }
        return saida
    }
```

- [ ] **Passo 2: rodar e ver falhar**

```bash
xcrun swiftc -parse-as-library -swift-version 5 \
  Knobler/Updater.swift Knobler/NovidadesCatalogo.swift $PLUGIN_SRC \
  tools/novidadescheck.swift -o /tmp/novidadescheck && /tmp/novidadescheck
```

Esperado: `Fatal error: novidadescheck: falta shell.html`.

- [ ] **Passo 3: escrever o shell**

`Knobler/Novidades/shell.html`:

```html
<!DOCTYPE html>
<html lang="pt-BR">
<head>
  <meta charset="utf-8">
  <title>Novidades do Knobler</title>
  <link rel="stylesheet" href="estilo.css">
</head>
<body>
  <header>
    <h1>Novidades</h1>
    <p class="sub">O que mudou no Knobler desde a sua última versão.</p>
  </header>
  <main id="conteudo"></main>
  <footer>
    <p>Documentação completa em <code>docs/</code> do repositório.</p>
  </footer>
</body>
</html>
```

- [ ] **Passo 4: escrever o estilo**

`Knobler/Novidades/estilo.css`:

```css
/* A página de novidades. Modo escuro por prefers-color-scheme: a janela segue
   a aparência do sistema, como o resto do app. */
:root {
  color-scheme: light dark;
  --fundo: #ffffff;
  --texto: #1c1c1e;
  --secundario: #6e6e73;
  --linha: rgba(0, 0, 0, 0.1);
  --destaque: #0a84ff;
}
@media (prefers-color-scheme: dark) {
  :root {
    --fundo: #1c1c1e;
    --texto: #f5f5f7;
    --secundario: #98989d;
    --linha: rgba(255, 255, 255, 0.12);
  }
}
* { box-sizing: border-box; }
body {
  margin: 0;
  padding: 0 40px 48px;
  background: var(--fundo);
  color: var(--texto);
  font: 15px/1.55 -apple-system, BlinkMacSystemFont, "SF Pro Text", sans-serif;
  -webkit-user-select: text;
}
header { padding: 40px 0 24px; }
h1 { margin: 0; font-size: 34px; font-weight: 600; letter-spacing: -0.02em; }
.sub { margin: 6px 0 0; color: var(--secundario); }
.versao { border-top: 1px solid var(--linha); padding-top: 28px; margin-top: 28px; }
.versao > h2 {
  font-size: 12px; font-weight: 600; letter-spacing: 0.08em;
  text-transform: uppercase; color: var(--secundario); margin: 0 0 20px;
}
.novidade { margin: 0 0 40px; }
.novidade h3 { font-size: 22px; font-weight: 600; margin: 0 0 8px; letter-spacing: -0.01em; }
.novidade p { margin: 0 0 16px; }
figure { margin: 0 0 16px; }
figure img, figure video {
  width: 100%; height: auto; display: block;
  border: 1px solid var(--linha); border-radius: 10px;
}
figcaption { margin-top: 8px; font-size: 13px; color: var(--secundario); }
ol.tutorial { margin: 0 0 16px; padding-left: 22px; }
ol.tutorial li { margin-bottom: 6px; }
button {
  font: inherit; font-weight: 500; color: #fff; background: var(--destaque);
  border: 0; border-radius: 7px; padding: 7px 14px; cursor: pointer;
}
button:active { filter: brightness(0.9); }
footer { border-top: 1px solid var(--linha); padding-top: 20px; color: var(--secundario); font-size: 13px; }
code { font-family: "SF Mono", ui-monospace, monospace; font-size: 13px; }
```

- [ ] **Passo 5: escrever a ponte**

`Knobler/Novidades/ponte.js`:

```js
// Injetado como WKUserScript (.atDocumentEnd) pelo NovidadesWindow. O Swift
// define window.KNOBLER_CORPO antes deste script rodar.
(function () {
  var alvo = document.getElementById("conteudo");
  if (alvo && typeof window.KNOBLER_CORPO === "string") {
    alvo.innerHTML = window.KNOBLER_CORPO;
  }
  // Delegação: o corpo é injetado depois do parse, então listener por botão
  // não pegaria. Um listener no documento pega todos, inclusive os futuros.
  document.addEventListener("click", function (e) {
    var botao = e.target.closest("button[data-acao]");
    if (!botao) return;
    window.webkit.messageHandlers.app.postMessage({
      acao: botao.getAttribute("data-acao"),
      alvo: botao.getAttribute("data-alvo") || ""
    });
  });
})();
```

- [ ] **Passo 6: escrever a boas-vindas**

`Knobler/Novidades/boas-vindas.html` — os dois passos do wizard atual, agora com
lugar pra print:

```html
<section class="versao">
  <h2>Bem-vindo</h2>

  <section class="novidade">
    <h3>O Knobler mora no notch</h3>
    <p>Passe o cursor sobre o notch pra abrir o card: música, Pomodoro,
       notificações e a prateleira de arquivos ficam ali. Não há ícone no Dock
       nem janela principal — o app roda em segundo plano.</p>
    <figure>
      <img src="midia/boas-vindas-card.png" alt="O card aberto no notch, com a música tocando">
      <figcaption>O card abre com o cursor sobre o notch.</figcaption>
    </figure>
  </section>

  <section class="novidade">
    <h3>Tudo mora no ícone da barra de menus</h3>
    <p>Ajustes, nota rápida, seletor de cor e esta página saem do <strong>◐</strong>
       no topo da tela. É por ali que você chega em tudo que não está no card.</p>
    <button data-acao="abrirAjustes" data-alvo="geral">Abrir os Ajustes</button>
  </section>

  <section class="novidade">
    <h3>Dois atalhos globais</h3>
    <p>Segure a tecla <strong>⌥ direita</strong> pra ditar: fale, solte, e o texto
       aparece onde o cursor está. Um toque no <strong>Control esquerdo</strong>
       desenha por cima da tela; Esc para de desenhar.</p>
    <ol class="tutorial">
      <li>Segure ⌥ direita e fale uma frase.</li>
      <li>Solte a tecla e espere a transcrição.</li>
      <li>O texto entra no campo onde o cursor estava.</li>
    </ol>
    <button data-acao="abrirAjustes" data-alvo="ditado">Ajustes do ditado</button>
  </section>
</section>
```

- [ ] **Passo 7: a mídia da boas-vindas**

O print do card já existe nos docs. Copie (não use symlink — bundle assinado não
aceita):

```bash
mkdir -p Knobler/Novidades/midia
cp docs/images/music-expanded.png Knobler/Novidades/midia/boas-vindas-card.png
```

- [ ] **Passo 8: rodar o gate e ver passar**

```bash
xcrun swiftc -parse-as-library -swift-version 5 \
  Knobler/Updater.swift Knobler/NovidadesCatalogo.swift $PLUGIN_SRC \
  tools/novidadescheck.swift -o /tmp/novidadescheck && /tmp/novidadescheck
```

Esperado: falha em `versoes do catálogo (["0.25.0"]) != arquivos em disco ([])` —
a versão 0.25.0 só é escrita na Task 7. Ajuste temporariamente
`NovidadesCatalogo.versoes` para `[]` e rode de novo; esperado `novidadescheck ok`.
Deixe `versoes = []` até a Task 7.

- [ ] **Passo 9: embarcar a pasta no app**

Em `project.yml`, dentro de `targets.Knobler.sources`, acrescente **antes** da
entrada do `Vendor/`:

```yaml
      # a página de novidades: folder reference (type: folder) pra preservar
      # midia/ dentro do bundle — os src do HTML são relativos.
      - path: Knobler/Novidades
        type: folder
        buildPhase: resources
```

E na entrada `- Knobler` acima, troque por:

```yaml
      # Includes AgentRequestModels.swift and AgentRequestStore.swift.
      - path: Knobler
        excludes:
          - Novidades/**
```

Depois:

```bash
xcodegen generate
xcodebuild -project Knobler.xcodeproj -scheme Knobler -configuration Debug build
```

Esperado: build ok. Confirme que a pasta foi copiada:

```bash
ls build/dd/Build/Products/Debug/Knobler.app/Contents/Resources/Novidades/midia/
```

Esperado: `boas-vindas-card.png`.

- [ ] **Passo 10: commit**

```bash
git add Knobler/Novidades project.yml tools/novidadescheck.swift
git commit -m "feat(novidades): shell HTML, estilo, ponte e página de boas-vindas"
```

---

### Task 3: A janela e a WKWebView endurecida

**Files:**
- Create: `Knobler/NovidadesWindow.swift`
- Modify: `tools/snapshot.sh` — **não**; a janela fica fora do harness (WKWebView
  não renderiza offscreen)

**Interfaces:**
- Consome: `NovidadesCatalogo.aExibir(instalada:vista:)`, `.tudo()`,
  `.versaoVista(_:)`, `.marcarVisto(_:_:)`.
- Produz: `final class NovidadesWindow` com
  `init(paginas: [String], aoFechar: @escaping () -> Void)` e `func mostrar()`;
  e o protocolo `NovidadesAcoes` que a Task 4 implementa no `AppDelegate`.

- [ ] **Passo 1: escrever a janela**

Crie `Knobler/NovidadesWindow.swift`:

```swift
//
//  NovidadesWindow.swift
//  Knobler
//
//  A página de novidades: uma NSWindow com uma WKWebView que carrega o
//  `shell.html` do bundle e recebe o corpo das versões pendentes por
//  WKUserScript. Quais versões entram é decisão do `NovidadesCatalogo`.
//
//  Por que HTML e não SwiftUI: figura com legenda, vídeo em loop, passo
//  numerado e botão de ação são baratos em CSS e caros em SwiftUI, e este
//  conteúdo muda a cada release enquanto a moldura não muda nunca.
//
//  O endurecimento segue o Sparkle (SUWKWebView.m), que resolve o mesmo
//  problema há anos — com uma diferença: lá o JavaScript do documento nasce
//  desligado porque o HTML vem de um feed remoto. Aqui o HTML é do bundle
//  assinado e a página precisa de listener de clique, então o que protege é o
//  content rule list (o documento não fala com a rede) e a allowlist de
//  navegação, não desligar JS.
//

import AppKit
import WebKit

/// O que a página pode pedir ao app. Enum fechado: string que não casa é
/// ignorada, nunca vira chamada.
enum NovidadeAcao {
    case abrirAjustes(String)
    case instalarPeca(String)
    case abrirCard

    init?(acao: String, alvo: String) {
        switch acao {
        case "abrirAjustes": self = .abrirAjustes(alvo)
        case "instalarPeca": self = .instalarPeca(alvo)
        case "abrirCard": self = .abrirCard
        default: return nil
        }
    }
}

@MainActor
protocol NovidadesAcoes: AnyObject {
    func executar(_ acao: NovidadeAcao)
}

@MainActor
final class NovidadesWindow: NSObject {
    private var window: NSWindow?
    private var webView: WKWebView?
    private var observer: NSObjectProtocol?

    private let paginas: [String]
    private let aoFechar: () -> Void
    private weak var acoes: NovidadesAcoes?

    /// Nome do handler; o `ponte.js` fala com `webkit.messageHandlers.app`.
    private static let handler = "app"

    /// - Parameters:
    ///   - paginas: nomes de arquivo sem extensão, na ordem de exibição.
    ///   - aoFechar: roda uma vez, no fechamento. É onde a versão vista é gravada.
    init(paginas: [String], acoes: NovidadesAcoes?, aoFechar: @escaping () -> Void) {
        self.paginas = paginas
        self.acoes = acoes
        self.aoFechar = aoFechar
    }

    private static var pasta: URL? {
        Bundle.main.url(forResource: "Novidades", withExtension: nil)
    }

    /// Corpos das páginas, concatenados. Página que sumiu do bundle é pulada em
    /// silêncio: uma figura a menos é melhor que uma janela vazia.
    private func corpo() -> String {
        guard let pasta = Self.pasta else { return "" }
        return paginas.compactMap { nome in
            let url = pasta.appendingPathComponent("\(nome).html")
            guard let html = try? String(contentsOf: url, encoding: .utf8) else { return nil }
            // A boas-vindas traz o próprio cabeçalho; versão ganha o dela.
            guard nome != NovidadesCatalogo.boasVindas else { return html }
            return "<section class=\"versao\"><h2>Versão \(nome)</h2>\(html)</section>"
        }.joined()
    }

    /// O corpo entra como literal JSON — que é literal JS válido — em vez de
    /// concatenação de string: aspas e barras invertidas do HTML não escapam
    /// pro código.
    private func scriptDeInjecao() -> WKUserScript? {
        guard let pasta = Self.pasta,
              let ponte = try? String(contentsOf: pasta.appendingPathComponent("ponte.js"),
                                      encoding: .utf8),
              let literal = try? JSONEncoder().encode(corpo()),
              let corpoJS = String(data: literal, encoding: .utf8)
        else { return nil }
        return WKUserScript(source: "window.KNOBLER_CORPO = \(corpoJS);\n\(ponte)",
                            injectionTime: .atDocumentEnd,
                            forMainFrameOnly: true)
    }

    func mostrar() {
        if window == nil { montar() }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func montar() {
        let config = WKWebViewConfiguration()
        config.mediaTypesRequiringUserActionForPlayback = []
        config.preferences.javaScriptCanOpenWindowsAutomatically = false
        config.defaultWebpagePreferences.allowsContentJavaScript = true
        if let script = scriptDeInjecao() {
            config.userContentController.addUserScript(script)
        }
        config.userContentController.add(self, name: Self.handler)

        let web = WKWebView(frame: .zero, configuration: config)
        web.navigationDelegate = self
        web.allowsBackForwardNavigationGestures = false
        webView = web
        aplicarBloqueioDeRede(em: web)

        if let pasta = Self.pasta {
            web.loadFileURL(pasta.appendingPathComponent("shell.html"),
                            allowingReadAccessTo: pasta)
        }

        let window = NSWindow(contentRect: .zero,
                              styleMask: [.titled, .closable],
                              backing: .buffered,
                              defer: false)
        window.title = "Novidades do Knobler"
        window.contentView = web
        window.isReleasedWhenClosed = false
        window.setContentSize(NSSize(width: 820, height: 620))
        window.center()
        self.window = window

        // Nenhuma janela do projeto tem delegate: o X e o Esc caem todos aqui.
        observer = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification, object: window, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.desmontar() }
        }
    }

    /// A WKWebView morre com a janela. O WKUserContentController retém o
    /// handler forte — sem o remove aqui, o ciclo vaza e reabrir a janela com o
    /// mesmo nome de handler é erro, não warning.
    private func desmontar() {
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
        webView?.configuration.userContentController
            .removeScriptMessageHandler(forName: Self.handler)
        webView?.navigationDelegate = nil
        webView = nil
        window = nil
        aoFechar()
    }

    /// Bloqueia toda requisição de rede do documento. Mais forte que CSP: não
    /// depende de o HTML cooperar. A página é 100% local; se algum dia um
    /// `<img>` apontar pra fora, ele simplesmente não carrega.
    private func aplicarBloqueioDeRede(em web: WKWebView) {
        let regra = #"[{"trigger":{"url-filter":".*"},"action":{"type":"block"}}]"#
        WKContentRuleListStore.default()?.compileContentRuleList(
            forIdentifier: "novidades-sem-rede", encodedContentRuleList: regra
        ) { lista, _ in
            guard let lista else { return }
            MainActor.assumeIsolated {
                web.configuration.userContentController.add(lista)
            }
        }
    }
}

extension NovidadesWindow: WKScriptMessageHandler {
    nonisolated func userContentController(_ controller: WKUserContentController,
                                           didReceive message: WKScriptMessage) {
        guard let corpo = message.body as? [String: Any],
              let acao = corpo["acao"] as? String else { return }
        let alvo = corpo["alvo"] as? String ?? ""
        MainActor.assumeIsolated {
            guard let acao = NovidadeAcao(acao: acao, alvo: alvo) else { return }
            acoes?.executar(acao)
        }
    }
}

extension NovidadesWindow: WKNavigationDelegate {
    nonisolated func webView(_ webView: WKWebView,
                             decidePolicyFor action: WKNavigationAction,
                             decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        let url = action.request.url
        // A carga inicial do shell é a única navegação de arquivo permitida;
        // depois dela, file:// é recusado como qualquer outro esquema.
        if action.navigationType == .other, url?.isFileURL == true {
            decisionHandler(.allow); return
        }
        if let url, url.scheme == "https" || url.scheme == "http" {
            NSWorkspace.shared.open(url)
        }
        decisionHandler(.cancel)
    }
}
```

- [ ] **Passo 2: compilar**

```bash
xcodegen generate
xcodebuild -project Knobler.xcodeproj -scheme Knobler -configuration Debug build
```

Esperado: build ok. (A janela ainda não é aberta por ninguém — a integração é a
Task 5.)

- [ ] **Passo 3: commit**

```bash
git add Knobler/NovidadesWindow.swift
git commit -m "feat(novidades): janela com WKWebView local endurecida"
```

---

### Task 4: A ponte de ações no AppDelegate

**Files:**
- Modify: `Knobler/KnoblerApp.swift` — `showSettings` deixa de ser `private`;
  conformidade a `NovidadesAcoes`

**Interfaces:**
- Consome: `NovidadeAcao`, `NovidadesAcoes` (Task 3), `PluginHost.instalar(_:)`
  (`Plugin.swift:487`), `viewModelPrincipal()` (`KnoblerApp.swift:1079`),
  `SettingsPane(rawValue:)` (`SettingsView.swift:16`).
- Produz: `AppDelegate.executar(_ acao: NovidadeAcao)`.

- [ ] **Passo 1: tornar `showSettings` acessível**

Em `Knobler/KnoblerApp.swift:1562`, troque:

```swift
    private func showSettings(pane: SettingsPane?) {
```

por:

```swift
    /// Não é `private` porque a página de novidades abre painel pela ponte
    /// (`executar(_:)`), no mesmo caminho da flag `--ajustes=`.
    func showSettings(pane: SettingsPane?) {
```

- [ ] **Passo 2: implementar as ações**

Acrescente, logo depois de `openOnboarding()` (`KnoblerApp.swift:787-789`):

```swift
    /// As ações que a página de novidades pode pedir. Enum fechado do lado do
    /// Swift (`NovidadeAcao`), lista validada pelo `novidadescheck` do lado do
    /// HTML: string desconhecida morre antes de chegar aqui.
    func executar(_ acao: NovidadeAcao) {
        switch acao {
        case .abrirAjustes(let painel):
            showSettings(pane: SettingsPane(rawValue: painel))
        case .instalarPeca(let id):
            guard let peca = PluginID(rawValue: id) else { return }
            plugins.instalar(peca)
        case .abrirCard:
            viewModelPrincipal()?.setExpandedDirect(true)
        }
    }
```

E na declaração da classe, acrescente a conformidade:

```swift
extension AppDelegate: NovidadesAcoes {}
```

(coloque a extension logo abaixo da classe, junto das outras extensions do
arquivo).

- [ ] **Passo 3: compilar**

```bash
xcodebuild -project Knobler.xcodeproj -scheme Knobler -configuration Debug build
```

Esperado: build ok.

- [ ] **Passo 4: commit**

```bash
git add Knobler/KnoblerApp.swift
git commit -m "feat(novidades): ponte de ações da página pro app"
```

---

### Task 5: Integração — abertura, flag e menu

**Files:**
- Modify: `Knobler/KnoblerApp.swift:701-712` (flags), `:722-789` (abertura),
  `:1370-1372` (menu)

**Interfaces:**
- Consome: `NovidadesWindow` (Task 3), `executar(_:)` (Task 4),
  `NovidadesCatalogo` (Task 1), `Updater.installedVersion`
  (`Updater.swift:140-143`).
- Produz: `AppDelegate.mostrarNovidades(paginas:gravando:depoisPermissoes:)` e
  `@objc openNovidades()`.

- [ ] **Passo 1: trocar o bloco de abertura**

Substitua `apresentarBoasVindasSeNecessario()`, `mostrarBoasVindas(...)` e
`openOnboarding()` (`KnoblerApp.swift:722-789`) por:

```swift
    /// O app é LSUIElement: sem janela e sem ícone no Dock, quem instala não tem
    /// onde procurar nem o app nem as permissões. A página de novidades conta
    /// isso na primeira abertura e, a cada versão nova, mostra o que chegou.
    private func apresentarNovidadesSeNecessario() {
        // Saúde da instalação é problema de agora, não novidade: vai direto pro
        // painel, sem passar pela página nem pelo versionamento.
        if Permission.installIssue != nil {
            showSettings(pane: .permissoes)
            return
        }
        let vista = NovidadesCatalogo.versaoVista()
        let paginas = NovidadesCatalogo.aExibir(instalada: updater.installedVersion,
                                                vista: vista)
        guard !paginas.isEmpty else { return }
        // Permissões só na primeira execução de verdade: quem está vendo uma
        // versão nova já passou por esse painel.
        mostrarNovidades(paginas: paginas, gravando: true, depoisPermissoes: vista == nil)
    }

    private var novidadesWindow: NovidadesWindow?

    private func mostrarNovidades(paginas: [String],
                                  gravando: Bool,
                                  depoisPermissoes: Bool = false) {
        let versao = updater.installedVersion
        let janela = NovidadesWindow(paginas: paginas, acoes: self) { [weak self] in
            guard let self else { return }
            self.novidadesWindow = nil
            // No modo de captura (--novidades) e na releitura pelo menu, tirar
            // print ou reler não pode queimar o estado da máquina.
            guard gravando else { return }
            NovidadesCatalogo.marcarVisto(versao)
            if depoisPermissoes { self.showSettings(pane: .permissoes) }
        }
        novidadesWindow = janela
        janela.mostrar()
    }

    /// Porta de volta: quem pede de propósito quer ver tudo — e reler não grava
    /// nada, ao contrário do wizard que isto substitui.
    @objc private func openNovidades() {
        mostrarNovidades(paginas: NovidadesCatalogo.tudo(), gravando: false)
    }
```

- [ ] **Passo 2: trocar o bloco de flags**

Em `KnoblerApp.swift:707-712`, troque:

```swift
        } else if CommandLine.arguments.contains("--boas-vindas") {
            // modo de captura: mostra tudo e não grava nada
            mostrarBoasVindas(paraVersao: 0, gravando: false)
        } else {
            apresentarBoasVindasSeNecessario()
        }
```

por:

```swift
        } else if CommandLine.arguments.contains("--novidades") {
            // modo de captura: mostra tudo e não grava nada
            mostrarNovidades(paginas: NovidadesCatalogo.tudo(), gravando: false)
        } else {
            apresentarNovidadesSeNecessario()
        }
```

- [ ] **Passo 3: trocar o item de menu**

Em `KnoblerApp.swift:1370-1372`, troque:

```swift
        let boasVindas = menu.addItem(
            withTitle: "Boas-vindas…", action: #selector(openOnboarding), keyEquivalent: "")
        boasVindas.target = self
```

por:

```swift
        let novidades = menu.addItem(
            withTitle: "Novidades…", action: #selector(openNovidades), keyEquivalent: "")
        novidades.target = self
```

- [ ] **Passo 4: apagar o wizard**

```bash
git rm Knobler/Onboarding.swift Knobler/OnboardingView.swift tools/onboardingcheck.swift
xcodegen generate
xcodebuild -project Knobler.xcodeproj -scheme Knobler -configuration Debug build
```

Esperado: build ok, sem referência pendente a `Onboarding`.

- [ ] **Passo 5: conferir a suíte**

```bash
./tools/check.sh
```

Esperado: todos ok. Se algum gate reclamar de `Onboarding`, é referência
esquecida — corrija antes de seguir.

- [ ] **Passo 6: ver a janela de verdade**

```bash
./build/dd/Build/Products/Debug/Knobler.app/Contents/MacOS/Knobler --novidades
```

Esperado: a janela abre com a página de boas-vindas, o print carrega, e o botão
"Abrir os Ajustes" abre o painel Geral. Feche e confirme que
`defaults read com.zoi.knobler novidades.versaoVista` continua **ausente** (o
modo de captura não grava).

- [ ] **Passo 7: commit**

```bash
git add -A Knobler tools
git commit -m "feat(novidades): página substitui o wizard de boas-vindas"
```

---

### Task 6: Gate de release e regra de processo

**Files:**
- Modify: `tools/release.sh` (depois da validação de versão, `:59-78`)
- Modify: `VERSIONING.md`, `CLAUDE.md`

**Interfaces:**
- Consome: `$VER` e `$INPUT` já resolvidos por `release.sh`.
- Produz: abort com mensagem quando falta a página numa MINOR.

- [ ] **Passo 1: acrescentar o abort**

Em `tools/release.sh`, logo depois do bloco `if [ -n "$LAST_VER" ] && ! ver_gt …`
(linha ~78), acrescente:

```bash
# --- página de novidades (obrigatória em MINOR) ------------------------------
# Feature sem página é feature que ninguém descobre. Fix (PATCH) não precisa.
NOVIDADE="Knobler/Novidades/$VER.html"
NEW_MI="${VER#*.}"; NEW_MI="${NEW_MI%%.*}"
OLD_MI="${LAST_VER#*.}"; OLD_MI="${OLD_MI%%.*}"
if [ "$NEW_MI" != "$OLD_MI" ] && [ ! -f "$NOVIDADE" ]; then
  echo "release MINOR sem página de novidades: crie $NOVIDADE e acrescente \"$VER\" a NovidadesCatalogo.versoes." >&2
  exit 2
fi
```

- [ ] **Passo 2: provar que aborta**

```bash
./tools/release.sh --dry-run minor
```

Esperado: `release MINOR sem página de novidades: crie Knobler/Novidades/0.25.0.html …`
e código de saída 2. (Se o `--dry-run` do script usar outra sintaxe, leia o
cabeçalho de `tools/release.sh` e use a de lá.)

- [ ] **Passo 3: provar que PATCH passa**

```bash
./tools/release.sh --dry-run patch
```

Esperado: não reclama da página (pode reclamar de `## [Unreleased]` vazio, o que
é outro guard e está correto).

- [ ] **Passo 4: escrever a regra**

Em `VERSIONING.md`, na seção do fluxo de release, acrescente:

```markdown
**MINOR exige página de novidades.** Toda feature escreve a novidade em
`Knobler/Novidades/<versão>.html` junto da entrada do `CHANGELOG.md`, enquanto
desenvolve — não no fim do ciclo. `tools/release.sh minor` aborta sem o arquivo;
`patch` passa sem. Ver `docs/novidades.md`.
```

Em `CLAUDE.md`, na seção **Versionamento**, acrescente uma linha:

```markdown
Feature nova escreve a novidade em `Knobler/Novidades/<versão>.html` junto da
entrada do CHANGELOG (o `release.sh minor` aborta sem ela) e acrescenta a versão
a `NovidadesCatalogo.versoes`.
```

- [ ] **Passo 5: commit**

```bash
git add tools/release.sh VERSIONING.md CLAUDE.md
git commit -m "feat(release): MINOR exige página de novidades"
```

---

### Task 7: A primeira versão com página

**Files:**
- Create: `Knobler/Novidades/0.25.0.html`, mídia em `Knobler/Novidades/midia/`
- Modify: `Knobler/NovidadesCatalogo.swift` (`versoes`)
- Modify: `CHANGELOG.md` (`## [Unreleased]`)

**Interfaces:**
- Consome: o vocabulário HTML da Task 2 e as ações da Task 4.
- Produz: a primeira versão exibível, que é a própria página de novidades.

Decisão registrada: a 0.24 já saiu, e reescrever novidade retroativa pras onze
peças é trabalho sem leitor — quem está na 0.24 vai receber a 0.25 e ver a página
dela. A primeira versão a ganhar arquivo é a que traz esta feature.

- [ ] **Passo 1: gravar o vídeo da própria página**

Com a build Debug rodando `--novidades`, grave 4 s de tela mostrando a rolagem e
um clique num botão de ação:

```bash
# grave com QuickTime ou screencapture -v, recorte pra janela, e converta:
ffmpeg -i bruto.mov -t 4 -an -vcodec libx264 -pix_fmt yuv420p -crf 28 \
  -vf "scale=1280:-2" Knobler/Novidades/midia/novidades.mp4
```

Se `ffmpeg` não estiver instalado (`brew install ffmpeg`), use um PNG no lugar do
vídeo e ajuste o HTML abaixo — o gate aceita os dois.

- [ ] **Passo 2: escrever a versão**

`Knobler/Novidades/0.25.0.html`:

```html
<section class="novidade">
  <h3>Esta página</h3>
  <p>A partir de agora, toda versão nova do Knobler abre uma página como esta na
     primeira vez que o app roda — com print, vídeo e o passo a passo de cada
     novidade. Ela substitui a antiga janela de boas-vindas, que era só texto.</p>
  <figure>
    <video src="midia/novidades.mp4" autoplay loop muted playsinline></video>
    <figcaption>A página abre sozinha uma vez por versão.</figcaption>
  </figure>
  <ol class="tutorial">
    <li>Ela aparece sozinha no primeiro launch depois de cada atualização.</li>
    <li>Fecha no X ou no Esc, e não volta a aparecer naquela versão.</li>
    <li>Pra reler quando quiser: <strong>◐</strong> na barra de menus →
        <strong>Novidades…</strong> — reler não marca nada como visto.</li>
  </ol>
  <p>Se você pulou versões, a página traz todas as que faltavam, da mais nova pra
     mais antiga.</p>
</section>
```

- [ ] **Passo 3: registrar a versão no catálogo**

Em `Knobler/NovidadesCatalogo.swift`, devolva `versoes` ao valor final:

```swift
    static let versoes: [String] = ["0.25.0"]
```

- [ ] **Passo 4: rodar o gate**

```bash
./tools/check.sh
```

Esperado: `novidadescheck ok` — lista e arquivos batem, mídia existe.

- [ ] **Passo 5: escrever o CHANGELOG**

Em `CHANGELOG.md`, sob `## [Unreleased]`:

```markdown
### Added
- **Página de novidades**: toda versão nova abre uma página com texto, print,
  vídeo e tutorial do que chegou (`Knobler/Novidades/<versão>.html`, renderizada
  num `WKWebView` local). Pula versões sem perder nada: quem estava na 0.24 e vai
  pra 0.27 vê as três. Reabre em **◐ → Novidades…** sem marcar nada como visto.

### Removed
- A janela de boas-vindas em SwiftUI (`Onboarding.swift`, `OnboardingView.swift`)
  e o versionamento por passo. A primeira abertura agora é a página de
  boas-vindas, com print. Quem já tinha visto o wizard não revê nada.
```

- [ ] **Passo 6: commit**

```bash
git add Knobler/Novidades Knobler/NovidadesCatalogo.swift CHANGELOG.md
git commit -m "feat(novidades): página da 0.25.0"
```

---

### Task 8: Documentação

**Files:**
- Create: `docs/novidades.md` (de `docs/onboarding.md`, via `git mv`)
- Modify: `docs/index.md:30`, `docs/settings.md:110,121`,
  `docs/calendar-countdown.md:34`, `docs/troubleshooting.md:88`,
  `docs/architecture.md:34,96`, `README.md:79,164`, `CLAUDE.md:140-142`
- Modify: `docs/images/` — `boas-vindas-1.png`/`-2.png` saem

- [ ] **Passo 1: renomear e reescrever o doc**

```bash
git mv docs/onboarding.md docs/novidades.md
```

Reescreva `docs/novidades.md` cobrindo, nesta ordem: o que a página faz; quando
abre (primeiro launch de versão nova, ativando o app; **◐ → Novidades…** sem
gravar; `--novidades` pra captura); o que acontece com quem pulou versões; que a
primeira abertura encadeia o painel Permissões; e a receita de captura num
comentário HTML:

```markdown
<!-- Captura: WKWebView não renderiza no tools/snapshot.sh, então a imagem é
     manual. Build Release, rodar de ~/Applications (de /tmp o installIssue
     manda pro painel Permissões e a página nem abre), `Knobler --novidades`,
     achar o windowID em CGWindowListCopyWindowInfo e `screencapture -o -l<id>`. -->
```

- [ ] **Passo 2: consertar os links**

```bash
grep -rn "onboarding.md\|boas-vindas" docs/ README.md CLAUDE.md
```

Atualize cada ocorrência: `docs/index.md:30` (link e descrição), `docs/settings.md`
(dois links), `docs/calendar-countdown.md`, `docs/troubleshooting.md`,
`README.md:79` (o bloco descreve "versionada por passo" — agora é por release) e
`README.md:164`.

- [ ] **Passo 3: consertar a arquitetura**

Em `docs/architecture.md:33-39`, o fluxo de launch cita a janela de boas-vindas:
troque por "a página de novidades". Em `:96`, a linha da tabela de ownership
(`Passos de boas-vindas já vistos | Onboarding | OnboardingView, AppDelegate`)
vira:

```markdown
| Versão de novidades já vista | `NovidadesCatalogo` (sem dependências, por isso testável isolado) | `NovidadesWindow`, `AppDelegate` |
```

- [ ] **Passo 4: consertar o CLAUDE.md**

Em `CLAUDE.md:140-142`, a receita `--boas-vindas` vira `--novidades`, e
acrescente `NovidadesWindow` à lista de views que não renderizam no harness
(`WKWebView`, junto da seção Link).

- [ ] **Passo 5: trocar as imagens**

```bash
git rm docs/images/boas-vindas-1.png docs/images/boas-vindas-2.png
```

Capture a página nova pela receita do Passo 1 e salve como
`docs/images/novidades.png`, referenciando-a em `docs/novidades.md`.

- [ ] **Passo 6: conferir que nada ficou pendurado**

```bash
grep -rn "onboarding\|Onboarding\|boas-vindas" docs/ README.md CLAUDE.md tools/ Knobler/ \
  --exclude-dir=superpowers
```

Esperado: só `Knobler/Novidades/boas-vindas.html`, as chaves de migração em
`NovidadesCatalogo.swift` e menções históricas no `CHANGELOG.md`.

- [ ] **Passo 7: commit**

```bash
git add -A docs README.md CLAUDE.md
git commit -m "docs: página de novidades substitui o doc de boas-vindas"
```

---

## Verificação final

- [ ] `./tools/check.sh` — todos os gates, `novidadescheck` incluso
- [ ] `xcodebuild -project Knobler.xcodeproj -scheme Knobler -configuration Debug build`
- [ ] `Knobler --novidades` abre a página, o vídeo toca em loop, o botão de ação
      abre o painel certo, e `defaults read com.zoi.knobler novidades.versaoVista`
      continua ausente depois de fechar
- [ ] Simulação de update: `defaults write com.zoi.knobler novidades.versaoVista 0.24.0`,
      abrir o app normalmente (sem flag) — a página abre com a 0.25.0, e ao fechar
      a chave passa a valer a versão instalada
- [ ] Simulação de migração: `defaults delete com.zoi.knobler novidades.versaoVista`,
      `defaults write com.zoi.knobler onboarding.versao -int 2`, abrir — a página
      abre com a 0.25.0, **sem** a boas-vindas
- [ ] Simulação de instalação limpa: apagar as duas chaves e a de permissões,
      abrir — vê só a boas-vindas, e o painel Permissões vem depois de fechar

## Riscos que o plano herda da spec

1. Print desatualizado: nenhum gate compara mídia com UI real.
2. Peso do bundle: MP4 por novidade acumula; revisitar acima de ~20 MB em `midia/`.
3. `WKScriptMessageHandler` no macOS 26 tem relato de crash não investigado
   (developer.apple.com/forums/thread/811070). A máquina de desenvolvimento roda
   macOS 26 — se acontecer, acontece na Task 5.
4. O `novidadescheck` arrasta 19 arquivos pro compile (o bloco do `plugincheck`,
   pelo `PluginID` de verdade): o gate fica dos mais lentos da suíte. Só a lista
   de `SettingsPane` continua cópia, marcada com `ponytail:` — trazê-la de
   verdade arrastaria SwiftUI e a janela de Ajustes inteira.
