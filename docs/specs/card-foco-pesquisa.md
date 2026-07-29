# Pesquisa — Card aberto com foco único

Levantamento do código existente pra checar cada premissa do spec
`card-foco.md`. Divide-se em: o que confirma, o que **contradiz**, e o que o
spec não previu.

## 1. Timestamps: a premissa central não se sustenta como escrita

O spec diz "seção cujo estado mudou nos últimos 10 s sobe". O que existe hoje:

| Seção | Fonte | Timestamp? |
|-------|-------|-----------|
| atividade | `NotchActivity.updatedAt` | ✅ existe |
| historico | `NotchNotification.date` (`NotchNotification.swift:39`) | ✅ existe |
| mensagens | `PeerMessage.at` (`Peer.swift:32`) | ✅ existe |
| shelf | `ShelfStore.items: [URL]` | ❌ só o array |
| musica | `MediaController.state` | ❌ nenhum |
| pomodoro | `PomodoroState` | ❌ nenhum |
| espelho | `vm.mirrorOn` | ❌ nenhum |
| nota | `QuickNote.text` | ❌ nenhum |

Três já servem de graça. Quatro precisam de um `updatedAt` novo — barato,
todos têm `didSet`/setter único (`ShelfStore.items` já tem `didSet`).

### O furo real: tick ≠ mudança

`PomodoroState.remaining` muda **a cada segundo**. `MediaController` publica
`position` continuamente enquanto toca. Se `updatedAt` for carimbado a cada
publicação, Pomodoro e música ficam permanentemente "mudados nos últimos 10 s"
e vencem a promoção pra sempre — a regra de recência degenera em "pomodoro
sempre no topo".

**Correção necessária no spec:** carimbar `updatedAt` só em **transições de
identidade/estado**, não em progresso:

- musica: mudou a faixa, ou `isPlaying` virou
- pomodoro: mudou `phase` ou `runState` (não `remaining`)
- atividade: mudou `title`/`detail`, ou cruzou `done` (não cada `progress`)
- shelf: `items.count` mudou
- espelho: `mirrorOn` virou
- mensagens/historico: item novo

Ou seja, a promoção precisa de uma noção explícita de **evento**, não de
"algo mudou". Isso é uma decisão de design que o spec engoliu sem nomear.

## 2. O gesto de scroll vai quebrar — e já é dívida documentada

`KnoblerApp.handleScroll` (`KnoblerApp.swift:646-745`) define a zona sensível
ao scroll com **altura literal**:

```swift
let zoneHeight: CGFloat = vm.historyOpen ? 420 : (expanded ? 200 : notchSize.height + 10)
```

O código já traz um aviso ⚠️ dizendo que os 200 são carga: o card da nota mede
198 pt e sobram 2 pt de folga. Com **altura por seção** (espelho 202,
mensagens 272), o card passa dos 200 rotineiramente e a faixa de baixo sai da
zona — o scroll ali deixa de ser reconhecido. Hoje é um caso de canto; com o
spec vira o caso comum.

O comentário `ponytail:` explica por que é literal: o monitor roda fora do
SwiftUI e não lê o tamanho renderizado. **A solução é o próprio spec**: se
cada seção declara a altura, o VM sabe a altura antes da view desenhar —
`vm.cardHeight` publicado, e o monitor lê dali. Isso *paga* a dívida em vez
de agravá-la, mas precisa estar no spec como tarefa.

## 3. Colisão de gestos: três gestos, uma faixa

Hoje o card aberto tem três gestos distintos, todos em `handleScroll`:

- vertical > 24 pt → abre; < −24 pt → fecha (`NotchGesture.verticalTarget`)
- vertical > 120 pt na mesma passada → **cortina do histórico**
- horizontal > 50 pt → **troca aba** música ⇄ mensagens (`vm.tab`)

O spec aposenta `vm.tab` e o conceito de cortina (histórico vira seção). Isso
deixa dois gestos órfãos e uma pergunta não respondida: **o horizontal passa a
percorrer a faixa de seções?** Se sim, colide com o horizontal no notch
*fechado*, que hoje pula faixa de música (`KnoblerApp.swift:734+`) — mesmo
eixo, significados diferentes conforme o estado. Funciona, mas é exatamente o
tipo de coisa que o usuário não descobre.

