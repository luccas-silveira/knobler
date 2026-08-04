# Wizard de boas-vindas e dicas de atalho — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Uma janela de boas-vindas apresentada na primeira execução, com dois
passos informativos (o que é o Knobler e onde ele vive; os dois atalhos
globais), versionada por passo para que a base instalada veja só o que é novo
pra ela.

**Design:** [`2026-08-03-boas-vindas-design.md`](../specs/2026-08-03-boas-vindas-design.md)
**Pesquisa:** [`2026-08-03-boas-vindas-research.md`](../specs/2026-08-03-boas-vindas-research.md)

**Architecture:** Um modelo puro (`Knobler/Onboarding.swift`) com a lista de
passos, os dois números de versão por passo e a função de filtragem — sem
`import SwiftUI` e sem `AppSettings`, para que `tools/onboardingcheck.swift`
compile só ele. Uma view (`Knobler/OnboardingView.swift`) com a janela e as duas
telas. O `AppDelegate` deixa de pedir Acessibilidade no launch (quem pede passa
a ser o painel Permissões, que já tem `request(completion:)`) e passa a
apresentar o wizard; o painel Permissões abre quando o wizard fecha.

**Tech Stack:** Swift 5 / SwiftUI / AppKit (`NSWindow` + `NSHostingView`),
XcodeGen, `swiftc` direto nos checks.

## Global Constraints

- Comentários e strings de UI em **pt-BR** (`CLAUDE.md`).
- `Knobler/Onboarding.swift` **não** pode importar SwiftUI nem referenciar
  `AppSettings` — é o que faz o check compilar isolado (mesma razão do
  `CalendarAviso`). Se essa regra cair, o check morre junto.
- Arquivo novo em `Knobler/` = `xcodegen generate`. **Nunca** editar o
  `.xcodeproj` à mão.
- Check novo = entrada em `tools/check.sh`, senão a CI não o vê.
- O wizard **não escreve** em `AppSettings`. Se aparecer vontade de colocar um
  toggle, releia a seção "O que o backlog pedia" da spec.
- `MARKETING_VERSION` e tags: só `tools/release.sh`. Este plano escreve em
  `## [Unreleased]` do `CHANGELOG.md` e mais nada.

---

## Task 1 — Modelo puro dos passos e o filtro

**Arquivo:** `Knobler/Onboarding.swift` (novo)

- [ ] `struct OnboardingPasso`: `id: String`, `titulo: String`, `criadoEm: Int`,
      `revisadoEm: Int`. O corpo do texto mora na view — aqui só o que o filtro
      precisa e o que o check consegue verificar.
- [ ] `enum Onboarding` com `static let passos: [OnboardingPasso]`:
      `apresentacao` (`criadoEm: 1, revisadoEm: 1`) e `atalhos`
      (`criadoEm: 2, revisadoEm: 2`).
- [ ] `static let versaoAtual = 2` — o maior `max(criadoEm, revisadoEm)` da
      lista. Deixe um comentário dizendo que subir um passo obriga a subir isto.
- [ ] `enum Novidade { case novo, atualizado }` e
      `struct PassoVisivel { let passo: OnboardingPasso; let novidade: Novidade }`.
- [ ] `static func visiveis(paraVersao vista: Int, passos: [OnboardingPasso] = passos) -> [PassoVisivel]`:
      inclui o passo quando `max(criadoEm, revisadoEm) > vista`; a novidade é
      `.novo` quando `criadoEm > vista`, senão `.atualizado`. Ordem preservada.
- [ ] Chaves e migração, isoladas em funções que recebem o `UserDefaults`
      (`= .standard` por padrão) pra o check poder passar um suite próprio:
      - `chaveVersao = "onboarding.versao"`;
      - `chaveLegado = "onboarding.permissoes.apresentado"`;
      - `static func versaoVista(_ d: UserDefaults) -> Int` — se `chaveVersao`
        existe, devolve; senão, se `chaveLegado` for `true`, devolve **1**
        (base instalada vê só os atalhos); senão **0**.
      - `static func marcarVisto(_ d: UserDefaults)` grava `versaoAtual`.

**Verificação:** compila sozinho —
`xcrun swiftc -parse-as-library -swift-version 5 Knobler/Onboarding.swift -o /tmp/x`.
Se pedir SwiftUI ou `AppSettings`, a Task 1 está errada.

**Commit:** `feat: modelo de passos do onboarding com versão por passo`

---

## Task 2 — Check hermético

