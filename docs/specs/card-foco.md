# Spec — Card aberto com foco único

Status: implementado (branch `feat/card-foco`, 2026-07-29)
Escopo: apenas o notch **expandido**. O notch fechado e a prioridade de
interrupções (`NotchViewModel.mode`) ficam como estão.
Pesquisa de viabilidade: `card-foco-pesquisa.md` — este spec já incorpora
as quatro correções que ela levantou.

## Problema

O card aberto empilha tudo que existe, sempre na mesma ordem. Em
`NotchView.musicContent` são cinco `if` independentes (pomodoro, espelho,
shelf, atividade, música) que não se excluem — com quatro ativos o card vira
uma torre. A ordem é arbitrária e não olha pra nada: um deploy que avançou
agora aparece abaixo de um shelf parado há três horas. E a altura é somada à
mão em `currentSize` com constantes que dependem de *quais* seções coexistem
(`height += hasMusic || hasShelf ? 46 : 60`), o que é combinatório e já
causou o bug de moldura menor que o conteúdo documentado no próprio código.

Antes disso, `expandedContent` ainda tem quatro ramos mutuamente exclusivos
(nota, histórico, Mensagens, stack) governados por regras diferentes: cortina,
swipe de dois dedos, `pageDots`.

Resultado: três mecanismos de navegação, duas noções de exclusividade e uma
ordem fixa.

## Modelo

O card aberto passa a ser **uma lista ordenada de seções + um índice de foco**.

Seções: `musica`, `atividade`, `shelf`, `pomodoro`, `espelho`, `mensagens`,
`historico`, `nota`.

- A seção em foco ocupa o card e **declara a própria altura**.
- **Todas** as seções ativas viram ícones numa faixa no rodapé, cada uma com um
  sinal vivo mínimo — inclusive a que está em foco, que aparece acesa (0,9 de
  opacidade) contra as demais apagadas (0,35). É o que dá noção de posição:
  sem o ícone da própria seção na faixa não dá pra saber onde você está.
- Clique num ícone troca o foco.

Isso substitui: os `if` empilháveis de `musicContent`, a aritmética de
`currentSize` pro modo `.music`, a supressão implícita Pomodoro→música,
os `pageDots` de duas abas e a cortina do histórico.

## Ordenação

Ordem efetiva = **ordem-base do usuário, com promoção por recência**,
calculada **uma única vez no momento em que o card abre** e congelada até
fechar.

1. Ordem-base vem dos Ajustes (drag-to-reorder), painel **Notch**.
2. Seções sem conteúdo (sem música, shelf vazio, pomodoro idle) saem da lista
   inteira — não aparecem nem como ícone.
3. Qualquer seção com **evento de transição** nos últimos **10 s** sobe pro
   topo, mantendo entre si a ordem de recência (mais recente primeiro).
4. O foco inicial é a primeira da lista resultante.

### Evento de transição

Não é "o estado mudou" — é uma lista fechada de transições por seção. A
distinção é obrigatória, não cosmética: `PomodoroState.remaining` muda a cada
segundo e o `MediaController` publica posição continuamente, então "mudou"
deixaria essas duas permanentemente promovidas e a regra degeneraria em
"pomodoro sempre no topo".

| Seção | Conta como evento | **Não** conta |
|-------|-------------------|---------------|
| musica | trocou a faixa; `isPlaying` virou | avanço da posição |
| pomodoro | mudou `phase` ou `runState` | tique do `remaining` |
| atividade | mudou `title`/`detail`; cruzou `done` | cada passo do `progress` |
| shelf | `items.count` mudou | — |
| espelho | `mirrorOn` virou | — |
| mensagens | mensagem nova | — |
| historico | notificação nova | — |
| nota | rascunho passou de vazio a não-vazio | cada tecla |

Cada seção carrega um `updatedAt` carimbado só nessas transições. Três fontes
já têm timestamp utilizável (`NotchActivity.updatedAt`,
`NotchNotification.date`, `PeerMessage.at`); as outras cinco ganham o campo —
todas têm setter único ou `didSet`.

Congelar na abertura é deliberado: nada se mexe debaixo do cursor, o alvo de
clique da faixa não muda de lugar, e como o card vive segundos a próxima
abertura já reflete o estado novo.

### Trava do foco

- Escolha manual (clique num ícone) trava o foco **até o notch recolher**.
- `NotchViewModel.typingNote == true` trava o foco na nota
  incondicionalmente: nem promoção, nem clique na faixa tiram. Isto preserva a
  regra hoje expressa como `if typingNote { return .music }` em
  `NotchViewModel.mode` — quando o campo sai da árvore o `.onDisappear` zera o
  foco, o painel larga a chave do teclado e as teclas seguintes vazam pro app
  da frente sem sinal nenhum. Perda de texto silenciosa.

## Faixa de ícones

Vive no rodapé, no slot hoje ocupado por `pageDots` (`NotchView.swift:809`) —
já é clicável e já tem o swipe de dois dedos mapeado.

Cada ícone carrega **um sinal vivo mínimo**, não um rótulo:

| Seção      | Sinal |
|------------|-------|
| atividade  | anel de progresso fino em volta do ícone (indeterminado = arco girando) |
| musica     | ponto aceso quando tocando; apagado quando pausada |
| pomodoro   | anel do tempo restante da fase (foco/pausa) |
| shelf      | contagem de itens |
| mensagens  | nenhum por enquanto — não existe contagem de não-lidas no store |
| historico  | contagem das últimas 24 h |
| espelho    | ícone sólido (ligado/desligado já é a presença) |
| nota       | ponto quando há rascunho |

