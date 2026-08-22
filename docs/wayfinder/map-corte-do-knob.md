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
| 3. Medir contra o código que ele roda | **004** os eventos no código que ele roda | A 003.1 mediu contra um `KnoblerApp` sem o código que o usuário de fato executa. Mesma pergunta, código certo — e é a última carta antes de aceitar que o mapa não vai achar a causa varrendo. |
| 4. Consertar e travar | **005** aplicar e blindar com gate | O gate é o que impede a regressão de voltar em três meses. A métrica dele é a lacuna de topo — "moldura menor que o conteúdo" está provada cega. |

## Decisões até aqui

- [Auditar a moldura contra o conteúdo](tickets/002-auditar-moldura-contra-conteudo.md) — a altura do knob (`currentSize`) lê **20 identificadores dinâmicos**, e o `interactiveNotch` amarra **7** deles a uma `.animation(_:value:)`. Sobram **13 sem animação amarrada**, e **8 deles mudam com o `mode` parado** — ou seja, a moldura pode saltar de tamanho fora de qualquer transação animada. O maior salto isolado é o card do link: **342 pt** de uma vez. A divergência de *valor* entre moldura e conteúdo está fechada (os dois chamam a mesma função); o que resta é divergência de *transação*. O documento não prova que isso produza o corte — quem prova é a 001. Detalhe e comandos de recontagem em [medicao-002-moldura.md](medicao-002-moldura.md).

- [Reproduzir o corte no harness](tickets/001-reproduzir-o-corte.md) — **o corte não reproduziu**: 35 combinações em 11 famílias de transição, lacuna de topo **0,0 pt** em todas, veredicto idêntico em 9 corridas. O negativo vale porque o instrumento foi atacado: com a moldura empurrada 60 pt pra baixo dentro da `NotchView` de verdade, o harness acusa 60,0 pt e aborta com erro. Duas coisas que o zero **não** cobre, e ambas importam pro 003: as fotos saem a ~17 Hz, então um piscar de um quadro a 60 Hz cabe entre duas fotos; e a métrica "moldura menor que o conteúdo" é cega a uma divergência de `currentSize`, porque forma e conteúdo dividem o mesmo `ZStack` sob o mesmo `.mask` — encolher a altura encolhe os dois juntos. Achado lateral: em toda corrida algumas fotos saem **sem moldura e sem conteúdo**, sempre em cima de uma troca de `mode`, enquanto o controle parado nunca some. É a única pista de "pisca" que a varredura produziu. O harness (`tools/cortecheck/`) ficou fora do `tools/check.sh` de propósito: precisa de sessão gráfica e leva ~4,5 min. Detalhe e comandos em [medicao-001-repro.md](medicao-001-repro.md).

- [Qual mecanismo conserta](tickets/003-qual-mecanismo-conserta.md) — **a hipótese do mapa caiu.** Encolher a altura não pinta o corte: forma e conteúdo dividem o mesmo `ZStack` sob o mesmo `.mask`, então a injeção de uma moldura 60 pt menor acusou **0 de 34**. A classe inteira "moldura menor que o conteúdo" está morta como mecanismo, e como métrica de gate. Sobrevive o inventário da 002; morre a conclusão que se tirava dele. Quatro rotas foram à mesa com o custo de cada uma e o usuário escolheu **medir mais uma vez**, agora contra eventos de ambiente — nasce daí a 003.1. Ele também trouxe janela, tela cheia e sono de volta ao escopo **como suspeitos da causa**, não como área a consertar.