**Arquivos:** `tools/onboardingcheck.swift` (novo), `tools/check.sh`

- [ ] Harness com `-parse-as-library` (**não** `main.swift`), no molde dos
      outros: linha de compilação no cabeçalho, asserções, saída `!= 0` no erro.
- [ ] Casos, todos sobre `Onboarding.visiveis(paraVersao:passos:)` com uma
      lista de passos fixa do próprio teste (não a de produção, que vai mudar):
      - `vista = 0` → todos os passos, todos `.novo`;
      - `vista = versaoAtual` → **vazio** (e portanto o wizard não abre);
      - passo com `criadoEm > vista` → só ele, `.novo`;
      - passo com `criadoEm <= vista < revisadoEm` → só ele, `.atualizado`;
      - `vista = 1` na lista de produção → só `atalhos`.
- [ ] Casos de `versaoVista(_:)` com um `UserDefaults(suiteName:)` descartável:
      suite vazia → `0`; só a chave legada `true` → `1`; `chaveVersao = 2` →
      `2` (a chave nova ganha da legada).
- [ ] Entrada em `tools/check.sh`, junto dos outros `swift_check`:
      `swift_check onboardingcheck Knobler/Onboarding.swift tools/onboardingcheck.swift`

**Verificação:** `./tools/check.sh` passa com um check a mais que hoje (24).

**Commit:** `test: gate do filtro de passos do onboarding`

---

## Task 3 — A janela e as duas telas

**Arquivo:** `Knobler/OnboardingView.swift` (novo)

- [ ] `struct OnboardingView: View` recebendo `[PassoVisivel]` e dois closures
      (`aoConcluir`, `aoIgnorar`). Um passo por vez, com "Continuar" / "Voltar"
      e o botão final "Começar".
- [ ] Botão **"Ignorar"** visível em todos os passos.
- [ ] Cabeçalho "Novo" ou "Atualizado" por passo, conforme `Novidade` — só
      quando `versaoVista > 0` (numa instalação nova, tudo é novo e o selo é
      ruído).
- [ ] Conteúdo do passo `apresentacao`: o notch responde ao mouse; o app não tem
      Dock nem janela, o acesso é o ícone da barra de menus; e uma linha dizendo
      que Mensagens te anuncia na rede local com o nome do Mac (editável em
      Ajustes → Mensagens).
- [ ] Conteúdo do passo `atalhos`: ⌥ direita = ditado (segurar pra falar);
      Control direito = anotação. Só esses dois.
- [ ] **Decida e fixe o tamanho da janela agora** — o recorte da captura depende
      dele (ver Task 7). 800×520, igual aos Ajustes, é o default que já tem
      recorte calibrado.

**Verificação:** build Debug. Sem snapshot automático: `NSWindow` real não
renderiza no `tools/snapshot.sh`.

**Commit:** `feat: telas de boas-vindas`

---

## Task 4 — Wiring no AppDelegate

**Arquivo:** `Knobler/KnoblerApp.swift`

- [ ] `xcodegen generate` primeiro (dois arquivos novos).
- [ ] Tirar `Permission.promptAccessibilityOnce()` do
      `applicationDidFinishLaunching` (`:175`). A pesquisa confirma que os três
      consumidores repolam o trust a cada 3 s e se religam sem relaunch — mas
      **deixe um comentário** dizendo isso, senão a linha volta.
- [ ] `apresentarBoasVindasSeNecessario()` substituindo
      `apresentarPermissoesSeNecessario()` no `else` da flag de CLI:
      calcula `visiveis(paraVersao: versaoVista(...))`; **lista vazia → não
      abre nada** e o painel Permissões segue a regra própria (abaixo).
- [ ] Janela no molde do `showSettings` (`:1302`): `NSHostingView`,
      `isReleasedWhenClosed = false`, `center()`, `makeKeyAndOrderFront` +
      `NSApp.activate(ignoringOtherApps: true)`. Guardar em
      `private var onboardingWindow: NSWindow?`.
- [ ] Observer de `NSWindow.willCloseNotification` **para essa janela**: grava
      `marcarVisto`, solta a referência e encadeia o painel Permissões
      (`showSettings(pane: .permissoes)`). "Ignorar" e "Começar" só chamam
      `close()` — uma gravação, um lugar.
- [ ] `Permission.installIssue != nil` continua abrindo o painel Permissões
      direto, **sem** passar pelo wizard: é regra de saúde da instalação, não de
      novidade.
