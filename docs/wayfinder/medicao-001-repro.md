# Medição 001 — Reprodução do corte

Método: o harness `tools/cortecheck/main.swift` hospeda a `NotchView` de verdade numa
`NSHostingView` dentro de uma `NSWindow` posicionada fora de qualquer tela, dirige
**transições** (não poses) mexendo no estado pelos mesmos pontos de entrada que o app usa,
e fotografa a view a cada giro de runloop enquanto a animação corre. Cada foto é
classificada pixel a pixel em três classes sobre fundo magenta puro — magenta (fundo),
quase-preto (moldura) e o resto (conteúdo) — e vira uma linha de medida: primeira linha
com moldura, última linha com moldura, última linha com conteúdo. O quadro conta como
**corte** quando o conteúdo passa da moldura em mais de 2 pt, quando a moldura começa mais
de 2 pt abaixo do topo, ou quando existe conteúdo desenhado sem moldura nenhuma. O
`tools/snapshot.sh` não serviu e não foi estendido: ele usa `ImageRenderer`, que renderiza
o estado parado e não avança animação — o defeito procurado é transitório.

Duas travas antes de qualquer contagem, porque as duas falhas silenciosas deste desenho
são "a animação não corre" e "o detector é cego":

- **Controle positivo** (a animação corre): a troca de `mode` — o único gatilho com
  `.animation(morphAnimation, value: mode)` amarrada — tem que produzir alturas
  intermediárias. Produz: `[530, 523, 46, 32, 0, 217, 214, 210, 210, 210, 210]` pt,
  **8 alturas distintas**. Sem isso o harness aborta com código 1.
- **Controle do detector** (o detector enxerga): uma moldura sintética de 100 pt com
  conteúdo descendo até 200 pt tem que acusar corte. Acusa, com **excedente de 100,0 pt**
  exatos. Sem isso o harness aborta com código 1.

## O número

**34 combinações rodadas, em 11 famílias. 0 produziram moldura menor que o conteúdo.**

Famílias varridas: `lista3-focus`, `lista3-link`, `lista3-espelho`, `lista3-calendario`,
`lista3-shelf`, `lista3-notificacao`, `lista3-incoming` (os identificadores da Lista 3 da
[medição 002](medicao-002-moldura.md), nos dois sentidos), `faixa-withanimation` (a troca
de seção pelo caminho de verdade), `mesma-runloop` (duas mudanças no mesmo giro),
`chegada-assincrona` (notificação, HUD, Pomodoro, mensagem, link e screenshot chegando no
meio da animação de expansão) e `hover-vs-gesto` (o `setExpandedDirect` cancelando o
`pendingWork` do hover).

Todas as 34 moveram a moldura de verdade — nenhuma combinação ficou inerte (a coluna
`alturas` do harness é ≥ 2 em todas). O maior salto dirigido foi o card do link em foco
contra a atividade: **504 → 126 pt**, os 378 pt que a medição 002 previu somando o link
(342) à diferença de seção.

Nenhum quadro teve lacuna no topo (`lacuna_topo_max = 0,0 pt` nas 34), que é a forma que o
sintoma relatado — "aparece apenas a metade de baixo" — teria na imagem.

## O que a varredura mediu de passagem, e vale registrar

**A moldura salta sem interpolar quando o `focar` é chamado pelado.** Nas 13 combinações
da família `lista3-*` a moldura tem exatamente **2 alturas** na série inteira: a de antes e
a de depois, sem nenhum valor no meio. Exemplo, `foco-link-para-atividade`:

```
[504, 126, 126, 126, 126, 126, 126, 126, 126, 126, 126, 126, 126, 126, 126, 126]
```

378 pt entre duas fotos consecutivas (~60 ms de intervalo), zero interpolação. É a
confirmação empírica do que a medição 002 leu no código: esses identificadores não têm
`.animation(_:value:)` amarrada na cadeia do `interactiveNotch`.

**Mas o caminho de verdade não chama `focar` pelado.** Clicar na faixa de seções é
`withAnimation(.easeOut(duration: 0.22)) { vm.focar(s) }` (`Knobler/NotchView.swift:986`) e
o swipe horizontal é o mesmo embrulho em volta de `focarVizinho`
(`Knobler/KnoblerApp.swift:1006`) — as duas únicas ocorrências de `withAnimation` no
projeto inteiro. Com a transação ambiente do app, a mesma transição interpola:

```
faixa-link-para-atividade: [504, 486, 153, 126, 126, ...]   (4 alturas)
foco-link-para-atividade:  [504, 126, 126, 126, 126, ...]   (2 alturas)
```

Ou seja: a moldura **não** anda solta no caminho que o usuário usa — ela pega carona na
transação de 0,22 s. E o conteúdo, que tem curva própria de 0,3 s para o mesmo `vm.focus`
(`Knobler/NotchView.swift:970`), ainda assim nunca ficou maior que a moldura em nenhuma das
fotos. O pior excedente medido em toda a varredura — nas 34 combinações, não só nessa
família — foi **0,0 pt**: o conteúdo chega a encostar na borda de baixo da moldura, nunca a
ultrapassa.

