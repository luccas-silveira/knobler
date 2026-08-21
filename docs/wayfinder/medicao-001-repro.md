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
- **Controle do desvio na view real** (o detector enxerga *na `NotchView`*): o controle
  acima é uma view sintética — prova que `medir` sabe somar, não que enxerga defeito na
  árvore de verdade. Este roda a `NotchView` real empurrada 60 pt pra baixo (um
  `.padding(.top, 60)` no envelope do harness; nada em `Knobler/*.swift` é tocado) e exige
  lacuna de topo de **60,0 pt** em **todos** os quadros. Sai 60,0 pt nas 5 corridas da bateria do round 1 e nas 4 do round 2.
  Sem isso o harness aborta com código 1.

## O número

**35 combinações rodadas, em 11 famílias. 0 produziram lacuna no topo da moldura:
`lacuna_topo_max = 0,0 pt` nas 35.** Lacuna no topo é a forma que o sintoma relatado —
"aparece apenas a metade de baixo" — teria na imagem, e é a métrica que o controle do
desvio prova responder na `NotchView` de verdade.

Métrica secundária, com ressalva: **0 combinações produziram moldura menor que o
conteúdo**, com o pior excedente da varredura em 0,0 pt (o conteúdo encosta na borda de
baixo da moldura, nunca a ultrapassa). A ressalva está em "o que um zero não cobre":
encolher só a moldura na `NotchView` real **não** produz conteúdo para fora dela, então
esse zero mede menos do que o nome sugere.

Famílias varridas: `lista3-focus`, `lista3-link`, `lista3-espelho`, `lista3-calendario`,
`lista3-shelf`, `lista3-notificacao`, `lista3-incoming` (`allowReply` e `mediaHeight`) — os
identificadores da Lista 3 da
[medição 002](medicao-002-moldura.md), nos dois sentidos —, `faixa-withanimation` (a troca
de seção pelo caminho de verdade), `mesma-runloop` (duas mudanças no mesmo giro),
`chegada-assincrona` (notificação, HUD, Pomodoro, mensagem, link e screenshot chegando no
meio da animação de expansão) e `hover-vs-gesto` (o `setExpandedDirect` cancelando o
`pendingWork` do hover).

Todas as 35 moveram a moldura de verdade — nenhuma combinação ficou inerte (a coluna
`alturas` do harness é ≥ 2 em todas). O maior salto dirigido foi o card do link em foco
contra a atividade: **504 → 126 pt**, os 378 pt que a medição 002 previu somando o link
(342) à diferença de seção.

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
fotos. O pior excedente medido em toda a varredura — nas 35 combinações, não só nessa
família — foi **0,0 pt**: o conteúdo chega a encostar na borda de baixo da moldura, nunca a
ultrapassa.

**Alguns quadros saem sem moldura nenhuma — e sem conteúdo nenhum.** Em 35 combinações,
algumas fotos por corrida vieram magenta puro: nem pixel de moldura, nem pixel de conteúdo
(o harness separa os dois casos e imprime a conta). **Sem teto declarado** — foram 6 a 15
nas nove corridas medidas com o instrumento daquela época, e **6 a 38** somando as corridas
feitas depois (a janela de observação de 1,6 s da 003.1 subiu o piso). Este contador **não
tem banda**: ele mede quantas fotos calham de cair exatamente em cima de uma troca de
`mode`, o que muda com a cadência da máquina — duas bandas já foram escritas aqui e furadas
na corrida seguinte. O
que é estável, e é a metade que importa, é a outra: **nenhuma** dessas fotos tinha conteúdo
desenhado, em nenhuma corrida. Todas caem em cima de uma troca de `mode` — o controle
positivo, o `hover-abre-e-gesto-fecha` e as cinco `*-durante-abertura`. O contraste que
importa: o **controle do fechado parado**, que não dirige transição nenhuma, mede 32 pt em
**todas** as fotos (50–51 fotos por corrida, bateria de 5 corridas do round 1) — a pilulinha fechada nunca some quando nada muda. Não dá para decidir
pela imagem se esses quadros são o `cacheDisplay` devolvendo buffer não desenhado ou
quadros reais em que a árvore não desenhou nada; os PNGs ficam em `/tmp/cortecheck-quadros`.
Não é o sintoma relatado (some tudo, não a metade de cima), mas é a única pista de "pisca"
que a varredura produziu, e é reprodutível.

