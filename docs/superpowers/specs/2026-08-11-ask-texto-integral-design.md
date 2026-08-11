# Card de pergunta: texto integral

Data: 2026-08-11
Área: `Knobler/Ask.swift` (`AskCardView`)

## Problema

O card do `POST /ask` trunca o que o usuário precisa ler para responder. Hoje a
pergunta usa `.lineLimit(2)` no header e cada descrição de opção usa
`.lineLimit(2)` na linha da opção. Perguntas longas — o caso real que motivou
isto foi uma fila de grill de 16 perguntas — chegam cortadas em `…`, e as
descrições que carregam o trade-off entre as opções chegam cortadas também. Não
dá para responder corretamente sem ver o texto.

O card já é agnóstico à ferramenta de origem: qualquer processo que faça
`POST /ask` no formato `AskUserQuestion` aparece nele, e o card não sabe quem
mandou (`source` é só um rótulo opcional no header). Esta mudança é puramente de
exibição e não toca no contrato da API.

## Comportamento

A **pergunta** aparece sempre por inteiro, sem `lineLimit`. Não depende de hover:
o cabeçalho não muda de altura enquanto o mouse percorre a lista.

A **descrição da opção sob o cursor** aparece por inteiro. As demais opções
continuam em 2 linhas. Ao sair da opção, ela volta a 2 linhas.

O card **cresce em altura** o quanto for preciso. Sem rolagem interna, sem teto.

Os dois tetos que hoje impediriam isso caem:

- `Knobler/KnoblerApp.swift:1198` — a janela do notch deixa de ser
  `NSSize(width: 700, height: 520)` e passa a ter a altura utilizável da tela
  (`screen.visibleFrame.height`). A janela é transparente fora do card e não
  intercepta clique, então cobrir mais tela não muda o comportamento; ela vira
  uma tela de desenho grande e quem manda na altura passa a ser só o card.
  Nenhum redimensionamento por card, nenhuma animação de janela.
- `Knobler/NotchView.swift:417` — o `min(height, 500)` do card `.question` sai.

O painel lateral de `preview` fica inalterado: quando alguma opção traz
`preview`, a lista continua com 250pt de largura e a expansão in-place acontece
dentro dela.

A altura do card acompanha o hover **em tempo real**: entrar numa opção expande a
descrição e o card cresce; sair recolhe. A transição usa a animação que
`AberturaDoCard` já aplica sobre a altura.

No extremo em que nem a tela inteira comporta o card, ele para de crescer na
altura utilizável da tela e o excedente é cortado pela máscara. Não entra
rolagem. É um caso que exige pergunta e opções descomunais ao mesmo tempo, e
resolver especulativamente custa mais que o corte.

## Implementação

Em `Knobler/Ask.swift`:

- `header(question:)` — remover `.lineLimit(2)` do `Text(question.question)`.
- `optionRow(_:question:)` — o `.lineLimit` da descrição passa a ser `nil`
  quando `hovered == option.label`, e `2` caso contrário.

O estado `hovered` já existe e já é atualizado pelo `.onHover` da linha; nenhum
estado novo entra em `AskCardView`.

Em `Knobler/NotchView.swift`:

- O `AskCardView` reporta a altura real que renderizou (`onGeometryChange`), e
  `NotchView` guarda esse valor num `@State`.
- `currentSize`, no caso `.question` com `askStore.state.active`, usa a altura
  medida quando existir, com `topInset` somado, e cai na fórmula atual
  (`46 + opções*48 + 44`) enquanto não houver medida — ela vira só o valor de
  partida do primeiro frame. O `min(height, 500)` sai; entra um clamp na altura
  utilizável da tela.
- Não há ciclo de layout: o pai impõe apenas a largura ao card
  (`NotchView.swift:679`), nunca a altura.

Em `Knobler/KnoblerApp.swift`:

- A janela passa a ter a altura utilizável da tela, conforme a seção acima.

## Verificação

`tools/snapshot.sh` gera `ask-simple.png` e `ask-multiselect.png`. Eles cortam
antes do campo de texto (o `TextField` não renderiza offscreen), mas cobrem
header e lista de opções, que é exatamente o que muda aqui. O harness renderiza
sem cursor, então o estado de hover não sai no PNG por padrão — a validação do
texto expandido é inspeção visual no app rodando, com um `POST /ask` de
descrição longa.

Os dois cenários Ask em `tools/main.swift:316-343` usam o `frameHeight` default
de 240pt (`tools/main.swift:64`), abaixo do que o card já pede hoje (~248/282).
Sobem para 420, como `tools/main.swift:302`, `:394` e `:660` já fazem pelos
mesmos motivos.

`tools/askcheck.swift` valida só o reducer (`AskStore`/`AskState`/`AskAction`) e
não é afetado. Nenhum gate de `tools/check.sh` cobre layout de view; nenhuma
entrada nova é necessária. A auto-medição não tem check hermético possível — é
inspeção visual, como o resto do layout.

## Fora de escopo

Rolagem interna no card. Qualquer mudança no contrato de `POST /ask`. O painel de
`preview`. Redimensionar a janela do notch por card.

## Decisões do grill

- **A3** — a janela cede: `KnoblerApp.swift:1198` passa de 520pt fixos para a
  altura utilizável da tela, e o `min(height, 500)` de `NotchView.swift:417` sai.
  Motivo: os dois tetos estão colados e nenhum outro código depende dessas
  constantes; a janela é transparente fora do card e não intercepta clique, então
  cobrir mais tela não muda comportamento. Descartado redimensionar a janela por
  card — traria animação de janela sem ganho.
- **A1** — o card se mede e reporta a altura; a fórmula de `NotchView.swift:414`
  vira valor de partida. Motivo: medir o texto à mão (mapear `.footnote`/
  `.caption2` para `NSFont` e chamar `boundingRect`) seria reimplementar o layout
  do SwiftUI ao lado do SwiftUI, e as duas contas divergem no primeiro `padding`
  que alguém mexer. Aceito o custo: a altura deixa de ter check hermético.
- **A2** — no extremo em que o card passa da tela, corta pela máscara, sem
  rolagem. Motivo: exige pergunta e opções descomunais ao mesmo tempo; com a
  janela do tamanho da tela o caso praticamente não ocorre.
- **A4** — a altura acompanha o hover em tempo real, animada por
  `AberturaDoCard`. Motivo: sai de graça da auto-medição de A1, e dimensionar
  pelo pior caso deixaria folga morta permanente no card.
- **A5** — `frameHeight` de `ask-simple` e `ask-multiselect` sobe para 420.
  Motivo: o default de 240 já cortava antes desta mudança.
- **A6, A7** — nada muda. Motivo: `askcheck` só cobre o reducer e o card é
  renderizado num único lugar; ambos confirmam a spec.
