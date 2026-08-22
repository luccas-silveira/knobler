# Mapa: O knob cortado ao meio

Aberto em 2026-08-21

**Fechado em 2026-08-22** — os sete tickets fecharam. A causa não foi encontrada: **51
combinações distintas**, varridas três vezes conforme o instrumento crescia (35 → 43 → 51,
totais cumulativos e não somáveis), zero cortes, a última com sensibilidade provada em
todas as transições. O mapa entrega o que a [005](tickets/005-o-que-fazer-sem-a-causa.md)
redefiniu no lugar dela — detecção, prova, autocura e gate —, e a prova gravada é o que
mantém a causa alcançável na próxima vez que o defeito aparecer na máquina do usuário.

## Destino

O app **detecta** o knob cortado ao meio quando isso acontece, **deixa prova** do estado em
que aconteceu, **se cura** refazendo o layout, e um gate hermético em `tools/check.sh`
falha se essa proteção quebrar.

Este destino foi reescrito em 2026-08-22, na [005](tickets/005-o-que-fazer-sem-a-causa.md).
Ele dizia "causa identificada, corrigida e coberta por gate", e a causa não foi
identificada: três varreduras com o instrumento provado mediram zero. A prova gravada é o
que mantém a causa alcançável depois.

O mapa cobre o **desenho** do notch. Posicionamento em multi-monitor e comportamento em
tela cheia continuam fora — os eventos de janela entraram no escopo como suspeitos da
causa, não como área a consertar.

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
| 4. Decidir sem a causa | **005** o que fazer sem a causa | As três varreduras deram zero e a premissa do mapa caiu. Decisão do usuário, não do agente: as rotas têm perfis de risco muito diferentes e é ele quem paga. |
| 5. Detectar, curar e travar | **006** detectar, gravar, curar e travar | A prova gravada é o que mantém a causa alcançável depois de o app parar de exibir o defeito. O gate mira a lacuna de topo — "moldura menor que o conteúdo" está provada cega. |

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
  atravessando o evento — um defeito que só existe com a janela fora de ordem foi acusado
  em 40,0 pt em **três das quatro** transições de `orderOut`. Sono e troca de modo de display ficaram de fora porque mexeriam na
  máquina do usuário; a **troca de Space não existe neste código** (sem observador de
  `activeSpace`, `NotchWindow` é `.canJoinAllSpaces`). Fechou a segunda pergunta pela metade que a
  evidência aguenta: os quadros magenta **não são buffer virgem** — o `cacheDisplay` rodou e
  desenhou o irmão magenta na mesma foto, e nenhum dos 38/35/26 vazios examinados voltou
  numa segunda foto do mesmo giro. "Quadro real" é a leitura provável, **com ressalva**: as
  duas provas fortes saem do mesmo `cacheDisplay`, e a terceira pode ser cega ao caso. **A pergunta volta ao mapa:** nem estado da interface
  nem ambiente reproduzem o corte, e o que sobra está em "Ainda não especificado". Detalhe e
  comandos em [medicao-003-1-ambiente.md](medicao-003-1-ambiente.md).

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
  150 ms, 2 de 2 corridas cada, **verificado independentemente pela revisão** — contra 5
  das 8 cegas na 003.1. A janela do harness virou a
  `NotchWindow` de verdade, fechando o limite que a 003.1 deixou escrito. Dois achados sem
  causa provada: `applyVisibility` ordena a janela pra frente **mesmo já visível** a cada
  mudança de Ajuste (66 dos 67 `orderFrontRegardless` sem estado que flipasse), e
  `fullscreenDisplays()` custa **máximo 16–21 ms** na main thread — mais que um quadro a
  60 Hz — com `ocultarEmTelaCheia` **ligada por padrão** na máquina do usuário. **A pergunta
  volta ao mapa sem a saída "foi medido contra o código errado":** estado da interface (35),
  ambiente simulado (8) e código real (8) foram varridos, e nenhum reproduz. Detalhe e
  comandos em [medicao-004-codigo-real.md](medicao-004-codigo-real.md).

- [O que fazer sem a causa](tickets/005-o-que-fazer-sem-a-causa.md) — **a premissa de que uma varredura acharia a causa caiu**, e com ela o destino original. 51 combinações distintas, varridas três vezes conforme o instrumento crescia (35 → 43 → 51, cumulativos), zero cortes, a última com sensibilidade provada em 8 de 8 transições. Quatro rotas foram à mesa com o custo de cada uma; o usuário escolheu **detectar, gravar e se curar** — o conserto corre só quando a medição diz que o defeito está presente, e deixa prova de que estava. O que sobrevive: a lacuna de topo como métrica, o harness como instrumento, e os dois achados laterais da 004 seguem não sendo causa.

