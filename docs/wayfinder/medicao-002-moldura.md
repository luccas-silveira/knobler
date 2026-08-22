# Medição 002 — Moldura contra conteúdo

Método: para cada `case` de `currentSize` (`Knobler/NotchView.swift:376-466`) foi lido
todo identificador de estado (não-constante) que a expressão de retorno lê, direta ou
indiretamente (via `closedHasContent`, `alturaDaSecao`, `larguraDoCard`). Esse conjunto é a
Lista 1. A Lista 2 é toda chamada `.animation(_:value:)` encadeada diretamente em
`interactiveNotch` (`Knobler/NotchView.swift:295-327`) — a única moldura que veste
`.mask(shape)`. A Lista 3 é a diferença simples entre as duas: identificadores que mudam
`currentSize` sem nenhuma `.animation(_:value:)` correspondente na cadeia do
`interactiveNotch`. Toda contagem abaixo tem o comando `rg`/`grep` que a reproduz em
`## Verificação`.

## Lista 1 — entradas que alteram `currentSize`

`private var currentSize: CGSize` começa em `Knobler/NotchView.swift:376` e tem um `switch
mode` até `:466`. `mode` é a própria chave do switch, então entra na lista.

| # | Identificador | Onde `currentSize` o lê | Caso |
|---|---|---|---|
| 1 | `mode` | `NotchView.swift:378` | chave do `switch` |
| 2 | `wingsVisible` (via `closedHasContent`, `NotchView.swift:196`) | `NotchView.swift:380` | `.closed` |
| 3 | `vm.activity` (via `closedHasContent`, `NotchView.swift:196`) | `NotchView.swift:380` | `.closed` |
| 4 | `vm.micInUse` (via `closedHasContent`, `NotchView.swift:196`) | `NotchView.swift:380` | `.closed` |
| 5 | `noteBadge` (via `closedHasContent`, `NotchView.swift:196`) | `NotchView.swift:380` | `.closed` |
| 6 | `vm.hasRealNotch` | `NotchView.swift:381`, `:391` | `.closed`, `.hud`/`.dictation`/`.pomodoro` |
| 7 | `vm.notchSize` (`.width`/`.height`) | `NotchView.swift:383-385`, `:388`, `:391-392` | `.closed`, `.hud`/`.dictation`/`.pomodoro` |
| 8 | `vm.focus` | `NotchView.swift:402`, `:411` | `.music` (`alturaDaSecao`, `larguraDoCard`) |
| 9 | `shelf.preview` | `NotchView.swift:403` | `.music` (`alturaDaSecao(preview:)`) |
| 10 | `vm.mirrorOn` | `NotchView.swift:404` | `.music` (`alturaDaSecao(espelhoLigado:)`) |
| 11 | `linkAberto` → `linkPreview.hosted(by:)` (`NotchView.swift:77`) | `NotchView.swift:405`, `:412` | `.music` (`alturaDaSecao(linkAberto:)`, `larguraDoCard`) |
| 12 | `vm.calendarAviso` | `NotchView.swift:406` | `.music` (`alturaDaSecao(eventoProximo:)`) |
| 13 | `vm.activeNotification?.actionTitles` | `NotchView.swift:415` | `.notification` |
| 14 | `vm.incoming?.allowReply` | `NotchView.swift:419` | `.message` |
| 15 | `vm.incoming?.mediaHeight` | `NotchView.swift:421` | `.message` |
| 16 | `agentRequestStore.state.active` | `NotchView.swift:430` | `.question` |
| 17 | `askStore.state.active` | `NotchView.swift:430`, `:437` | `.question` |
| 18 | `agentRequestExpanded` | `NotchView.swift:434` | `.question` |
| 19 | `askStore.state.page` | `NotchView.swift:440` | `.question` |
| 20 | `askHeight` | `NotchView.swift:449` | `.question` |

Constantes citadas no brief que compõem os números acima (não mudam em runtime, mas são
os valores somados): `alturaDaSecao` (`NotchView.swift:122-138`), `noteEditorHeight`
(`:95`), `shelfPreviewHeight` (`:118`), `espelhoDesligadoHeight` (`:121`), `linkWebHeight`
(`:106`), `linkHeaderHeight` (`:107`), `sectionStripHeight` (`:1006`),
`HistoryListView.listHeight` (`HistoryListView.swift:15`, valor 260),
`AnnotationDeckView.alturaDaGrade` (`AnnotationDeckView.swift:36`, valor 106).

