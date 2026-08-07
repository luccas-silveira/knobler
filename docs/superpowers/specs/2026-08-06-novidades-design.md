# Página de novidades — design

Data: 2026-08-06
Estado: revisada pelo grill. Dossiê:
`docs/superpowers/research/2026-08-06-novidades-research.md`.

## Vocabulário

Três níveis, nomes fixos — nenhum colide com `card`, `peça`, `painel` ou `seção`,
que já têm dono no projeto:

- **página** — a janela inteira
- **versão** — um arquivo (`0.25.0.html`), o que chegou numa release
- **novidade** — uma feature demonstrada dentro de uma versão

## Problema

O Knobler é `LSUIElement` e cresce por release: v0.24.0 fechou onze peças de
marketplace, e nada disso chega a quem já tinha o app instalado. O único canal
hoje é o `CHANGELOG.md`, técnico demais pra ensinar alguém a usar, e o wizard de
boas-vindas (`Onboarding.swift` + `OnboardingView.swift`), que é texto puro em
SwiftUI, sem imagem, versionado por um `Int` desligado do SemVer.

O que falta é uma página de verdade — texto, print, vídeo curto e tutorial —
que abra sozinha quando a versão sobe e demonstre o que chegou.

O outro canal que existe, o `DevAvisos` (`docs/avisos.md`), continua no papel
dele: card curto no notch, publicado à mão no `avisos.json`, filtrado por faixa
de versão. Ele alcança quem **ainda não atualizou** — é o convite; a página é a
demonstração depois do update. Publicar um aviso no dia do release não custa
código nenhum, e as ações dele seguem `https`-only como hoje
(`DevAvisos.swift:151-165`): abrir a janela local a partir de um JSON remoto seria
a primeira exceção a essa regra, e não vale.

## Decisão de forma

A janela é um `WKWebView` com HTML local, não SwiftUI. O motivo é o conteúdo:
figura com legenda, vídeo em loop, passo numerado e botão de ação são baratos em
HTML/CSS e caros em SwiftUI, e o conteúdo muda a cada release enquanto a moldura
não muda nunca. O app já embarca `WKWebView` (Link Preview), então não entra
dependência nova.

O custo aceito: a janela não entra no `tools/snapshot.sh` (`WKWebView` não
renderiza offscreen — vala já documentada no `CLAUDE.md`), e passam a existir
dois vocabulários de estilo no projeto.

## Arquitetura

### Janela

`NovidadesWindow` — uma `NSWindow` não-modal com o `WKWebView` ocupando tudo,
molde do `mostrarBoasVindas` (`KnoblerApp.swift:739-784`): `styleMask` `[.titled,
.closable]`, moldura fixa no conteúdo, `isReleasedWhenClosed = false`, e um
observer de `NSWindow.willCloseNotification` no lugar de delegate — nenhuma
janela do projeto tem delegate. Esc fecha.

Abre em três situações:

1. **Primeiro launch de uma versão nova** — comparação de `MARKETING_VERSION`
   com `novidades.versaoVista`. Pega update pelo Updater, por `brew upgrade` e
   por download manual, e dispara uma vez só por versão. **Ativa o app**
   (`NSApp.activate`): num app sem Dock, janela que nasce atrás de tudo é janela
   que ninguém encontra. Grava a versão vista ao fechar.
2. **Menu da barra (◐) → "Novidades…"** — abre com o histórico completo e **não
   grava** a versão vista. Substitui o item "Boas-vindas…" de hoje, que grava
   (`KnoblerApp.swift:787-789`) — a mudança é deliberada: menu é releitura, e
   item de menu que altera estado invisível é surpresa.
3. **`Knobler --novidades`** — mostra tudo e não grava, pra capturar print sem
   queimar o estado da máquina. Mesmo contrato do `--boas-vindas` atual, no mesmo
   bloco de flags (`KnoblerApp.swift:701-712`), que é o último passo do
   `applicationDidFinishLaunching` — depois de `plugins.subir()` e
   `placeWindows()`, então a ponte pode instalar peça com segurança.

Gravar é consequência de quem abriu, não parâmetro: só o caminho 1 grava.

Como hoje, `Permission.installIssue != nil` sequestra a primeira abertura e manda
direto pro painel Permissões (`KnoblerApp.swift:722-734`) — é por isso que a
receita de captura manda rodar de `/Applications`.

A `WKWebView` **nasce e morre com a janela**: no `willClose`, o mesmo observer que
grava a versão vista chama `removeScriptMessageHandler(forName:)` e solta a view.
O `WKUserContentController` retém o handler forte, e registrar o mesmo nome duas
vezes é erro — não warning. O padrão oposto (`LinkPreview.swift:40-41`, uma só
viva pro app inteiro) existe lá porque serve link a qualquer momento; aqui a
janela abre uma vez por release e ninguém está esperando resposta imediata.

