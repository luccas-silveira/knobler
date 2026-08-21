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
| 2. Escolher o conserto e medir o que sobrou | **003** qual mecanismo conserta · **003.1** eventos de ambiente no harness | A 003 decidiu com repro e inventário na mão — e a repro derrubou a hipótese, então a decisão dela foi medir mais uma vez em vez de consertar. A 003.1 nasce dessa decisão e fica na fase do pai: é o mesmo instrumento, dirigido contra o ambiente em vez do estado da interface. |
| 3. Consertar e travar | **004** aplicar e blindar com gate | O gate é o que impede a regressão de voltar em três meses. A métrica dele é a lacuna de topo — "moldura menor que o conteúdo" está provada cega. |

## Decisões até aqui

- [Auditar a moldura contra o conteúdo](tickets/002-auditar-moldura-contra-conteudo.md) — a altura do knob (`currentSize`) lê **20 identificadores dinâmicos**, e o `interactiveNotch` amarra **7** deles a uma `.animation(_:value:)`. Sobram **13 sem animação amarrada**, e **8 deles mudam com o `mode` parado** — ou seja, a moldura pode saltar de tamanho fora de qualquer transação animada. O maior salto isolado é o card do link: **342 pt** de uma vez. A divergência de *valor* entre moldura e conteúdo está fechada (os dois chamam a mesma função); o que resta é divergência de *transação*. O documento não prova que isso produza o corte — quem prova é a 001. Detalhe e comandos de recontagem em [medicao-002-moldura.md](medicao-002-moldura.md).

- [Reproduzir o corte no harness](tickets/001-reproduzir-o-corte.md) — **o corte não reproduziu**: 35 combinações em 11 famílias de transição, lacuna de topo **0,0 pt** em todas, veredicto idêntico em 9 corridas. O negativo vale porque o instrumento foi atacado: com a moldura empurrada 60 pt pra baixo dentro da `NotchView` de verdade, o harness acusa 60,0 pt e aborta com erro. Duas coisas que o zero **não** cobre, e ambas importam pro 003: as fotos saem a ~17 Hz, então um piscar de um quadro a 60 Hz cabe entre duas fotos; e a métrica "moldura menor que o conteúdo" é cega a uma divergência de `currentSize`, porque forma e conteúdo dividem o mesmo `ZStack` sob o mesmo `.mask` — encolher a altura encolhe os dois juntos. Achado lateral: em toda corrida algumas fotos saem **sem moldura e sem conteúdo**, sempre em cima de uma troca de `mode`, enquanto o controle parado nunca some. É a única pista de "pisca" que a varredura produziu. O harness (`tools/cortecheck/`) ficou fora do `tools/check.sh` de propósito: precisa de sessão gráfica e leva ~4,5 min. Detalhe e comandos em [medicao-001-repro.md](medicao-001-repro.md).

- [Qual mecanismo conserta](tickets/003-qual-mecanismo-conserta.md) — **a hipótese do mapa caiu.** Encolher a altura não pinta o corte: forma e conteúdo dividem o mesmo `ZStack` sob o mesmo `.mask`, então a injeção de uma moldura 60 pt menor acusou **0 de 34**. A classe inteira "moldura menor que o conteúdo" está morta como mecanismo, e como métrica de gate. Sobrevive o inventário da 002; morre a conclusão que se tirava dele. Quatro rotas foram à mesa com o custo de cada uma e o usuário escolheu **medir mais uma vez**, agora contra eventos de ambiente — nasce daí a 003.1. Ele também trouxe janela, tela cheia e sono de volta ao escopo **como suspeitos da causa**, não como área a consertar.

## Ainda não especificado

**O que fazer se a 003.1 também voltar de mãos vazias.** Duas rotas já apresentadas e não
escolhidas continuam disponíveis: autodiagnóstico embarcado na build normal (que revisita
a decisão de não rodar build instrumentada) e conserto defensivo sem causa provada. A
terceira possibilidade — o defeito depender de hardware que nenhum harness alcança — não
tem rota escrita ainda.

**Forma do gate de regressão.** Só dá para escrever depois de conhecer a causa. Snapshot
comparado, asserção sobre a matemática da altura ou harness de transição são candidatos
com custos diferentes.

## Fora de escopo

**Posicionamento em multi-monitor e comportamento em tela cheia.** Continuam fora: são
área a consertar, e o destino é o corte.

Os **eventos** de janela, tela cheia e sono **voltaram ao escopo** em 2026-08-21, por
decisão do usuário na [003](tickets/003-qual-mecanismo-conserta.md), e só como suspeitos
da causa. O argumento original para excluí-los — "expandir/recolher conserta, logo a
janela está certa" — não separa estado da interface de buffer de desenho corrompido:
expandir/recolher força um redesenho completo dos dois. Se a causa estiver num desses
eventos, o conserto vem junto.