**20 identificadores dinâmicos** alimentam `currentSize` (linha 1-20 da tabela).

## Lista 2 — `.animation(_:value:)` do `interactiveNotch`

`Knobler/NotchView.swift:295-327`, sete chamadas encadeadas direto no
`interactiveNotch` (não em `notch`, nem em nenhuma seção de conteúdo):

| # | Linha | Valor medido |
|---|---|---|
| 1 | `NotchView.swift:320` | `mode` |
| 2 | `NotchView.swift:321` | `wingsVisible` |
| 3 | `NotchView.swift:323` | `noteBadge` |
| 4 | `NotchView.swift:324` | `vm.micInUse` |
| 5 | `NotchView.swift:325` | `askStore.state.active?.id` |
| 6 | `NotchView.swift:326` | `agentRequestStore.state.active?.id` |
| 7 | `NotchView.swift:327` | `askStore.state.page` |

**7 chamadas de `.animation(_:value:)`** no `interactiveNotch`.

## Lista 3 — diferença (Lista 1 − Lista 2)

`askStore.state.active` (item 17) é coberto pelo `.id` do item 5, e
`agentRequestStore.state.active` (item 16) pelo `.id` do item 6 — contam como cobertos.
Sobram **13 identificadores** que mudam `currentSize` sem nenhuma `.animation(_:value:)`
correspondente na cadeia do `interactiveNotch`:

| Identificador | Linha em `currentSize` | Delta de altura possível |
|---|---|---|
| `vm.activity` | `NotchView.swift:380` | não numérico — muda a largura das asas fechadas (±`wingWidth*2`, `:144`=44pt → 88pt), não a altura |
| `vm.hasRealNotch` | `NotchView.swift:381`, `:391` | evento de display, não de interação — baixa frequência |
| `vm.notchSize` | `NotchView.swift:383-385`, `:388`, `:391-392` | evento de display (`KnoblerApp.swift:1182`), não de interação |
| `vm.focus` | `NotchView.swift:402`, `:411` | até 212 pt (272 mensagens − 60 atividade) |
| `shelf.preview` | `NotchView.swift:403` | 112 − 76 = 36 pt |
| `vm.mirrorOn` | `NotchView.swift:404` | 202 − 96 = 106 pt |
| `linkAberto` | `NotchView.swift:405`, `:412` | `linkWebHeight + 24` (438 pt em 780 de largura) − 96 = **342 pt** |
| `vm.calendarAviso` | `NotchView.swift:406` | 150 − 128 = 22 pt |
| `vm.activeNotification?.actionTitles` | `NotchView.swift:415` | 36 pt |
| `vm.incoming?.allowReply` | `NotchView.swift:419` | 108 − 72 = 36 pt (+ `mediaHeight`) |
| `vm.incoming?.mediaHeight` | `NotchView.swift:421` | `mediaHeight + 6`, sem teto conhecido no arquivo |
| `agentRequestExpanded` | `NotchView.swift:434` | 156 pt |
| `askHeight` | `NotchView.swift:449` | medido do conteúdo real via `PreferenceKey` — sem teto fixo, é a própria causa da divergência quando o card cresce |

`linkAberto` é a maior transição isolada: `Self.linkWebHeight` depende de
`linkContentWidth` (`NotchView.swift:103`, `linkCardWidth − 44` = 736) na proporção 9:16
(`:106`), então 414 pt (exato — 736 × 9/16 não tem resto) + `linkHeaderHeight` (24,
`:107`) = 438 pt contra os 96 pt do `espelhoDesligadoHeight` usado quando o link está
fechado (`:136`).

## O que isso não é

Os dois precedentes citados no ticket (`closedHasContent`, `NotchView.swift:193-194`, e
`alturaDaSecao`, `:96-98`) já estão fechados: hoje só existe UMA função por caso
(`closedHasContent` para o fechado, `alturaDaSecao` para o aberto) e tanto o conteúdo
quanto `currentSize` chamam essa mesma função — não há mais duas contas separadas que
podem divergir em valor. O que sobra é a Lista 3: o **momento** em que a moldura muda de
tamanho não tem curva de animação amarrada a 13 dos 20 gatilhos, enquanto o conteúdo pode
ter a própria (`expandedContent` anima `vm.focus` sozinho, com curva e duração diferentes
da `morphAnimation` do `interactiveNotch` — ver abaixo). É a hipótese do mapa, agora com
números: focus, shelf.preview, mirrorOn, linkAberto, calendarAviso, activeNotification,
incoming e agentRequestExpanded podem trocar de valor com o modo PARADO (sem trocar
`mode`), e nesses 8 casos a moldura não tem `.animation(_:value:)` nenhuma amarrada — o
SwiftUI aplica a transação ambiente do que disparou a mudança, não a `morphAnimation`.