Texto selecionável exige o monitor local de `NSEvent` pra ⌘C/⌘A: o app é
`LSUIElement` e não tem menu bar, então sem isso copiar não funciona nem com a
janela-chave (`LinkPreview.swift:126-143`).

### Carga do conteúdo

Sem `WKURLSchemeHandler` e sem `fetch`. A `WKWebView` carrega o `shell.html`
estático do bundle com `loadFileURL(_:allowingReadAccessTo:)` apontando pra
`Novidades/` — CSS e mídia relativa resolvem sozinhos. Os corpos das versões
pendentes o Swift lê do bundle e **injeta** num `WKUserScript` de `.atDocumentEnd`
(HTML escapado numa string JS, atribuído ao container do shell). Nada de arquivo
temporário: o bundle é assinado e read-only.

Sem `fetch` entre fragmentos, o motivo que justificaria o esquema custom
desaparece, e com ele o handler de `Range`/206 que o `<video>` exigiria (WebKit
bug 203302: no macOS o header `Range` chega ao handler) e a tabela de MIME.

O endurecimento segue o Sparkle (`SUWKWebView.m`), que resolve o mesmo problema —
release notes locais numa `WKWebView` — há anos:

- **JavaScript do documento desligado.** A ponte roda por `WKUserScript`, que
  executa mesmo com JS de documento off; é assim que o Sparkle injeta CSS.
- **`WKContentRuleList` bloqueando `.*`** — corta requisição externa na raiz, sem
  depender de o HTML cooperar. Mais forte que CSP.
- **`javaScriptCanOpenWindowsAutomatically = NO`.**
- **Allowlist de esquema em `decidePolicyFor`** — `http`/`https` sai pro
  `NSWorkspace.shared.open` com `.cancel`; qualquer outro esquema é bloqueado com
  log, `file://` inclusive.
- **`mediaTypesRequiringUserActionForPlayback = []`** explícito: o default no
  macOS não é documentado. `allowsInlineMediaPlayback` é iOS-only, não usar.

### Catálogo e estado

`Knobler/NovidadesCatalogo.swift` — arquivo **sem dependência de SwiftUI nem
`AppSettings`**, mesmo motivo do `Onboarding.swift`/`CalendarAviso.swift`: o gate
precisa compilá-lo isolado com `swiftc`.

Responsabilidade única: dada a versão instalada e a versão vista, devolver a
lista de versões a exibir, mais nova primeiro.

A comparação **reusa** `versionComponents`/`isNewer` do `Updater.swift`. Não é
duplicação nova: o `Updater` é autocontido de propósito (`Updater.swift:5-7`),
`versionComponents` é internal justamente porque o `DevAvisos` já a usa
(`DevAvisos.swift:140-149`), e o `avisoscheck` já compila os dois juntos com o
comentário "arrasta o Updater" (`check.sh:113-114`). O `novidadescheck` faz o
mesmo. Uma terceira cópia de comparação de SemVer no repo não se justifica.

Chave nova: `novidades.versaoVista` (String SemVer).

Migração da chave antiga `onboarding.versao` (`Int`):

| Estado antigo | Vira | Vê |
|---|---|---|
| ausente (instalação limpa) | grava versão atual | só `boas-vindas.html` |
| `0` ou legado `false` | `"0.0.0"` | `boas-vindas.html` |
| `1` | `"0.0.0"` | `boas-vindas.html` |
| `2` (viu o wizard atual) | `"0.24.0"` | novidades da 0.25 em diante |

Instalação limpa **não** recebe o histórico acumulado junto da boas-vindas: a
primeira impressão fica curta.

### Ponte de ações

Um `WKScriptMessageHandler` só, nome `app`, injetado por `WKUserScript` — que
roda mesmo com o JS do documento desligado. O JS manda `{acao, alvo}`; o Swift
casa contra um enum fechado e ignora silenciosamente o que não casar:

- `abrirAjustes(painel)` — `SettingsPane(rawValue:)`, o mesmo caminho da flag
  `--ajustes=`. Exige expor um método no `AppDelegate`: `showSettings(pane:)` é
  `private` hoje (`KnoblerApp.swift:1562`).
- `instalarPeca(PluginID)` — `plugins.instalar(_:)` (`Plugin.swift:487`)
- `abrirCard` — abre o card do notch

`SettingsPane` (`SettingsView.swift:16-19`) e `PluginID` (`Plugin.swift:19-22`)
são a validação: o gate cruza contra eles, não contra lista nova.

Nenhuma string vira chamada arbitrária, nenhum `eval`, nenhum caminho de arquivo
atravessa a ponte. `WKScriptMessageHandlerWithReply` existe desde macOS 11, mas é
overkill pra ação fire-and-forget.