- [Detectar, gravar, curar e travar](tickets/006-aplicar-e-travar-o-gate.md) — **entregue,
  e o custo cabe.** O invariante da lacuna de topo passou a ser medido em execução na
  geometria de layout da `NotchView`: **centenas de nanossegundos por medida, sob 1 µs**,
  contra os ~21 ms que a 004 achou na main thread. A varredura inteira (**51 combinações**) rodou com a sonda viva e
  gravou **zero** provas — falso positivo nenhum —, com o mesmo MD5 de veredicto da 004
  (`c0c4bef1223da3d33361af1a4a4640aa`) em 6 corridas, 3 antes e 3 depois; a maior diferença
  de cadência é **+1,0 Hz** de mediana, dentro dos 4,5 Hz de dispersão entre corridas do
  mesmo estado. A violação grava treze campos em JSONL no Application Support e refaz a
  subárvore da moldura (`.id`), com espera de 2 s entre curas. O gate
  (`tools/cortedetectorcheck.swift`) tem duas metades — o harness e o grep da fiação na
  `NotchView` — e **falha contra o código de antes** nos dois estados testados. Ele trava
  **comportamento**, não formato: a revisão montou quatro mutantes que preservam a API e
  mudam a lógica, e o gate reprovou os quatro. Teto de **5 curas por sessão** — passado ele
  o vigia continua gravando e para de reconstruir, para que uma premissa que caia num
  refactor futuro não vire laço permanente reiniciando câmera e avatares —, e a gravação
  ganhou a mesma janela de 2 s, contando as suprimidas (treze campos na prova, nenhum com
  conteúdo do usuário). `./tools/check.sh` = **38 ok**, snapshot verde, build sem warning.
  Limite declarado: o detector lê layout; se o defeito nascer abaixo dele, o log fica vazio
  — e um log vazio ao lado de um corte testemunhado também é evidência.

- **Achado de processo, sem ticket:** o mapa foi cartografado lendo o repositório principal com mudanças **não commitadas** no disco. O worktree onde tudo foi medido nasceu do último commit e não tinha `applyVisibility` nem o tratamento de Space — 1582 linhas contra 1668. O usuário confirmou que roda a build local com esse código, então ele é suspeito real e a 003.1 não pôde exercitá-lo. O código entrou no worktree em `f8684aa`, **só para ser medido**, e a [004](tickets/004-o-codigo-que-ele-roda.md) refaz a pergunta contra ele. A 001 e a 002 seguem íntegras: o trabalho pendente não toca `NotchView` nem `NotchViewModel`.

## Ainda não especificado

**O mapa varreu tudo o que dava para varrer, e não achou.** São **51 combinações
distintas**, varridas três vezes conforme o instrumento crescia: estado da interface (35),
mais ambiente simulado (43 no total) e mais o código real que o usuário executa (51 no
total). Os totais são **cumulativos** — a 003.1 e a 004 dizem isso nelas mesmas —, então
não se somam. Zero cortes nas três, a última com sensibilidade provada em todas as
transições. O destino
"causa raiz achada" não foi alcançado por varredura, e não há mais varredura a fazer com
este instrumento.

**Os zeros não são "não achamos" — são evidência positiva de onde o defeito NÃO mora.** A
[003](tickets/003-qual-mecanismo-conserta.md) provou que moldura e conteúdo dividem o mesmo
`ZStack` sob o mesmo `.compositingGroup()` + `.mask(shape)`: o grupo contribui zero pixel ou
contribui os dois. A [003.1](tickets/003.1-eventos-de-ambiente.md) mediu isso por outro
caminho — em **0** dos quadros vazios das três varreduras havia conteúdo desenhado sem
moldura. Uma metade persistente, que é exatamente o sintoma, a árvore mascarada **não sabe
produzir**. O defeito mora fora dela.

**E o limite maior não é de cadência, é de camada.** As três varreduras compartilham uma
câmera só, e ela nunca olha para a tela: `cacheDisplay` e `CALayer.render(in:)` **redesenham
a árvore de modelo**. Nenhuma das 51 combinações leu um pixel que o compositor tenha
composto. Um backing store parcialmente atualizado é invisível a **100%** do conjunto, por
construção, independente de cadência — e a cadência (~200 ms por foto, 2–11 Hz, um corte de
um quadro a 60 Hz cabendo entre duas fotos) é só o limite que já estava escrito.

**Logo: "o defeito continua e o JSONL fica vazio" não é uma hipótese entre outras — é o
desfecho esperado.** A detecção da 006 lê geometria de layout, a mesma camada que as três
varreduras já inocentaram. O log vazio ao lado de um corte testemunhado é o resultado a
esperar, e ele *é* informação: joga a causa para baixo do layout.

**O "outro mecanismo de captura" dá para especificar, e é isto:** fotografar o pixel do
**compositor** — `ScreenCaptureKit`, ou `CGWindowListCreateImage` contra o `windowNumber` da
`NotchWindow` — e comparar, no mesmo giro, com a foto de modelo do `cacheDisplay`. É a mesma
forma do controle da segunda câmera que a 003.1 já montou, com o caminho trocado pelo único
que enxerga a camada suspeita. Mesmo custo de ~200 ms por foto, mesmo teto de 8 fotos por camada por corrida,
e **não** exige build instrumentada no dia a dia — a decisão travada do mapa continua de pé.

**Um negativo já conferido, para poupar a próxima sessão:** a hipótese "a janela recorta o
topo" não se sustenta. O `placeWindows` (`Knobler/KnoblerApp.swift:1249-1256` — como toda
referência a `KnoblerApp.swift` neste mapa e nas medições 003.1 e 004, a linha só vale entre
o commit `f8684aa` e o merge; no `master` ela volta a ser outra até o usuário commitar o
trabalho local dele) prega o topo
da janela no topo da tela, e qualquer variação de `visibleFrame` encolhe o **rodapé**, nunca
a cabeça.

**Se a prova aparecer e apontar a causa**, o conserto dela é mapa novo — este fecha na
detecção.

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
