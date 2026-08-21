# 002 — Auditar a moldura contra o conteúdo

Map: [O knob cortado ao meio](../map-corte-do-knob.md)
Type: `measure`
Status: fechado (2026-08-21)
Assignee: sdd-002
Blocked by: —

## Pergunta

Que valores mudam a altura do knob sem estarem na lista de animação, e onde a moldura
pode ficar menor que o conteúdo que ela recorta?

Inventário a produzir, com arquivo e linha:

1. Toda entrada que altera `currentSize` da `NotchView` — as constantes de
   `alturaDaSecao`, `noteEditorHeight`, `shelfPreviewHeight`, `espelhoDesligadoHeight`,
   `linkWebHeight`, o `notchSize` que vem do display, e o que mais aparecer.
2. Toda `.animation(_:value:)` aplicada ao `interactiveNotch` e o valor que ela mede.
3. A diferença entre as duas listas. É aí que moldura e conteúdo podem andar em
   transações diferentes.

Depois, cada caso em que o conteúdo pode pedir mais altura do que a `.mask(shape)`
concede. O comentário do `closedHasContent` já registra que isso aconteceu antes — "quando
divergiam, o conteúdo desenhava fora da moldura" —, e o de `alturaDaSecao` registra outro,
a soma combinatória que dava moldura menor que o conteúdo. Dois precedentes na mesma
matemática são o motivo desta auditoria existir.

O resultado é uma tabela de divergências, não um conserto. Consertar é a 004.

Documento auxiliar se a lista passar de meia página: `medicao-002-moldura.md`.

## Resolução

Medição completa em [`medicao-002-moldura.md`](../medicao-002-moldura.md).

Em números: `currentSize` (`Knobler/NotchView.swift:348-438`) lê **20 identificadores
dinâmicos**. O `interactiveNotch` (`:267-299`) tem **7** chamadas de
`.animation(_:value:)`, das quais todas as 7 caem dentro dos 20 (2 delas — os `.active`
de `askStore`/`agentRequestStore` — cobertas pelo `.id` correspondente). Sobram **13**
identificadores que mudam a moldura sem nenhuma `.animation(_:value:)` amarrada:
`vm.activity`, `vm.hasRealNotch`, `vm.notchSize`, `vm.focus`, `shelf.preview`,
`vm.mirrorOn`, `linkAberto`, `vm.calendarAviso`, `vm.activeNotification?.actionTitles`,
`vm.incoming?.allowReply`, `vm.incoming?.mediaHeight`, `agentRequestExpanded` e
`askHeight`.

Os dois precedentes que motivaram o ticket (`closedHasContent` e a soma combinatória de
`alturaDaSecao`) já estão fechados no código atual: hoje só existe uma função por caso, e
tanto o conteúdo quanto `currentSize` chamam a mesma função — não há mais duas contas que
podem divergir em *valor*. A divergência que sobra é de *transação*: 8 dos 13
identificadores (`vm.focus`, `shelf.preview`, `vm.mirrorOn`, `linkAberto`,
`vm.calendarAviso`, `vm.activeNotification?.actionTitles`, `vm.incoming?.allowReply`,
`agentRequestExpanded`) podem mudar com `mode` parado — sem trocar de caso no switch — e
nesse caso a moldura não tem curva de animação amarrada na cadeia do `interactiveNotch`.
Achado concreto: `expandedContent` anima `vm.focus` com a própria curva
(`.animation(.easeOut(duration: 0.3), value: vm.focus)`, `NotchView.swift:970`), separada
da `morphAnimation` do `interactiveNotch` — e `currentSize` lê `vm.focus` (`:374`, `:383`)
sem animação equivalente. Moldura e conteúdo trocam de seção em transações diferentes,
confirmando em código a hipótese do mapa.

A tabela de divergências (delta de altura por identificador, maior caso: `linkAberto`,
342 pt) está em `medicao-002-moldura.md`. Nenhum conserto foi aplicado — é trabalho da
004.