Você perde o detalhe, não o glance.

## Altura

Cada seção expõe uma altura própria; o card anima entre elas.

| Seção | Altura |
|-------|--------|
| musica | 118 |
| atividade | 60 |
| shelf | 76 |
| pomodoro | 128 |
| espelho | 202 |
| mensagens | 272 |
| historico | `HistoryListView.listHeight + 12` |
| nota | `Self.noteEditorHeight + 20` |

`currentSize` pro modo `.music` vira `topInset + 10 + alturaDaSeçãoEmFoco +
faixa`. Os valores acima são os que já existem hoje nas constantes de
`currentSize` — nenhum é novo; eles só mudam de dono.

### O resultado precisa ser publicado

`NotchViewModel` ganha `@Published private(set) var cardHeight: CGFloat`,
escrito pelo mesmo cálculo acima. Isto **não é opcional**: o monitor de scroll
em `KnoblerApp.handleScroll` (`KnoblerApp.swift:667`) delimita a zona sensível
com altura literal —

```swift
let zoneHeight: CGFloat = vm.historyOpen ? 420 : (expanded ? 200 : ...)
```

— e o próprio código já avisa que os 200 são carga: o card da nota mede 198 pt,
sobram 2 pt. Com altura por seção (espelho 202, mensagens 272) o card passa dos
200 rotineiramente e a faixa de baixo sai da zona: o scroll ali deixa de ser
reconhecido. Hoje é caso de canto; sem `cardHeight` vira o caso comum.

Com `cardHeight` publicado, o monitor lê `vm.cardHeight + folga` e a dívida
`ponytail:` da tabela de números literais é paga em vez de agravada.

## Gestos

Aposentar `vm.tab` e a cortina do histórico deixa dois gestos órfãos em
`handleScroll`. Destino:

- **Horizontal > 50 pt com o card aberto** — hoje troca aba música ⇄ mensagens;
  passa a **percorrer a faixa de seções** (equivale a clicar no ícone vizinho),
  e portanto também **trava o foco**, igual ao clique. Com o card fechado o
  horizontal continua pulando faixa de música, como hoje.
- **Puxão vertical de 120 pt (cortina)** — aposentado. O histórico virou uma
  seção como as outras; um segundo caminho pra ele seria redundante.
  `NotchGesture.verticalTarget` perde o caso `.history` e o enum
  `ScrollTarget` fica com `.closed` / `.expanded`.
- **`scrollStartedInHistory`** (`KnoblerApp.swift:697`) — o handoff que entrega
  o eixo vertical à lista pra ela rolar de verdade continua existindo, com a
  condição reescrita de `vm.historyOpen` para `vm.focus == .historico`. As três
  guardas atuais (lista aberta, lista não-vazia, nota não hospedada nesta tela)
  se mantêm — sem elas o gesto morre na seção do histórico.

## Superfície de código

- **Novo** `NotchSectionOrder.swift`: uma func pura
  `ordenar(base:estados:agora:) -> [Section]` + a trava de foco. Sem import de
  AppKit, exatamente como `NotchGesture.swift` — é o que a torna testável.
- `NotchViewModel`: `@Published var focus: Section?`,
  `@Published var focusLocked: Bool`, `@Published private(set) var cardHeight`,
  e um `updatedAt` por seção (ver tabela de eventos de transição).
- `NotchView`: `expandedContent` vira um `switch focus`; `musicContent` some;
  `pageDots` vira `sectionStrip`.
- `KnoblerApp.handleScroll`: zona lê `vm.cardHeight`; horizontal percorre a
  faixa; `.history` sai do `ScrollTarget`.
- `MessageStore`: não existe noção de "não-lida" hoje — o sinal da faixa é
  "mensagens desde a última abertura do card", que é um contador no VM, não
  uma mudança no store.
- `NotchAPIServer`: `GET /status` passa a incluir a seção em foco. Custo quase
  zero e vira a forma de um script perguntar o que o notch está mostrando.
- `AppSettings`: `notchSectionOrder: [String]` em `UserDefaults`, com fallback
  pra ordem padrão quando a chave não existe ou traz uma seção desconhecida
  (versão futura pode acrescentar seções).
- `SettingsView`, painel Notch: lista drag-to-reorder.

## Fora de escopo

- Prioridade do notch fechado (`NotchViewModel.mode`) — inalterada.
- Frequência aprendida / persistência de uso. A promoção é por recência de
  estado, não por hábito.
- Teto de seções visíveis: com foco único não existe pilha pra limitar.

## Verificação

- `tools/sectionordercheck.swift` com `assert(...)`, registrado em
  `tools/check.sh` — é o padrão do repo (não há XCTest aqui; é assim que
  `NotchGesture` é testado). Casos: ordem-base respeitada em repouso; seção com
  evento há 3 s sobe; evento há 30 s não sobe; seção sem conteúdo some;
  `typingNote` vence tudo; **tique de `remaining`/posição não promove**.
- Snapshots: a lista de cenários é **reescrita**, não estendida — o eixo de
  variação deixa de ser "quais seções coexistem" e passa a ser "qual seção em
  foco × a faixa". Entram no harness todas **exceto** `historico` e
  `mensagens` (ambas usam `ScrollView`, que não renderiza offscreen — ver
  CLAUDE.md) e `espelho` (câmera real). Essas três seguem de captura manual.
  `NotchSectionOrder.swift` entra na lista de arquivos de `tools/snapshot.sh`.
- Manual: abrir o card com deploy em progresso + música tocando + shelf cheio
  e confirmar que o deploy está em foco e os outros dois são ícones com
  sinal.
