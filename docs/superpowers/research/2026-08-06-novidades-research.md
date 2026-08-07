# Pesquisa — página de novidades

Spec: `docs/superpowers/specs/2026-08-06-novidades-design.md`

Três frentes internas (reuso, documentação, blast radius) e uma externa
(WKWebView, esquema custom, mídia, prior art de "what's new").

## Achados

### A1 — Já existe um canal de novidade por versão no app: `DevAvisos`
- Fonte: `Knobler/DevAvisos.swift:1-20`, `docs/avisos.md:1-6`
- A doc abre com "quem mantém o Knobler publica um recado — **uma novidade da
  versão**, um aviso de manutenção — e ele vira card no notch". Filtra por faixa
  `minVersao`/`maxVersao`, aceita ações só `https`, respeita silêncio de reunião
  e entra no Histórico.
- Contradiz a spec: parcial
- Pergunta que levanta: a página de novidades e o `DevAvisos` são dois canais ou
  um? Um aviso publicado no dia do release apontando pra página resolveria a
  descoberta sem a janela abrir sozinha — e é o único caminho que alcança quem
  ainda **não** atualizou.

### A2 — `versionComponents`/`isNewer` já são reusados fora do Updater, com gate que arrasta o arquivo
- Fonte: `Knobler/Updater.swift:33-51`, `Knobler/DevAvisos.swift:140-149`,
  `tools/check.sh:113-114`
- O `Updater.swift` é deliberadamente autocontido (`Updater.swift:5-7`) e
  `versionComponents` é internal de propósito "porque `DevAvisos` valida faixa de
  versão usando ela". O `avisoscheck` já compila `Updater.swift` +
  `DevAvisos.swift` juntos, com o comentário "arrasta o Updater".
- Contradiz a spec: não — **fecha** a pergunta que a spec deixou aberta
- Registro: o `NovidadesCatalogo` reusa `isNewer`/`versionComponents`, e o
  `novidadescheck` arrasta o `Updater.swift` como o `avisoscheck` já faz.
  Duplicar comparação de SemVer num terceiro lugar não tem justificativa.

### A3 — `WKURLSchemeHandler` obriga você a implementar `Range`/206 para `<video>`
- Fonte: https://bugs.webkit.org/show_bug.cgi?id=203302 (RESOLVED FIXED
  2021-05-03; o macOS **inclui** o header `Range` nas requisições ao handler),
  https://developer.apple.com/forums/thread/745034
- Servindo por esquema custom, o handler vira um mini servidor HTTP: MIME type
  correto (senão CSS não aplica — forums/766143, /773910) e `HTTPURLResponse` com
  status 206, `Content-Range` e `Accept-Ranges` pro elemento `<video>` tocar. Com
  `file://` o WebKit lê o arquivo direto e o range não é problema seu.
- Contradiz a spec: sim
- Pergunta que levanta: a spec escolheu o esquema custom pra viabilizar `fetch`
  entre fragmentos. Se o Swift montar o documento e injetar (ou se as páginas
  virarem um HTML só), não há `fetch`, e `loadFileURL(_:allowingReadAccessTo:)`
  entrega imagem, CSS e vídeo sem escrever handler nenhum. Vale o handler?

### A4 — Esquema custom tem três exceções e um teste canônico
- Fonte: `WKWebViewConfiguration.h` (WebKit) — "An exception will be thrown if
  you try to register a URL scheme handler for a URL scheme that WebKit handles
  internally"; `WKWebView.h:113-125` — "The initializer copies the specified
  configuration"
- Registrar duas vezes o mesmo nome, registrar esquema inválido ou registrar
  esquema interno lança exceção; e o handler tem que estar na configuração
  **antes** de instanciar a `WKWebView`. O teste é
  `WKWebView.handlesURLScheme("knobler")`.
- Contradiz a spec: não — detalha o que a implementação precisa respeitar

