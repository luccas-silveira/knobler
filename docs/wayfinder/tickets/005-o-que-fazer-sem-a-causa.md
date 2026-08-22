# 005 — O que fazer sem a causa

Map: [O knob cortado ao meio](../map-corte-do-knob.md)
Type: `grilling`
Status: fechado (2026-08-22)
Assignee: sessão 005 (grilling com o usuário)
Blocked by: 004

## Pergunta

A premissa de que uma varredura acharia a causa caiu. O que o mapa faz agora?

## Resolução

**Qual premissa caiu, e como se mediu.** O mapa nasceu assumindo que o corte se
reproduziria fora do app, e que a causa apareceria varrendo o espaço de estados. Três
varreduras depois, com o instrumento provado em cada uma:

| Varredura | Combinações | Cortes | Sensibilidade |
|---|---|---|---|
| [001](001-reproduzir-o-corte.md) — estado da interface | 35 | 0 | controle na `NotchView` real, 60,0 pt |
| [003.1](003.1-eventos-de-ambiente.md) — ambiente simulado | 43 | 0 | 3 de 8 transições |
| [004](004-o-codigo-que-ele-roda.md) — código real do usuário | 51 | 0 | **8 de 8**, persistente e transiente |

Não há mais varredura a fazer com este instrumento, e o limite que sobra não é ajustável:
fotografar um card de 530 pt custa ~200 ms, a cadência cai para 2–11 Hz, e um corte que
dure um quadro a 60 Hz cabe entre duas fotos.

**As rotas em disputa, com o custo real.** Quatro foram à mesa:

1. **Detectar, gravar e se curar.** O app verifica o invariante geométrico e, quando ele é
   violado, grava a prova e refaz o layout. Custo: código permanente no app, e uma
   verificação que roda no ciclo de desenho. Entrega alívio imediato **e** captura.
2. **Só o autodiagnóstico.** Grava e não conserta. Custo: o usuário continua vendo o corte
   até a causa aparecer. Revisita a decisão travada de não rodar build instrumentada — mas
   numa forma diferente, porque o código vai na build de sempre.
3. **Só o conserto defensivo.** Custo: fecha o mapa com a causa em aberto para sempre, e é
   o remendo cego que o usuário quis evitar desde a abertura.
4. **Parar.** Custo: entrega inventário, harness e três zeros, e nada muda para o usuário.

**Escolhida, e por quem.** **Rota 1**, escolhida pelo usuário em 2026-08-22. A diferença
entre ela e o remendo cego que ele rejeitou é o gatilho: o conserto só corre quando a
medição diz que o defeito está presente, e deixa prova de que estava.

**O que sobrevive das decisões anteriores.** A métrica é a **lacuna de topo**, e continua
sendo — "moldura menor que o conteúdo" está provada cega (003). O harness de
`tools/cortecheck/` e os seus controles seguem sendo o instrumento. Os dois achados
laterais da 004 continuam **não** sendo causa. O escopo dos eventos como suspeitos, aberto
na 003, cumpriu o papel e não precisa ser reaberto.

**O que muda no destino.** O destino do mapa dizia "causa identificada, corrigida e coberta
por gate". A causa não foi identificada, e o mapa passa a entregar detecção, prova e
autocura, com o gate na métrica viva. O `## Destino` foi reescrito para dizer isso — a
mudança é de escopo e tinha que ficar visível.

Nasce daqui o [006](006-aplicar-e-travar-o-gate.md), que era o gate e passa a ser as três
coisas.
