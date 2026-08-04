# Wizard de boas-vindas e dicas de atalho — design

Uma janela apresentada na primeira execução que diz **o que o Knobler é, onde
ele vive e quais são os dois atalhos globais** — as três coisas que o app não
consegue comunicar sozinho por ser `LSUIElement` (sem Dock, sem janela).

Decidido em 2026-08-03 numa sessão de grilling. Sai do `IDEIAS.md` ("Wizard de
primeira execução" + "Dicas de hotkeys"), fundindo os dois itens num só.

## O que o backlog pedia e não é o que vai ser feito

O `IDEIAS.md` pedia um wizard que "pergunta minimal setup (Spotify login?,
ativar ditado?, ativar mensagens?) e vai automatizando". Auditado contra o
código, isso não existe como descrito:

- **Mensagens LAN não tem toggle de liga/desliga.** O painel Mensagens é
  `IdentitySettingsView` — nome e avatar, só. Não há o que "ativar".
- **Ditado e API local já nascem ligados.** `flag()` na `AppSettings.init`
  (`AppSettings.swift:222`) devolve `true` quando a chave não existe, e ambos
  passam por ela. Perguntar "quer ativar?" seria pedir confirmação de um sim
  que já está dado.
- **Spotify não tem login.** A mídia chega pelo MediaRemote; não há conta a
  conectar.

Logo o wizard **não escreve nada** em `AppSettings`. É informativo. O passo de
toggles foi projetado e cortado no mesmo grilling, quando o código desmentiu a
premissa.

## O que já existe (não confundir com trabalho)

| Peça | Onde |
|---|---|
| Onboarding de permissões na 1ª execução | `apresentarPermissoesSeNecessario()`, `KnoblerApp.swift:565` |
| Chave "já apresentei" no UserDefaults | `onboarding.permissoes.apresentado` |
| Molde de `NSWindow` com `NSHostingView` | `showSettings()`, `KnoblerApp.swift:1302` |
| Pedido de permissão por caso | `Permission.request(completion:)`, `Permissions.swift:193` |
| Aviso persistente de Acessibilidade faltando | `statusItem` (`:1066`) + item de menu (`:1081`) |
| Flag de CLI pra abrir UI sem estado | `--ajustes[=<painel>]` (`:555`) |

## Forma

`NSWindow` própria, não um painel de Ajustes. O molde é o `showSettings`:
`NSHostingView`, `isReleasedWhenClosed = false`, `makeKeyAndOrderFront` +
`NSApp.activate(ignoringOtherApps: true)`.

## Fluxo na primeira execução

```
launch → wizard → wizard fecha → painel Permissões
```

`Permission.promptAccessibilityOnce()` **sai** do
`applicationDidFinishLaunching`. Quem pede Acessibilidade passa a ser o painel
Permissões, pelo `request(completion:)` que ele já tem.

Consequência aceita: entre o launch e o fechamento do wizard, o interceptor de
notificação e o gatilho do ditado ficam sem Acessibilidade — mudos. A
[pesquisa](2026-08-03-boas-vindas-research.md) mostrou que isso se resolve
sozinho: os três consumidores de Acessibilidade repolam o trust a cada 3 s e se
religam sem relaunch. E quem
fecha o painel sem conceder fica sem a permissão; isso já está coberto pelo
aviso permanente no `statusItem` e pelo item "⚠ Ditado precisa de
Acessibilidade…" no menu. Ninguém fica sem caminho de volta.

O gatilho de saúde da instalação (`Permission.installIssue != nil`, que hoje
reapresenta o painel mesmo com o onboarding já visto) continua sendo do painel
Permissões e **não** passa pelo wizard nem pelo versionamento. Instalação em
quarentena não deve reabrir uma tela de boas-vindas.

## Passos

Dois, ambos informativos:

1. **O que é o Knobler e onde ele vive.** O notch responde ao mouse; o app não
   tem Dock nem janela; o acesso é o ícone da barra de menus. Mais uma linha
   avisando que Mensagens te anuncia na rede local com o nome do Mac — não há
   como não aparecer, então a hora de dizer é essa.
2. **Os dois atalhos globais.** ⌥ direita = ditado (`VolumeHUD.swift:180`),
   Control direito = anotação (`AnnotationModel.swift:42`).