- [ ] Item de menu **"Boas-vindas…"** logo acima de "Ajustes do Knobler…"
      (`:1152`), abrindo o wizard com **todos** os passos (`paraVersao: 0`) —
      quem pede de propósito quer ver tudo.
- [ ] Flag `--boas-vindas` **dentro do mesmo `if` da `--ajustes`** (`:555`):
      abre a janela e **não** grava versão nem encadeia Permissões (é modo de
      captura). Cuidado: o observer da Task 4 grava no fechamento — o modo
      captura precisa desviar disso.

**Verificação (ao vivo, ordem importa):**
1. `defaults delete com.zoi.knobler onboarding.versao` +
   `defaults delete com.zoi.knobler onboarding.permissoes.apresentado` → abre os
   dois passos; ao fechar, o painel Permissões aparece.
2. Relançar → não abre nada.
3. `defaults write com.zoi.knobler onboarding.permissoes.apresentado -bool true`
   + apagar `onboarding.versao` → abre **só** os atalhos, marcado "Novo".
4. Menu → "Boas-vindas…" → os dois passos.
5. `--boas-vindas` → abre, e ao fechar **não** grava nem abre Permissões.
6. Conceder Acessibilidade pelo painel e confirmar em até ~3 s que o ⚠ do
   `statusItem` some e o ditado responde — sem relaunch.

Restaure os `defaults` da máquina no fim.

**Commit:** `feat: boas-vindas na primeira execução`

---

## Task 5 — Documentação de usuário

**Arquivos:** `docs/onboarding.md` (novo), `docs/index.md`, `CHANGELOG.md`

- [ ] `docs/onboarding.md` no template dos outros (O que faz / Como usar /
      Permissões): o que a janela mostra, que ela não volta sozinha, como
      reabrir pelo menu, e que o painel Permissões vem depois.
- [ ] Link no `docs/index.md`.
- [ ] `## [Unreleased]` do `CHANGELOG.md`, em pt-BR.
- [ ] `docs/architecture.md`: `Onboarding.swift` na lista de módulos sem
      dependência (junto do `CalendarAviso`), e a mudança de quem pede
      Acessibilidade — hoje a arquitetura diz que é o launch.
- [ ] `README.md`: a tabela de permissões diz que Acessibilidade é pedida no
      launch. Passou a ser pedida no painel Permissões, depois do wizard.
      Corrigir, senão o doc mente.

**Commit:** `docs: boas-vindas na primeira execução`

---

## Task 6 — Imagens

**Arquivos:** `docs/images/boas-vindas-1.png`, `docs/images/boas-vindas-2.png`

- [ ] Build Release, `Knobler.app/Contents/MacOS/Knobler --boas-vindas`.
- [ ] `screencapture -l<windowID>` e recorte pelas bordas reais da janela — o
      `802x554+55+37` dos `settings-*.png` vale **se** a janela for 800×520
      (Task 3). Outro tamanho = recalibrar o recorte.
- [ ] Embutir nas duas seções do `docs/onboarding.md`.

**Commit:** `docs: imagens da janela de boas-vindas`

---

## Task 7 — Fechamento

- [ ] `./tools/check.sh` → 24 checks.
- [ ] Build Debug e Release.
- [ ] `docs/IDEIAS.md`: mover "Wizard de primeira execução" e "Dicas de
      hotkeys" para **Entregues**, com link pro doc — os dois itens viraram um.
      "Modo tutorial" fica no backlog, intocado.
- [ ] `docs/ROADMAP.md`: tirar o item da lista de soltos.
- [ ] `HANDOFF.md` com o estado da sessão.

**Commit:** `docs: onboarding sai do backlog`

---

## Armadilhas conhecidas

- **A flag de captura grava a versão.** O observer de `willCloseNotification` é
  global à janela; o modo `--boas-vindas` tem que desviar dele, senão tirar
  print queima o onboarding da máquina.
- **`versaoAtual` desatualizada.** Passo novo com `criadoEm: 3` e
  `versaoAtual` ainda em `2` faz o wizard reabrir pra sempre: grava 2, e 3 > 2
  na próxima. O check pega isso se a asserção "`vista = versaoAtual` → vazio"
  rodar sobre a lista **de produção** — inclua esse caso.
- **`Onboarding.swift` importando SwiftUI.** Mata o check em silêncio (ele passa
  a compilar a árvore toda, ou para de compilar).
- **Duas janelas disputando foco.** O painel Permissões só pode abrir **depois**
  do wizard fechar, nunca em paralelo. Foi o bug que criou o `asyncAfter(1.5)`
  original.