**Dez quadros saíram sem moldura nenhuma — e sem conteúdo nenhum.** Em 34 combinações, 10
fotos vieram magenta puro: nem pixel de moldura, nem pixel de conteúdo (o harness separa os
dois casos e imprime a conta). Todas caem em cima de uma troca de `mode` — o controle
positivo, o `hover-abre-e-gesto-fecha` e as cinco `*-durante-abertura`. O contraste que
importa: o **controle do fechado parado**, que não dirige transição nenhuma, mede 32 pt em
**todas** as fotos (51 de 51 na corrida citada; o número de fotos por corrida varia com a
máquina) — a pilulinha fechada nunca some quando nada muda. Não dá para decidir
pela imagem se esses 10 quadros são o `cacheDisplay` devolvendo buffer não desenhado ou um
quadro real em que a árvore não desenhou nada; os PNGs ficam em `/tmp/cortecheck-quadros`.
Não é o sintoma relatado (some tudo, não a metade de cima), mas é a única pista de "pisca"
que a varredura produziu, e é reprodutível.

## Limites desta varredura — o que um "0 de 34" não cobre

- **Cadência.** As fotos saem a **16,8 Hz** em média (o `cacheDisplay` de 1800×1280 px
  custa mais que o giro de runloop). Um corte que dure **um** quadro a 60 Hz (16,7 ms) cabe
  entre duas fotos. O sintoma relatado pelo usuário é um piscar; esta varredura não
  consegue negar um piscar de um quadro só.
- **Reduced Motion não foi varrido.** A `NotchView` lê
  `@Environment(\.accessibilityReduceMotion)`, e esse key path é somente-leitura no SDK do
  macOS 26 — o modificador `.environment(\.accessibilityReduceMotion, …)` não compila.
  Forçar o valor exigiria mexer na preferência de acessibilidade da máquina de quem roda.
  O harness imprime qual valor estava em vigor (aqui: **desligado**).
- **Três seções ficaram de fora**: `.mensagens`, `.historico` e `.nota`. Dar conteúdo a
  elas passa por `MessageStore.append` e `QuickNote`, que gravam no Application Support
  **real** do usuário. (O histórico de notificações foi resolvido: o harness zera
  `NotificationHistory.shared.arquivo` antes de tudo, então `vm.enqueue` — o ponto de
  entrada de verdade — roda sem tocar no disco.) As alturas dessas seções (272, 272 e 148
  pt) estão cobertas por proxy: `.link` aberto, com 438 pt, é a maior seção do app e está na
  varredura.
- **`agentRequestExpanded` (156 pt, item da Lista 3) não foi varrido**: é `@State` privado
  da `NotchView`, alcançável só por clique de verdade no card.
- **Só notch real.** Todas as 34 rodaram com `hasRealNotch = true`. `vm.hasRealNotch` e
  `vm.notchSize` são itens da Lista 3, mas mudam por evento de display, não de interação —
  e o mapa já descartou hipótese ligada a eles (o defeito acontece nas duas telas).

## Determinismo

A varredura inteira foi rodada **3 vezes**; a coluna de veredicto (`corte=N` das 34 linhas)
saiu **idêntica nas 3** — mesmo hash MD5. O que varia entre corridas é o número de fotos por
combinação (a cadência depende da máquina), não o veredicto.

O harness **não** foi acrescentado a `tools/check.sh`. Não é por indeterminismo — esse foi
medido e é 3/3. É por dois motivos de ambiente: (1) ele precisa de sessão gráfica, e o
controle positivo aborta com código 1 num runner sem WindowServer, o que deixaria a CI
vermelha em vez de pulada; (2) leva ~4,5 min contra os segundos que cada gate atual leva. A
forma do gate de regressão é, pelo mapa, decisão da 004 — não desta medição.

## Verificação

```bash
# a varredura inteira: compila a NotchView isolada e roda as 34 transições (~4,5 min)
./tools/cortecheck.sh

# as linhas que fecham a conta (controles + totais)
./tools/cortecheck.sh | grep -E 'controle|combinações|famílias|cadência|quadros sem moldura|com moldura menor'
# → controle do detector: corte=sim excedente=100.0 pt
#   controle do fechado parado: alturas [32, 32, ... ]   (51 fotos, todas 32)
#   controle positivo: 11 quadros, 8 alturas de moldura distintas (0–530 pt)
#   combinações rodadas: 34
#   famílias: chegada-assincrona, faixa-withanimation, hover-vs-gesto, lista3-calendario,
#             lista3-espelho, lista3-focus, lista3-incoming, lista3-link,
#             lista3-notificacao, lista3-shelf, mesma-runloop
#   cadência média das fotos: ~17 Hz
#   quadros sem moldura NENHUMA: 10 (com conteúdo desenhado: 0)
#   com moldura menor que o conteúdo: 0

# a série de alturas por quadro — a prova do salto sem interpolação
CORTECHECK_VERBOSE=1 ./tools/cortecheck.sh \
  | grep -A1 -E 'foco-link-para-atividade |faixa-link-para-atividade '
# → foco-link-para-atividade  alturas: [504, 126, 126, ...]        (2 alturas)
#   faixa-link-para-atividade alturas: [504, 486, 153, 126, ...]   (4 alturas)

# determinismo: três varreduras, veredicto idêntico
for i in 1 2 3; do ./tools/cortecheck.sh > /tmp/cc$i.txt 2>&1; done
for i in 1 2 3; do grep -o 'corte=[ ]*[0-9]*' /tmp/cc$i.txt | tr -d ' ' | md5 -q; done
# → três hashes iguais

# os quadros suspeitos, um PNG por foto
ls /tmp/cortecheck-quadros

# as duas únicas transações explícitas do projeto (o caminho de verdade da troca de foco)
grep -rn 'withAnimation' Knobler/*.swift
# → Knobler/NotchView.swift:986 e Knobler/KnoblerApp.swift:1006

# o `withAnimation` do conteúdo, com duração diferente (0.3 contra 0.22)
grep -n '\.animation(.*value: vm\.focus)' Knobler/NotchView.swift
# → Knobler/NotchView.swift:970
```
