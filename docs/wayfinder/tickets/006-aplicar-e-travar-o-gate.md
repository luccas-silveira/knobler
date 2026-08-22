# 006 — Detectar, gravar, curar e travar

Map: [O knob cortado ao meio](../map-corte-do-knob.md)
Type: `fix`
Status: aberto
Assignee: —
Blocked by: 005

## Pergunta

O app detecta o corte quando ele acontece, deixa prova, se cura, e existe um gate que falha
se essa proteção quebrar?

Quatro entregas, e a ordem importa porque cada uma depende da anterior:

**1. O invariante.** A métrica é a **lacuna de topo**: a distância entre o topo da moldura
desenhada e o topo onde ela deveria estar. Zero é o normal — as três varreduras mediram
0,0 pt em 129 combinações. "Moldura menor que o conteúdo" **não serve** e está provada
cega: forma e conteúdo dividem o mesmo `ZStack` sob o mesmo `.mask(shape)`
(`NotchView.swift:181` e `:249`), então encolher a altura encolhe os dois juntos. Isso está
medido na [003](003-qual-mecanismo-conserta.md) e não se re-discute.

**2. A detecção dentro do app.** O invariante precisa ser verificado em execução, não só no
harness. Onde e com que frequência é a parte cara desta tarefa: barato demais e não pega o
defeito, caro demais e o app paga no ciclo de desenho. A [004](004-o-codigo-que-ele-roda.md)
mediu que uma varredura síncrona de ~21 ms na thread principal já existe hoje e é mais que
um quadro — use como teto do que **não** fazer.

**3. A prova.** Quando o invariante quebra, grave o suficiente para achar a causa depois:
a geometria, o `mode`, a seção em foco, o que estava animando, e o que tinha acabado de
acontecer. Sem isso o mapa se cura e nunca aprende. Esta é a metade que o usuário escolheu
junto com a cura — não a corte por economia.

**4. A cura, e só quando o defeito está presente.** Refazer o layout é a ação; o gatilho é
a violação medida. Um refazimento que corre sem defeito presente é o remendo cego que o
usuário rejeitou desde a abertura da sessão.

**5. O gate.** Um check hermético que falha se a proteção quebrar. Duas registrações
manuais que sessões anteriores já esqueceram neste repositório e que fazem o trabalho sumir
da CI sem dar erro: linha nova em `tools/check.sh`, e arquivo `.swift` novo que a
`NotchView` use entra à mão em `tools/notchview-fontes.txt`. Harness escrito como
`main.swift` não aceita `-parse-as-library`.

O gate precisa **falhar contra o código de antes**. Um check que passa nos dois estados não
está checando nada — rode-o contra o `git stash` do conserto antes de fechar este ticket.

O instrumento já existe: `tools/cortecheck/`, com controles que provam que ele enxerga um
defeito plantado (60 pt de deslocamento acusam 60,0 pt) e a receita de injeção escrita na
`## Verificação` da [medição 004](../medicao-004-codigo-real.md). Reaproveite.

Fechar só depois de `./tools/check.sh` inteiro verde, com a saída citada na `## Resolução`.

**Atenção ao integrar:** este branch carrega o commit `f8684aa`, que trouxe código não
commitado do usuário só para ser medido. Ele **não** pode ir para o branch principal.
