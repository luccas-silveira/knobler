# 002 — Auditar a moldura contra o conteúdo

Map: [O knob cortado ao meio](../map-corte-do-knob.md)
Type: `measure`
Status: aberto
Assignee: —
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