## Conteúdo

### Estrutura no bundle

```
Knobler/Novidades/
  shell.html        documento estático: moldura, índice lateral, container vazio
  estilo.css        um só, com modo escuro
  ponte.js          injetado como WKUserScript: monta o corpo e fala com o Swift
  boas-vindas.html  corpo da primeira abertura
  0.25.0.html       corpo de uma release
  midia/            PNG e MP4 referenciados pelas versões
```

Cada arquivo de versão contém **só o corpo** — sem `<html>`, `<head>` ou
`<style>`. Vocabulário fechado, uma `<section>` por novidade:

```html
<section class="novidade">
  <h2>Título da novidade</h2>
  <p>O que ela faz e por que existe.</p>
  <figure>
    <video src="midia/ditado.mp4" autoplay loop muted playsinline></video>
    <figcaption>Segure ⌥ direita pra falar.</figcaption>
  </figure>
  <ol class="tutorial">
    <li>…</li>
  </ol>
  <button data-acao="abrirAjustes" data-alvo="ditado">Abrir Ajustes → Ditado</button>
</section>
```

### Mídia

Pasta própria, só o que as páginas referenciam. Copiar `docs/images/` inteiro
está descartado: são 14 MB em 41 PNGs, a maioria sem uso na página.

PNG pro que é estático; MP4 H.264 curto (3–5 s, `autoplay loop muted
playsinline`) pro que é gesto — segurar ⌥ direita, arrastar arquivo pra
prateleira. Print que já existe em `docs/images/` entra como **cópia**: bundle
assinado não aceita symlink.

### Régua editorial

A página ensina a **começar** — o primeiro uso, com a ação embutida no botão — e
linka `docs/` pro resto. O que virar referência completa está no lugar errado.

## O que sai

`OnboardingView.swift`, o `Onboarding.swift` inteiro (o versionamento por `Int`
com `criadoEm`/`revisadoEm` por passo — maquinaria que a spec do wizard já tinha
marcado como cara demais pro conteúdo, `2026-08-03-boas-vindas-design.md:103-105`),
o `tools/onboardingcheck.swift` e a entrada dele em `tools/check.sh:110` são
aposentados. Os dois passos de hoje viram novidades do `boas-vindas.html`, com
print no lugar das linhas de ícone. O encadeamento pro painel **Ajustes →
Permissões** ao fechar a janela continua exatamente como está.

Docs a atualizar, inventário completo:

| Arquivo | O quê |
|---|---|
| `docs/onboarding.md` | vira `docs/novidades.md`, cobrindo boas-vindas e novidades |
| `docs/index.md:30` | link e descrição |
| `docs/settings.md:110,121` | dois links pra `onboarding.md` |
| `docs/calendar-countdown.md:34` | link pra `onboarding.md` |
| `docs/troubleshooting.md:88` | menção textual |
| `docs/architecture.md:34,96` | fluxo de launch e tabela de ownership citam `Onboarding`/`OnboardingView` |
| `README.md:79,164` | bloco do wizard e sequência de permissões |
| `CLAUDE.md:140-142` | receita de captura `--boas-vindas` vira `--novidades` |
| `VERSIONING.md` | a exigência nova de página em MINOR |

## Gates

Um check novo em `tools/check.sh` (a lista canônica; check fora dela a CI não
vê), no lugar da entrada aposentada do `onboardingcheck`.

**`tools/novidadescheck.swift`** — compila `Knobler/NovidadesCatalogo.swift`,
`Knobler/Updater.swift` (pela comparação de versão, como o `avisoscheck` já faz) e
`Knobler/Plugin.swift` (pelo `PluginID`), e assere as duas metades:

Filtro —

- comparação SemVer por componente: `0.9.0` < `0.10.0`
- ordem decrescente na saída
- as quatro linhas da tabela de migração
- instalação limpa não recebe histórico

Conteúdo, varrendo `Knobler/Novidades/*.html` —

- nome de arquivo de versão é SemVer válido
- todo `src` aponta pra mídia que existe em `midia/`
- todo `data-acao` está no enum
- todo `data-alvo` de `instalarPeca` é um `PluginID` real

Um gate só, em Swift, e não dois com um `.mjs`: o repo não tem precedente de
`.mjs` varrendo arquivo estático (os três existentes sobem servidor fake ou
spawn de processo), e em Node o `PluginID` viraria lista copiada — cópia de enum
dessincroniza calada, que é o tipo de erro que estes gates existem pra pegar.

**`tools/release.sh`** — `minor` aborta sem `Knobler/Novidades/<versão>.html`;
`patch` passa sem. O abort entra depois da resolução de versão
(`release.sh:59-78`), junto dos outros pre-flight (`:87-106`).

## QA visual