### A5 — `WKScriptMessageHandler` vaza por retain cycle e quebra ao registrar duas vezes
- Fonte: `WKUserContentController.h` — "it is an error to add another script
  message handler to that WKContentWorld for that same name without first
  removing the previous"; https://developer.apple.com/forums/thread/22795 e
  três relatos independentes de vazamento
- O `WKUserContentController` retém o handler forte. Reabrir a janela de
  novidades reusando o mesmo controller sem `removeScriptMessageHandler(forName:)`
  é erro, não warning.
- Contradiz a spec: não — mas a spec não fala de ciclo de vida do handler
- Registro: `WKScriptMessageHandlerWithReply` existe desde macOS 11, abaixo do
  target 14.2 — disponível sem `#available`, e desnecessário pra ações
  fire-and-forget.

### A6 — Sparkle é o prior art da mesma decisão, e endurece mais que a spec
- Fonte: https://github.com/sparkle-project/Sparkle/blob/2.x/Sparkle/SUWKWebView.m,
  `SUReleaseNotesCommon.m`, https://sparkle-project.org/documentation/
- Renderiza release notes em `WKWebView` com: JavaScript **desligado** no
  documento por padrão (`SUEnableJavaScript` religa), `WKContentRuleList`
  bloqueando `.*` (mais forte que CSP e não depende do HTML cooperar),
  `javaScriptCanOpenWindowsAutomatically = NO`, allowlist de esquema no
  `decidePolicyFor` que recusa explicitamente `file://`, e link externo saindo
  pro `NSWorkspace` com `.cancel`.
- Contradiz a spec: parcial
- Pergunta que levanta: o `WKUserScript` roda mesmo com JS do documento
  desligado — é assim que o Sparkle injeta CSS. Dá pra ter a ponte JS→Swift com
  JS de documento desligado? Se der, a spec ganha o endurecimento de graça.

### A7 — Criar `WKWebView` é caro, e o projeto já paga esse preço uma vez só
- Fonte: `Knobler/LinkPreview.swift:40-41` — "Um só, reusado entre links: criar
  `WKWebView` é caro e o processo de conteúdo demora a subir";
  `docs/architecture.md:111-114`
- Contradiz a spec: parcial
- Pergunta que levanta: a janela de novidades cria uma `WKWebView` nova a cada
  abertura, ou mantém uma viva? Numa janela que abre uma vez por release, a
  latência do primeiro paint é justamente o pior momento pra pagar — e manter
  viva conflita com o `removeScriptMessageHandler` de A5.

### A8 — Sem menu bar, `⌘C`/`⌘A` não funcionam na WebView
- Fonte: `Knobler/LinkPreview.swift:126-143` — "o app é LSUIElement e não tem
  menu bar... sem isto, copiar e colar não funcionam nem com a janela-chave"
- Contradiz a spec: não — a spec não menciona
- Registro: se o texto da página for selecionável, precisa do mesmo monitor
  local de `NSEvent`.

### A9 — Modal que abre sozinho é criticado; a HIG dá três condições
- Fonte: https://www.nngroup.com/articles/popups/ ("people dislike popups and
  modals", recomendando overlay não-modal pra apresentar feature nova);
  https://developer.apple.com/design/human-interface-guidelines/onboarding —
  "design a flow that's fast, fun, and **optional**", "don't present it again on
  subsequent launches, but make sure it's easy for people to find later"