## Limites desta varredura — o que um "0 de 35" não cobre

- **Encolher a moldura sozinha não vaza conteúdo.** `shape.fill(Color.black)` e o conteúdo
  moram no MESMO `ZStack` (`Knobler/NotchView.swift:181`), e a máscara veste esse ZStack
  inteiro (`.mask(shape)`, `:249`). Injetar uma moldura 60 pt menor que o conteúdo na
  `NotchView` real faz os dois encolherem juntos: a varredura acusa 0, e acusaria 0 mesmo
  com o defeito plantado. É por isso que "moldura menor que o conteúdo" ficou como métrica
  secundária e a lacuna de topo virou o número do título — essa, sim, o controle do desvio
  prova que responde na view de verdade.
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
  da `NotchView`, alcançável só por clique de verdade no card. É o único item da Lista 3
  fora da varredura — `vm.incoming?.mediaHeight`, que a 002 marca como "sem teto conhecido",
  entrou na família `lista3-incoming` (200 → 0 pt).
- **Só notch real.** Todas as 35 rodaram com `hasRealNotch = true`. `vm.hasRealNotch` e
  `vm.notchSize` são itens da Lista 3, mas mudam por evento de display, não de interação —
  e o mapa já descartou hipótese ligada a eles (o defeito acontece nas duas telas).

## Determinismo

A varredura inteira foi rodada **5 vezes** (bateria do round 1) e mais **4** depois da
última mudança de trava (round 2); a coluna de veredicto (`corte=N` das 35 linhas)
saiu **idêntica nas 9** — mesmo hash MD5 nas duas baterias. O que varia entre corridas é o número de fotos por
combinação (a cadência depende da máquina), não o veredicto.

A trava do controle positivo exige **3 alturas de moldura distintas**, e o 3 é derivado, não
escolhido: duas alturas (antes e depois) só provariam que o estado mudou; a terceira é a que
prova que houve um valor **no meio** — interpolação, que é a única coisa que o controle
precisa responder. O limiar anterior era 5 e não vinha de lugar nenhum. Contagem por corrida
medida na bateria de 4 corridas do round 2, com quatro trocas de `mode`: **5, 7, 10 e 11**. Ela oscila
porque a amostragem às vezes cai em platôs da mola — mais fotos numa corrida não significa
mais alturas distintas —, e é justamente por isso que a trava não pode depender da cadência:
contra o piso medido (5) a margem é de 2 alturas.
Uma faixa de "9–13" chegou a ser escrita aqui a partir da bateria de 5 corridas do round 1,
que calhou de ser afortunada, e **não** se sustenta: corridas com MAIS fotos mediram MENOS alturas.

O harness **não** foi acrescentado a `tools/check.sh`. Não é por indeterminismo — esse foi
medido e é 9/9 (5 corridas do round 1 mais 4 do round 2). É por dois motivos de ambiente: (1) ele precisa de sessão gráfica, e o
controle positivo aborta com código 1 num runner sem WindowServer, o que deixaria a CI
vermelha em vez de pulada; (2) leva ~4,5 min contra os segundos que cada gate atual leva. A
forma do gate de regressão é, pelo mapa, decisão da 004 — não desta medição.

## Verificação

> A [medição 003.1](medicao-003-1-ambiente.md) mexeu no instrumento depois desta corrida, em
> quatro pontos: a janela de observação subiu de **0,8 s para 1,6 s**; a raiz do envelope
> passou a ser **ancorada no topo** (`.frame(maxWidth:maxHeight:alignment: .top)` no lugar do
> tamanho fixo, para o `setFrame` que muda tamanho não fingir lacuna); toda foto vazia passa
> por um **exame de segunda câmera**, com teto de **8 fotos por camada por corrida**, que
> custa cadência; e a varredura ganhou **8 transições de ambiente**.
>
> As **contagens de quadros** abaixo são do instrumento antigo e saem maiores hoje, "quadros
> sem moldura NENHUMA" hoje sai bem acima da faixa de 6–15 registrada aqui (**sem teto**: 6 a
> 38 nas corridas medidas, é cadência), e "combinações rodadas" agora é
> **43**, não 35. Os veredictos — 0 corte, lacuna 0,0 pt, controles em 100,0 e 60,0 pt — não
> mudaram.
>
> **A receita de determinismo abaixo mudou** e já está corrigida aqui: a 003.1 acrescentou um
> controle que imprime `quadros com corte=N/N`, e esse N é contagem de quadros, que varia por
> máquina. Hashear o arquivo inteiro passou a dar hashes diferentes entre corridas boas; o
> `grep -E '^  [a-z]'` antes do `grep -o` limita a conta às linhas de transição, que é o que
> o veredicto sempre foi.