Achado concreto de curva divergente: `expandedContent` (o conteúdo de `.music`) tem sua
própria animação de `vm.focus` — `.animation(.easeOut(duration: 0.3), value: vm.focus)`
em `NotchView.swift:998` — presa à `VStack` do conteúdo, não ao `interactiveNotch`. Quando
`vm.focus` muda, o conteúdo anima em 0.3s `easeOut`; a moldura (`currentSize`, que também
lê `vm.focus` nas linhas 374 e 383) não tem animação equivalente na cadeia do
`interactiveNotch` — item 8 da Lista 3. Moldura e conteúdo trocam de seção em transações
de animação diferentes, exatamente o mecanismo que o mapa registrou como hipótese.

## Verificação

```bash
# Lista 1 — região de currentSize
sed -n '376,466p' Knobler/NotchView.swift

# Lista 2 — .animation(_:value:) do interactiveNotch (região 295-327)
sed -n '295,327p' Knobler/NotchView.swift | grep -n '\.animation('
# → 7 ocorrências (linhas relativas 26,27,29,30,31,32,33 = absolutas 320,321,323,324,325,326,327)

# confirma que NENHUMA delas mede vm.focus, shelf.preview, vm.mirrorOn, linkAberto,
# vm.calendarAviso, vm.activeNotification, vm.incoming ou agentRequestExpanded
sed -n '295,327p' Knobler/NotchView.swift | grep -n '\.animation(' \
  | grep -Ec 'focus|shelf\.preview|mirrorOn|linkAberto|calendarAviso|activeNotification|incoming|agentRequestExpanded'
# → 0

# animação separada do conteúdo, presa a vm.focus, fora do interactiveNotch
grep -n '\.animation(.*value: vm\.focus)' Knobler/NotchView.swift
# → NotchView.swift:998 (dentro de expandedContent, não de interactiveNotch)

# constantes citadas no brief
grep -n 'static let noteEditorHeight\|static let shelfPreviewHeight\|static let espelhoDesligadoHeight\|static var linkWebHeight\|static func alturaDaSecao' Knobler/NotchView.swift

# precedentes já fechados (comentários)
grep -n 'quando$\|divergiam, o conteúdo desenhava fora da moldura\|soma$\|combinatória no' Knobler/NotchView.swift

# deltas de altura da Lista 3 — recalcula todos a partir dos números fonte
# (linhas 124-134 de alturaDaSecao, mais wingWidth em :141), não só o do link
sed -n '127,137p' Knobler/NotchView.swift
grep -n 'private let wingWidth' Knobler/NotchView.swift
python3 -c "
musica=118; pomodoro_com=150; pomodoro_sem=128; atividade=60
shelf_preview=112; shelf_grade=76
espelho_ligado=202; espelho_desligado=96
mensagens=272
link_aberto=round((780-44)*9/16)+24; link_fechado=espelho_desligado
notif_com=36; incoming_tall=108; incoming_curto=72
wing=44
print('vm.focus, delta max (mensagens-atividade):', mensagens-atividade)
print('shelf.preview, delta (112-76):', shelf_preview-shelf_grade)
print('vm.mirrorOn, delta (202-96):', espelho_ligado-espelho_desligado)
print('linkAberto, altura aberta:', link_aberto)
print('linkAberto, delta (438-96):', link_aberto-link_fechado)
print('vm.calendarAviso, delta (150-128):', pomodoro_com-pomodoro_sem)
print('vm.activeNotification?.actionTitles, delta:', notif_com)
print('vm.incoming?.allowReply, delta (108-72):', incoming_tall-incoming_curto)
print('vm.activity, largura das asas (wingWidth*2):', wing*2)
"
# → focus 212, shelf 36, mirror 106, link 438/342, calendario 22,
#   notification 36, incoming 36, asas 88 — bate com a tabela da Lista 3
```