Ficam de fora os atalhos contextuais (Esc na anotação e no Descanso, ⌘Z/⌘⇧Z/
Delete na anotação, ⌘-atalhos no preview de Link): quem já está no estado
descobre. Uma tabela com todos vira folha de referência que muda a cada atalho
novo — e, pela regra de versionamento abaixo, cada mudança reabriria o wizard
pra base inteira.

## Versionamento

`onboarding.versao: Int` no UserDefaults. Cada passo carrega **dois** números:

- `criadoEm` — versão em que o passo nasceu;
- `revisadoEm` — versão da última alteração relevante do conteúdo.

Um passo aparece se `max(criadoEm, revisadoEm) > versaoVista`. O cabeçalho é
"Novo" quando `criadoEm` disparou e "Atualizado" quando foi o `revisadoEm`.

No fim (ou no fechamento) grava a versão atual. **Lista filtrada vazia = o
wizard não abre.**

Um caminho de renderização só: instalação nova tem `versaoVista = 0` e vê
tudo; o filtro é a única coisa que muda entre um caso e outro.

⚠️ Tensão registrada, não resolvida: dois campos de versão por passo governando
duas telas de texto é maquinaria cara pro conteúdo atual. Ela se paga a partir
do terceiro passo.

## Migração da base instalada

Passo 1 (apresentação) tem `criadoEm: 1`; passo 2 (atalhos), `criadoEm: 2`.

Quem já tem `onboarding.permissoes.apresentado == true` migra para
`versaoVista = 1` — e portanto vê **só os atalhos**, que é justamente o que não
sabe. Instalação nova nasce em `0` e vê os dois passos. A migração é uma linha
lendo a chave velha; não há código de migração especial.

## Saída e reabertura

O X da janela e um botão **"Ignorar"** fazem a mesma coisa: gravam a versão
atual e fecham. Como nenhuma janela do projeto tem delegate hoje, o ponto de
gravação é um observer de `NSWindow.willCloseNotification` para essa janela — o
botão "Ignorar" só chama `close()` e cai no mesmo lugar. Fechar no passo 1 conta como visto — o
app não insiste com quem já dispensou.

A porta de volta é um item **"Boas-vindas…"** no menu da barra, logo acima de
"Ajustes do Knobler…".

## Código

Dois arquivos novos:

- **`Knobler/Onboarding.swift`** — os passos, `criadoEm`/`revisadoEm`, a função
  pura de filtragem e a chave do UserDefaults. **Sem `import SwiftUI` e sem
  `AppSettings`**: é o que faz o check compilar isolado, mesma razão que criou o
  `CalendarAviso` num arquivo sem dependência.
- **`Knobler/OnboardingView.swift`** — a janela e as duas telas.

Wiring em `KnoblerApp.swift`: trocar `apresentarPermissoesSeNecessario`, tirar
o `promptAccessibilityOnce` do launch, adicionar o item de menu, o
`windowWillClose` e a flag de CLI. Arquivo novo = `xcodegen generate`.

## Check

`tools/onboardingcheck.swift` sobre a função pura de filtragem, com entrada em
`tools/check.sh` (senão a CI não o vê). Casos:

- instalação nova (`versaoVista = 0`) → os dois passos;
- usuário em dia → nenhum passo, e portanto o wizard não abre;
- passo novo → só ele, cabeçalho "Novo";
- passo revisado → só ele, cabeçalho "Atualizado";
- base migrada (`versaoVista = 1`) → só os atalhos.

O erro que esse check existe pra pegar é silencioso nos dois sentidos: um
filtro errado ou nunca abre o wizard, ou o abre em todo launch.

## Documentação

- Flag **`--boas-vindas`** espelhando a `--ajustes`, pra abrir o wizard sem
  zerar UserDefaults a cada tentativa de captura.
- Duas PNGs em `docs/images/`, capturadas à mão com
  `screencapture -l<windowID>` — `NSWindow` real não renderiza no
  `tools/snapshot.sh`, mesma vala dos `settings-*.png`.
- `docs/onboarding.md` curto, com link no `docs/index.md`.
- Entrada em `## [Unreleased]` do `CHANGELOG.md`.