```bash
# a varredura inteira: compila a NotchView isolada e roda as 35 transições (~4,5 min)
./tools/cortecheck.sh

# as linhas que fecham a conta (controles + totais)
./tools/cortecheck.sh | grep -E 'controle|combinações|famílias|cadência|quadros sem moldura|com moldura menor'
# Os valores EXATOS (refazem a conta): 35 combinações, 11 famílias, 0 corte,
# lacuna_topo_max 0,0 pt, excedente do controle do detector 100,0 pt, lacuna do
# controle do desvio 60,0 pt. Os demais dependem da máquina e vêm entre
# parênteses como faixa medida, não como valor a bater.
# → controle do detector: corte=sim excedente=100.0 pt
#   controle do desvio na view real: lacuna_topo_max=60.0 pt, corte=sim
#   controle do fechado parado: alturas [32, 32, ... ]   (50–51 fotos, TODAS 32)
#   controle positivo: alturas de moldura distintas — a contagem OSCILA por
#     corrida; o que vale é ser ≥ 3 (a trava). Faixa e derivação do 3 na seção
#     Determinismo.
#   combinações rodadas: 35
#   famílias: chegada-assincrona, faixa-withanimation, hover-vs-gesto, lista3-calendario,
#             lista3-espelho, lista3-focus, lista3-incoming, lista3-link,
#             lista3-notificacao, lista3-shelf, mesma-runloop
#   cadência média das fotos: (16–18) Hz
#   quadros sem moldura NENHUMA: sem teto declarado (6–15 nas corridas medidas;
#     depende da cadência) — o exato aqui é "com conteúdo desenhado: 0", SEMPRE
#   com moldura menor que o conteúdo: 0

# a série de alturas por quadro — a prova do salto sem interpolação
CORTECHECK_VERBOSE=1 ./tools/cortecheck.sh \
  | grep -A1 -E 'foco-link-para-atividade |faixa-link-para-atividade '
# O que é exato aqui: os extremos (504 e 126 pt) e a CONTAGEM de alturas — 2 sem
# `withAnimation`, 4 com. Os valores do meio são ilustrativos: dependem de quando
# a foto cai na curva (medidos entre 486–488 e 146–160 na bateria de 5 corridas do round 1).
# → foco-link-para-atividade  alturas: [504, 126, 126, ...]        (2 alturas)
#   faixa-link-para-atividade alturas: [504, 487, 152, 126, ...]   (4 alturas)

# determinismo: cinco varreduras, veredicto idêntico
for i in 1 2 3 4 5; do ./tools/cortecheck.sh > /tmp/cc$i.txt 2>&1; done
for i in 1 2 3 4 5; do grep -E '^  [a-z]' /tmp/cc$i.txt \
  | grep -o 'corte=[ ]*[0-9]*' | tr -d ' ' | md5 -q; done
# → cinco hashes iguais

# a margem da trava do controle positivo (trava em 3, derivada — ver Determinismo)
grep -h 'controle positivo' /tmp/cc*.txt
# → a contagem por corrida oscila (5, 7, 10, 11 na bateria de 4 corridas); o exato é o
#   PISO observado, 5, contra a trava de 3

# os quadros suspeitos, um PNG por foto
ls /tmp/cortecheck-quadros

# as duas únicas transações explícitas do projeto (o caminho de verdade da troca de foco)
grep -rn 'withAnimation' Knobler/*.swift
# → Knobler/NotchView.swift:986 e Knobler/KnoblerApp.swift:1006

# o `withAnimation` do conteúdo, com duração diferente (0.3 contra 0.22)
grep -n '\.animation(.*value: vm\.focus)' Knobler/NotchView.swift
# → Knobler/NotchView.swift:970
```