- [Eventos de ambiente no harness](tickets/003.1-eventos-de-ambiente.md) — **o ambiente
  também não pinta o corte.** 8 transições novas dirigem a janela pelos pontos de entrada do
  app (`orderOut`, `orderFrontRegardless`, `setFrame(_:display: true)`): **17 chamadas
  dirigidas, 15 com mudança observável, lacuna de topo 0,0 pt nas oito, 5 das quais sem
  sensibilidade demonstrada** (uma injeção de revisão de 150 ms passou inteira pela
  transição durante morph, a 10,7 Hz) — a varredura
  inteira fecha em **43 combinações, 0 corte**, com dois controles novos provando que a
  janela escondida não cega a foto e que o desvio de 60 pt continua sendo acusado
  atravessando o evento. Sono e troca de modo de display ficaram de fora porque mexeriam na
  máquina do usuário; a **troca de Space não existe neste código** (sem observador de
  `activeSpace`, `NotchWindow` é `.canJoinAllSpaces`). Fechou a segunda pergunta pela metade que a
  evidência aguenta: os quadros magenta **não são buffer virgem** — o `cacheDisplay` rodou e
  desenhou o irmão magenta na mesma foto, e nenhum dos 38/35/26 vazios examinados voltou
  numa segunda foto do mesmo giro. "Quadro real" é a leitura provável, **com ressalva**: as
  duas provas fortes saem do mesmo `cacheDisplay`, e a terceira pode ser cega ao caso. **A pergunta volta ao mapa:** nem estado da interface
  nem ambiente reproduzem o corte, e o que sobra está em "Ainda não especificado". Detalhe e
  comandos em [medicao-003-1-ambiente.md](medicao-003-1-ambiente.md).

- [Eventos de ambiente no harness](tickets/003.1-eventos-de-ambiente.md) — **também não reproduziu.** 8 transições de ambiente, 17 chamadas de janela dirigidas, lacuna de topo **0,0 pt** em todas; 43 combinações no total, zero cortes. O instrumento acusa: um defeito que só existe com a janela fora de ordem foi acusado em 40,0 pt em três das quatro transições de `orderOut`. Mas **5 das 8 não têm sensibilidade demonstrada** — numa delas um defeito de 150 ms passou inteiro, porque fotografar um card de 530 pt custa ~200 ms e a cadência cai para 2–11 Hz. Sobre os quadros vazios: **não são buffer virgem** (o desenho rodou e pintou o fundo na mesma foto), mas provar que o app não desenhou nada exigiria uma câmera que não compartilhe o mesmo caminho. Detalhe em [medicao-003-1-ambiente.md](medicao-003-1-ambiente.md).

- [Os eventos no código que ele roda](tickets/004-o-codigo-que-ele-roda.md) — **o código
  real também não pinta o corte, e agora as oito transições provam que enxergariam.** 8
  transições novas dirigem a réplica de `applyVisibility` (`KnoblerApp.swift:1073`) e de
  `fullscreenDisplays()` (`:1040`) pelos três chamadores nas cadências deles: **68 chamadas
  de `applyVisibility` dirigidas** (58 vindas de mudança em `AppSettings`, uma delas uma
  rajada de 30 no mesmo giro), **106 varreduras de `CGWindowListCopyWindowInfo` na main
  thread**, 87 eventos de janela registrados — **lacuna de topo 0,0 pt nas oito**, e a
  varredura inteira fecha em **51 combinações, 0 corte**. A sensibilidade que faltava está
  fechada: a injeção de 40 pt, gateada no ponto de acionamento do código real em vez de em
  `!janela.isVisible`, foi acusada por **8 de 8**, nas formas persistente e transiente de
  150 ms, 2 de 2 corridas cada — contra 5 das 8 cegas na 003.1. A janela do harness virou a
  `NotchWindow` de verdade, fechando o limite que a 003.1 deixou escrito. Dois achados sem
  causa provada: `applyVisibility` ordena a janela pra frente **mesmo já visível** a cada
  mudança de Ajuste (66 dos 67 `orderFrontRegardless` sem estado que flipasse), e
  `fullscreenDisplays()` custa **máximo 16–21 ms** na main thread — mais que um quadro a
  60 Hz — com `ocultarEmTelaCheia` **ligada por padrão** na máquina do usuário. **A pergunta
  volta ao mapa sem a saída "foi medido contra o código errado":** estado da interface (35),
  ambiente simulado (8) e código real (8) foram varridos, e nenhum reproduz. Detalhe e
  comandos em [medicao-004-codigo-real.md](medicao-004-codigo-real.md).