Também some `scrollStartedInHistory` (`KnoblerApp.swift:697`), o handoff que
entrega o eixo vertical à lista quando a cortina está aberta. Com histórico
como seção focada, a condição vira `focus == .historico` — mesma lógica, outro
nome. As três guardas dela (`historyOpen && !items.isEmpty && !hosted(by:)`)
precisam ser reproduzidas ou o gesto morre na seção do histórico.

## 4. Testes: o spec pediu a ferramenta errada

Não existe XCTest neste repo. O padrão é `tools/<nome>check.swift` com
`assert(...)` puro, orquestrado por `tools/check.sh` (é assim que
`NotchGesture` é testado, junto com quicknote, history, updater, webhook…).

**Correção:** o teste da função de ordenação é `tools/sectionordercheck.swift`
registrado em `tools/check.sh`, não um alvo de teste novo. Isso também
significa que `NotchSectionOrder.swift` precisa ser um arquivo puro sem
dependência de AppKit — como `NotchGesture.swift` já é.

## 5. Snapshots: precisa de trabalho no harness

`tools/snapshot.sh` compila 50+ arquivos numa lista manual — adicionar
`NotchSectionOrder.swift` é uma linha. Mas:

- Os cenários hoje são combinações de estado (`closed-music`,
  `expanded-activity-only`…). Com foco único, o eixo de variação muda: passa a
  ser **uma seção em foco × a faixa**. A lista de cenários precisa ser
  reescrita, não estendida.
- Confirmado o caveat do CLAUDE.md: `historico` (`HistoryListView` usa
  `ScrollView`) e `mensagens` (`MessagesView` idem) não renderizam offscreen.
  Ficam de captura manual.
- `espelho` depende de câmera real — já é assim hoje.

Sobram ~5 seções snapshotáveis, mais a faixa em si.

## 6. Ajustes: encaixe limpo

`SettingsPane` (`SettingsView.swift:16`) já tem o caso `.notch`. `AppSettings`
persiste tudo com o mesmo padrão `@Published + didSet + UserDefaults` — um
`[String]` cabe direto (`ShelfStore` já guarda `[String]` assim). Nenhum
obstáculo.

Ponto de atenção: `List { }.onMove` no macOS renderiza, mas o painel de
Ajustes **não** é coberto por `tools/snapshot.sh` (é screenshot manual, por
causa do `NavigationSplitView`) — então a validação visual do reorder é
manual, como os outros painéis.

## 7. Pontos menores

- `NotchAPIServer` expõe `GET /status`. Faz sentido incluir a seção em foco ali
  — custo quase zero, e vira a forma de um script perguntar o que o notch está
  mostrando.
- `MessageStore` **não tem contagem de não-lidas** — só `threads`. O sinal
  "não-lidas" da faixa não existe hoje; ou se cria a noção de lido, ou o sinal
  vira "quantidade de mensagens desde a última abertura do card".
- `NotchViewModel` tem 8 `@Published` que só existem pra coordenar exclusividade
  entre modos (`historyOpen`, `tab`, `mirrorOn`, `airpodsCard`, `updateCard`).
  O spec elimina `historyOpen` e `tab`; os outros três descrevem o notch
  *fechado* e ficam.

## Impacto no spec

Quatro coisas a corrigir/acrescentar em `card-foco.md`:

1. Promoção é por **evento de transição**, não por "mudou" — com a tabela do
   §1 dizendo o que conta como evento em cada seção.
2. Acrescentar tarefa: `vm.cardHeight` publicado, e `handleScroll` lê dali em
   vez do literal 200/420. Sem isso o gesto quebra.
3. Decidir o destino dos gestos órfãos (horizontal, puxão de 120 pt).
4. Teste é `tools/sectionordercheck.swift` + `check.sh`, não XCTest; e os
   cenários de snapshot são reescritos, não estendidos.

Nada disso derruba o desenho. O item 1 é o único que muda o *modelo*; os
outros três são custo de implementação que o spec estava subestimando.