- Contradiz a spec: parcial
- Registro: a spec já cumpre as três (fechável, uma vez por versão, item de
  menu). O que a HIG sugere e a spec não tem é a alternativa contextual ("Tip
  Kit"-style) — fora de escopo, mas é a crítica que a decisão está aceitando.

### A10 — Abrir pelo menu hoje **grava** a versão vista; a spec diz que não grava
- Fonte: `Knobler/KnoblerApp.swift:787-789` — `openOnboarding()` chama
  `mostrarBoasVindas(paraVersao: 0, gravando: true)`
- Contradiz a spec: sim (spec, "Menu da barra … sem gravar versão vista")
- Pergunta que levanta: qual é o certo? Gravar pelo menu significa que quem abre
  "Novidades…" por curiosidade perde a abertura automática da versão seguinte —
  não: grava a versão **atual**, então perde só o que já viu. Não gravar
  significa que a janela reabre sozinha no próximo launch mesmo depois de lida.

### A11 — `Permission.installIssue` sequestra a primeira abertura
- Fonte: `Knobler/KnoblerApp.swift:722-734` — se `installIssue != nil`, vai
  direto pro painel Permissões e o wizard nem aparece
- Contradiz a spec: não — a spec herda o comportamento sem citá-lo
- Registro: é a razão de a receita de captura mandar rodar de `/Applications`
  (`CLAUDE.md:140-142`). Vale repetir no `docs/novidades.md`.

### A12 — A ordem de launch é segura: o bloco do wizard é o último
- Fonte: `Knobler/KnoblerApp.swift:601-603` (`plugins.subir()` e só então
  `placeWindows()`), `:701-712` (bloco de flags, fim do método)
- Contradiz a spec: não
- Registro: a janela nasce depois das peças, então `plugins.instalar(_:)` pela
  ponte é seguro. Este arquivo tem dois bugs históricos de ordem (`:232-239`) —
  a nova chamada entra no bloco `701-712`, não antes.

### A13 — O inventário de docs a atualizar é maior que o da spec
- Fonte: `docs/architecture.md:34` e `:96` (tabela de ownership cita
  `Onboarding`/`OnboardingView`), `docs/index.md:30`, `docs/settings.md:110,121`,
  `docs/calendar-countdown.md:34`, `docs/troubleshooting.md:88`, `README.md:79`
  e `:164`, `CLAUDE.md:140-142` (receita `--boas-vindas`), `tools/check.sh:110`
  (entrada do `onboardingcheck` a remover)
- Contradiz a spec: parcial — a spec só cita `docs/onboarding.md`
- Registro: sete arquivos além do que a spec listou. Entra no plano, não é
  decisão de design.

### A14 — A exigência de página em MINOR não existe na fonte de verdade do versionamento
- Fonte: `VERSIONING.md:34-49`, `CLAUDE.md:67-74`, `tools/release.sh:59-78`
  (resolução de versão) e `:87-106` (bloco de pre-flight)
- Contradiz a spec: parcial
- Registro: o abort entra em `release.sh` perto de `59-78` (precisa da versão
  resolvida) e a regra tem que ser escrita em `VERSIONING.md`, não só no
  `CLAUDE.md`.

### A15 — Não há precedente de gate `.mjs` varrendo arquivo estático
- Fonte: `tools/check.sh:144-149` (os `.mjs` existentes sobem servidor fake ou
  spawn de processo), `tools/onboardingcheck.swift:1-9` (molde de gate Swift)
- Contradiz a spec: parcial
- Pergunta que levanta: o `novidadeshtmlcheck` é `.mjs` ou Swift? Varrer HTML por
  regex e cruzar com uma lista de `PluginID` é mais barato em Node, mas a lista
  de `PluginID` e de `SettingsPane` vive em Swift — em `.mjs` ela seria copiada,
  e cópia de enum é exatamente o tipo de coisa que apodrece.

### A16 — A spec usa "página" com dois sentidos
- Fonte: `2026-08-06-novidades-design.md:65-66` ("lista de páginas a exibir" =
  fragmento por release) versus `:152` ("a página de atualização" = a janela)
- Contradiz a spec: parcial (ambiguidade interna)
- Registro: escolher um termo. "Página" pra janela, "seção de versão" pro
  fragmento — ou o inverso, mas um só.

### A17 — H.264 é o seguro; HEVC economiza ~40-50% com risco em Intel antigo
- Fonte: WebKit/Safari suportam HEVC desde Safari 11; decodificação por hardware
  em Apple Silicon e Intel 2017+
  (https://www.totalmedia.ai/en/resources/blog/why-safari-struggles-with-video-formats)
- Contradiz a spec: não
- Registro: em clipe de 3-5s a diferença absoluta é de centenas de KB. A spec
  fixa H.264; manter. Não achei benchmark confiável de GIF/APNG vs H.264 pra
  captura de tela — a preferência por MP4 fica como consenso qualitativo, não
  como número.

### A18 — O SwiftUI do wizard nunca foi decisão contra HTML, e a spec antiga já registrou a tensão do versionamento
- Fonte: `docs/superpowers/specs/2026-08-03-boas-vindas-design.md:42-44`
  ("`NSWindow` própria… O molde é o `showSettings`") e `:103-105` ("⚠️ Tensão
  registrada, não resolvida: dois campos de versão por passo governando duas
  telas de texto é maquinaria cara pro conteúdo atual")
- Contradiz a spec: não — **apoia**
- Registro: a escolha de SwiftUI foi "reusa o molde que já existe", não uma
  rejeição de HTML; e a maquinaria que a spec nova aposenta já estava marcada
  como cara demais pelo próprio autor.

### A19 — `showSettings` é `private`; não existe API de abrir painel de fora
- Fonte: `Knobler/KnoblerApp.swift:1562` (`private func showSettings(pane:)`),
  `Knobler/PluginsSettingsPane.swift:195-197` (`abrir(_:)` roteia por
  `SettingsPane(rawValue:)` e por `KnoblerMain.delegate` pras peças sem painel)
- Contradiz a spec: não
- Registro: `abrirAjustes(painel)` da ponte precisa de um método exposto no
  `AppDelegate`, no mesmo caminho que a flag `--ajustes=` já usa. `SettingsPane`
  (`SettingsView.swift:16-19`) e `PluginID` (`Plugin.swift:19-22`) já são os
  enums de validação — o gate cruza contra eles, não contra lista nova.

### A20 — Sem sandbox, e `isInspectable` já nasce seguro
- Fonte: `tools/knobler.entitlements` ("Não é sandbox … nada de
  `com.apple.security.app-sandbox`"), `Knobler/Info.plist` (sem ATS, sem
  `CFBundleURLTypes`), https://webkit.org/blog/13936/ ("It defaults to `false`")
- Contradiz a spec: não
- Registro: nenhum entitlement novo é necessário. O esquema custom da spec é
  interno à `WKWebView` e **não** precisa de `CFBundleURLTypes` — é outro
  registro, e confundir os dois abriria o app pra URL externa.

### A21 — Default de `mediaTypesRequiringUserActionForPlayback` no macOS não é documentado
- Fonte: `WKWebViewConfiguration.h` (existe em macOS 10.12+, sem doc de default);
  o WebKit blog de política de autoplay cobre só iOS
- Contradiz a spec: não
- Registro: setar `[]` explicitamente custa uma linha e remove a dúvida.
  `allowsInlineMediaPlayback` é iOS-only — ignorar tutorial que mande usar.

## Fila do grill

Ordenada por dependência.

1. **A3 + A6** — esquema custom com handler de `Range`/206, ou `loadFileURL` com
   o endurecimento do Sparkle (JS de documento desligado, `WKContentRuleList`,
   allowlist de esquema)? Trava A4, A7, A15 e o tamanho do plano inteiro.
2. **A1** — a página convive com o `DevAvisos` ou o substitui como canal de
   anúncio? Trava a decisão de como quem ainda não atualizou fica sabendo.
3. **A10** — abrir pelo item de menu grava a versão vista ou não?
4. **A15** — o gate do HTML é `.mjs` (rápido, mas copia os enums) ou Swift (lê os
   enums de verdade)?
5. **A7** — `WKWebView` criada por abertura ou mantida viva? Depende de 1.
6. **A16** — fixar o vocabulário: "página" versus "seção de versão".
7. **A9** — a régua editorial aceita a crítica ao modal automático, ou vale um
   caminho menos intrusivo na primeira abertura?

Fora da fila, como registro que o plano herda: A2 (reusa `isNewer`, gate arrasta
o `Updater`), A5, A8, A11, A12, A13, A14, A17, A19, A20, A21.
