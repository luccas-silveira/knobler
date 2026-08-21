# Mapa: O knob cortado ao meio

Aberto em 2026-08-21

## Destino

A causa do knob aparecer cortado ao meio está identificada, corrigida e coberta por um
gate hermético em `tools/check.sh` que falha se o defeito voltar.

O mapa cobre o **desenho** do notch — moldura, máscara e animação. Não cobre a posição da
`NotchWindow` na tela, multi-monitor, tela cheia nem sleep: o defeito se conserta com um
ciclo de expandir/recolher, então a janela está certa e o estado de desenho é que quebra.

## Notas

O sintoma, nas palavras do usuário: *"às vezes pisca e fica aparecendo apenas a metade de
baixo, e precisa fechar e reabrir"*. A metade que sobra fica na posição certa — é corte,
não deslocamento.

Decisões travadas no grilling de abertura, cada uma com o porquê:

**Recupera com expandir/recolher.** Não exige reiniciar o app. Logo o `setFrame` do
`placeWindows` está correto e o alvo é a árvore SwiftUI da `NotchView`.

**Acontece nas duas telas** — notch físico do MacBook e ilha simulada em monitor externo.
Descarta hipótese ligada a `hasRealNotch` ou a `notchSize` do display externo.

**Acontece nos dois estados** — pilulinha fechada e card aberto. Descarta hipótese
restrita ao layout das seções expandidas.

**Várias vezes por dia**, sem gatilho percebido.

**Sem build instrumentada.** O usuário não quer rodar uma versão de diagnóstico no dia a
dia. Toda a investigação sai de harness e leitura de código. Esta é a decisão que mais
restringe o mapa — não a re-proponha sem falar com ele.

Hipótese de trabalho, escrita aqui para não se perder e **não** para ser assumida como
verdade: `currentSize` da `NotchView` muda por valores que não estão na lista de
`.animation(_:value:)` do `interactiveNotch` (que mede `mode`, `wingsVisible`,
`noteBadge`, `micInUse` e o estado do `askStore`). Moldura e conteúdo animando em
transações diferentes deixariam exatamente um quadro de estado intermediário — o piscar.

## Ordem de execução

| Fase | Tickets | Por quê |
|---|---|---|
| 1. Ver o defeito fora do app | **001** reproduzir o corte no harness · **002** auditar moldura contra conteúdo | Sem repro nem inventário, qualquer conserto é chute — e o mapa inteiro assume uma hipótese que ninguém mediu. A 002 anda em paralelo porque não depende da 001: ela lê o código, não o comportamento. |
| 2. Escolher o conserto | **003** qual mecanismo conserta | Decide com repro e inventário na mão. Vem antes do código porque as rotas (fonte única de verdade da altura, transação única, moldura medida pelo conteúdo) têm custos muito diferentes. |
| 3. Consertar e travar | **004** aplicar e blindar com gate | O gate é o que impede a regressão de voltar em três meses. |

## Decisões até aqui

- [Auditar a moldura contra o conteúdo](tickets/002-auditar-moldura-contra-conteudo.md) — a altura do knob (`currentSize`) lê **20 identificadores dinâmicos**, e o `interactiveNotch` amarra **7** deles a uma `.animation(_:value:)`. Sobram **13 sem animação amarrada**, e **8 deles mudam com o `mode` parado** — ou seja, a moldura pode saltar de tamanho fora de qualquer transação animada. O maior salto isolado é o card do link: **342 pt** de uma vez. A divergência de *valor* entre moldura e conteúdo está fechada (os dois chamam a mesma função); o que resta é divergência de *transação*. O documento não prova que isso produza o corte — quem prova é a 001. Detalhe e comandos de recontagem em [medicao-002-moldura.md](medicao-002-moldura.md).

## Ainda não especificado

**Plano B se o harness não reproduzir.** A decisão de não rodar build instrumentada e o
destino "causa raiz achada" podem colidir aqui. Se a 001 voltar de mãos vazias, a rota
volta a ser uma conversa — captura sob demanda, teste de estresse mais agressivo, ou
aceitar um conserto defensivo sem repro.

**Forma do gate de regressão.** Só dá para escrever depois de conhecer a causa. Snapshot
comparado, asserção sobre a matemática da altura ou harness de transição são candidatos
com custos diferentes.

## Fora de escopo

**Posição da janela, multi-monitor, tela cheia e sleep.** O destino é o desenho; a
recuperação por expandir/recolher mostra que a janela não é a culpada. Se o usuário
relatar um defeito de posição de verdade, é mapa novo.