- [Os eventos no código que ele roda](tickets/004-o-codigo-que-ele-roda.md) — **o negativo mais forte do mapa, e também é zero.** 68 chamadas de `applyVisibility` dirigidas (58 vindas de mudança nos Ajustes, uma delas em rajada de 30 no mesmo giro), 106 varreduras da lista de janelas do sistema, 87 eventos de janela: **lacuna de topo 0,0 pt**, 51 combinações, zero cortes. O que separa esta das anteriores é a sensibilidade: **8 de 8** transições acusam um defeito plantado, nas formas persistente e transiente de 150 ms, verificado independentemente pela revisão — contra 5 das 8 cegas na 003.1. O instrumento passou a usar a `NotchWindow` de verdade. Dois achados laterais, medidos e explicitamente **não** apontados como causa: o app chama `orderFrontRegardless` com a janela já visível em 66 de 67 vezes, e `fullscreenDisplays()` custa até ~21 ms na thread principal — mais que um quadro a 60 Hz — com a opção ligada por padrão. Detalhe em [medicao-004-codigo-real.md](medicao-004-codigo-real.md).

- **Achado de processo, sem ticket:** o mapa foi cartografado lendo o repositório principal com mudanças **não commitadas** no disco. O worktree onde tudo foi medido nasceu do último commit e não tinha `applyVisibility` nem o tratamento de Space — 1582 linhas contra 1668. O usuário confirmou que roda a build local com esse código, então ele é suspeito real e a 003.1 não pôde exercitá-lo. O código entrou no worktree em `f8684aa`, **só para ser medido**, e a [004](tickets/004-o-codigo-que-ele-roda.md) refaz a pergunta contra ele. A 001 e a 002 seguem íntegras: o trabalho pendente não toca `NotchView` nem `NotchViewModel`.

## Ainda não especificado

**O mapa varreu tudo o que dava para varrer, e não achou.** Estado da interface (35
combinações), ambiente simulado (43) e o código real que o usuário executa (51): zero
cortes nas três, a última com sensibilidade provada em todas as transições. O destino
"causa raiz achada" não foi alcançado por varredura, e não há mais varredura a fazer com
este instrumento.

**O limite que sobrou é a câmera.** Fotografar um card de 530 pt custa ~200 ms, então a
cadência cai para 2–11 Hz. Um corte que dure um quadro a 60 Hz cabe folgado entre duas
fotos. Elevar isso não é ajuste: é outro mecanismo de captura, e ninguém especificou qual.

**As rotas que continuam sobre a mesa**, as duas já apresentadas e não escolhidas:
autodiagnóstico embarcado na build normal, que revisita a decisão de não rodar build
instrumentada; e conserto defensivo sem causa provada, com o gate na lacuna de topo.

**Os dois achados laterais da 004 podem virar trabalho próprio** — não como causa do corte,
que eles não são, mas como custo: um ordenamento de janela redundante a cada mudança de
Ajuste, e uma varredura síncrona de até 21 ms na thread principal. Se virarem ticket, é
outro mapa: o destino deste é o corte.

## Fora de escopo

**Posicionamento em multi-monitor e comportamento em tela cheia.** Continuam fora: são
área a consertar, e o destino é o corte.

Os **eventos** de janela, tela cheia e sono **voltaram ao escopo** em 2026-08-21, por
decisão do usuário na [003](tickets/003-qual-mecanismo-conserta.md), e só como suspeitos
da causa. O argumento original para excluí-los — "expandir/recolher conserta, logo a
janela está certa" — não separa estado da interface de buffer de desenho corrompido:
expandir/recolher força um redesenho completo dos dois. Se a causa estiver num desses
eventos, o conserto vem junto.