Fora do `tools/snapshot.sh`. A receita é a das boas-vindas: build, rodar de
`/Applications` ou `~/Applications`, `Knobler --novidades`, achar o `windowID` em
`CGWindowListCopyWindowInfo`, `screencapture -o -l<id>`. Vira comentário em
`docs/novidades.md`.

## Processo

`CLAUDE.md` **e** `VERSIONING.md` ganham a regra: **feature nova escreve a
novidade no HTML junto da entrada do CHANGELOG**, não no fim do ciclo de release.
O `VERSIONING.md` é a fonte de verdade do bump — a exigência de página em MINOR
mora lá, não só no `CLAUDE.md`.

No dia do release, publicar um aviso no `avisos.json` apontando pro GitHub
Release: é o que alcança quem ainda não atualizou.

## Fora de escopo

- Página remota ou hospedada no site (offline deixa de funcionar; o site passa a
  ter que acompanhar o ritmo do app)
- Geração automática a partir do `CHANGELOG.md`
- Notificação/selo de novidade no ícone da barra de menus
- i18n: o app é pt-BR, a página também

## Riscos conhecidos

1. **Print desatualizado.** Nenhum gate compara a mídia com a UI real. É o mesmo
   risco que `docs/images/` já corre, e o `novidadescheck` só garante que o
   arquivo existe.
2. **Peso do bundle.** Um MP4 de 3–5 s de tela custa centenas de KB, então o
   acúmulo é lento — mas é acúmulo. Revisitar quando a pasta `midia/` passar de
   uns 20 MB; a saída natural é podar as versões mais antigas do bundle.
3. **Dois vocabulários de estilo.** A janela HTML não herda o visual do resto do
   app automaticamente; manter parecido é trabalho manual no `estilo.css`.
4. **`WKScriptMessageHandler` no macOS 26.** Existe relato de crash
   (developer.apple.com/forums/thread/811070) não investigado. A máquina de
   desenvolvimento roda macOS 26 — se aparecer, aparece cedo.

## Decisões do grill

- **A3 + A6** — cortado o `WKURLSchemeHandler`. Motivo: o esquema custom só se
  pagava pelo `fetch` entre fragmentos, e o Swift injetando o corpo por
  `WKUserScript` elimina o `fetch`. Com o handler iam junto o `Range`/206 que o
  `<video>` exigiria no macOS (WebKit 203302) e a tabela de MIME. O
  endurecimento veio do Sparkle (`SUWKWebView.m`), que é prior art do mesmo
  problema: JS de documento desligado, `WKContentRuleList`, allowlist de esquema.
- **A1** — página e `DevAvisos` convivem com papéis separados, sem código novo.
  Motivo: só o aviso alcança quem não atualizou; e abrir janela local a partir de
  JSON remoto quebraria a regra `https`-only de `DevAvisos.swift:151-165`.
- **A10** — o item de menu **não** grava a versão vista, mudando o comportamento
  de hoje (`KnoblerApp.swift:787`). Motivo: menu é releitura; gravar é
  consequência de ter aberto sozinho.
- **A15** — um gate só, em Swift, no lugar de `novidadescheck` + `.mjs`. Motivo:
  em Node o `PluginID` viraria cópia, e não há precedente de `.mjs` varrendo
  arquivo estático no repo.
- **A7** — `WKWebView` nasce e morre com a janela, contrariando o padrão do
  `LinkPreview`. Motivo: o `WKUserContentController` retém o handler forte e
  registrar o mesmo nome duas vezes é erro; a latência de primeiro paint não
  importa numa janela aberta uma vez por release.
- **A16** — vocabulário fixado: página (janela), versão (arquivo), novidade
  (feature demonstrada). Motivo: "seção", "card", "peça" e "painel" já têm dono.
- **A9** — mantida a abertura automática ativando o app. Motivo: a crítica de
  NN/g e a HIG pedem fácil de fechar, uma vez só e reencontrável — a spec cumpre
  as três; num app sem Dock, não ativar é a janela não ser vista.
- **A2** — reusa `isNewer`/`versionComponents` do `Updater`, e o gate arrasta o
  arquivo. Motivo: o `avisoscheck` já faz exatamente isso; terceira cópia de
  SemVer no repo não se justifica.
- **A5, A8, A11, A12, A19, A20, A21** — incorporados ao texto como restrições de
  implementação (ciclo de vida do handler, ⌘C sem menu bar, `installIssue`, ordem
  do launch, `showSettings` privado, sem entitlement novo, autoplay explícito).
- **A13, A14** — inventário de docs e a regra no `VERSIONING.md` viraram tabela e
  seção de processo.
- **A17** — mantido H.264. Motivo: em clipe de 3–5 s a economia do HEVC é de
  centenas de KB e o risco é Intel pré-2017.
