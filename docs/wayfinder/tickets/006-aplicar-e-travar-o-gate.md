# 006 — Detectar, gravar, curar e travar

Map: [O knob cortado ao meio](../map-corte-do-knob.md)
Type: `fix`
Status: fechado (2026-08-22)
Assignee: sdd-006
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

## Resolução

**Entregue: o invariante, a detecção, a prova, a cura e o gate — as cinco.** Nada foi
cortado.

**1. O invariante.** `CorteDoKnob.lacunaDeTopo` (`Knobler/CorteDoKnob.swift`) é o `minY` da
moldura desenhada dentro de um espaço de coordenadas plantado na raiz da `NotchView`, onde
ele é **0 por construção** — a raiz é um `VStack` alinhado ao topo e a moldura é o primeiro
filho. Tolerância **2 pt**, herdada do harness (4 px de bitmap a escala 2) contra os 22 pt
do menor salto real da Lista 3 da [002](../medicao-002-moldura.md). A **altura ficou fora do
invariante**: ela anima, então a altura desenhada diverge legitimamente de `currentSize`
durante todo morph e compará-las acusaria toda transição. Ela entra na prova como contexto
(`animando`), nunca como gate.

**2. A detecção, com o custo medido.** A sonda é um `SensorDeCorte` — `Color.clear` de
fundo com `GeometryReader`, logo depois do `.frame(width:height:)` da moldura. Nenhum
syscall, nenhuma captura de bitmap (a câmera do harness custa ~200 ms por card de 530 pt).
Dois números medidos, não estimados:

| O que | Medido | Teto da 006 |
|---|---|---|
| Caminho normal do invariante | **134–157 ns por medida** (100 000 medidas, 2 corridas) | os ~21 ms de `fullscreenDisplays()` da [004](../medicao-004-codigo-real.md) |
| Cadência da varredura `real` com a sonda viva | medianas por transição **10,0–70,2 Hz** contra **9,9–70,6 Hz** sem ela (3 corridas de cada estado) | — |

O maior delta de mediana é **+1,0 Hz** (`real-ajustes-durante-morph`), e a dispersão entre
corridas do **mesmo** estado chega a 4,5 Hz (10,0 → 14,5 Hz) — ou seja, o custo integrado
está **dentro do ruído** da medição. O veredicto não mexeu: a coluna de `corte=` saiu com o
MD5 `c0c4bef1223da3d33361af1a4a4640aa` nas **seis** corridas, o mesmo hash de determinismo
que a 004 registrou.

**Falso positivo: zero.** A varredura inteira — **51 combinações**, os controles inclusive —
rodou com a sonda viva e **não gravou uma prova sequer** (o arquivo não chegou a existir),
com `lacuna_topo_max = 0,0 pt` nas oito `real-` e "com moldura menor que o conteúdo: 0".

**3. A prova.** Uma linha JSON por violação em
`~/Library/Application Support/Knobler/corte-do-knob.jsonl`, mais uma linha de `os_log`
(`subsystem com.zoi.knobler`, categoria `corte-do-knob`). Doze campos: `data`, `lacuna_pt`,
`moldura` (x/y/largura/altura), `altura_esperada`, `mode`, `foco`, `ultimo_evento` (a última
transição de seção do VM e há quantos segundos), `animando`, `display`, `notch_real`,
`violacao`, `curou`. **Por que arquivo e não só `os_log`:** o log unificado expira e sai da
máquina só via `log show` com predicado; o arquivo o usuário anexa. Por que Application
Support: é onde `NotificationHistory`, `MessageStore` e `AppSettings` já persistem. Poda em
**50 linhas**, gravação numa fila serial fora da main thread, e o contexto só é montado na
violação (`@autoclosure`) — o caminho normal não constrói nada. Sem bundle id (o processo é
o harness do `cortecheck`, não o app) a prova vai pro `/tmp` e não encosta no arquivo do
usuário.

**4. A cura.** `.id(vigia.geracao)` na moldura: a geração anda **só** quando `avaliar` mede
uma violação, e trocá-la reconstrói a subárvore — o mesmo efeito do ciclo manual de
expandir/recolher que o usuário faz hoje. Espera de **2 s** entre curas, porque a cura gera
geometria nova que volta pro vigia; a prova registra se aquela violação curou ou caiu dentro
da espera.

**5. O gate — e ele falha contra o código de antes.** `tools/cortedetectorcheck.swift`
(hermético, ~0,1 s), registrado em `tools/check.sh`. A linha do check tem **duas** metades:
o grep da fiação na `NotchView` e o harness. Sem o grep, a regressão realista — alguém
arranca o `.background(SensorDeCorte(...))` num refactor — passaria verde, que é exatamente
como este trabalho sumiria da CI sem dar erro. As três saídas:

```
$ # estado ANTES do conserto (Knobler/NotchView.swift de 466ac32, sem CorteDoKnob.swift)
sumiu da NotchView: SensorDeCorte(vigia: vigia
rc=1

$ # CorteDoKnob.swift presente, fiação arrancada da NotchView (o refactor silencioso)
sumiu da NotchView: SensorDeCorte(vigia: vigia
rc=1

$ # estado DEPOIS
custo do invariante: 134 ns por medida (100000 medidas)
cortedetectorcheck ok — invariante, prova e cura travados
rc=0
```

O harness exige: topo no lugar e desvio dentro da tolerância **não** acusam; 60 pt acusam
60,0; a prova sai com os doze campos numa linha JSON e o arquivo poda em 50; a cura corre na
violação e **não** corre dentro da espera; e o custo do caminho normal fica abaixo de 1 ms
(asserção folgada de propósito — número apertado vira gate instável em máquina carregada).

**`./tools/check.sh` inteiro, verde:**

```
  sectionordercheck          ok
  cortedetectorcheck         ok
  ...
  pulado: codex-integration (rode com --com-ambiente)
✅ 38 checks ok
```

**O limite, declarado.** Este detector lê a **geometria de layout** do SwiftUI. Se o defeito
nascer abaixo dela — composição, buffer, WindowServer —, ele fica calado, e a autocura não
corre. Medir pixel em execução está fora: é a câmera do harness, ~200 ms por card. Isso não
torna a entrega meia: um log de provas **vazio** ao lado de um corte testemunhado pelo
usuário é, ele próprio, evidência — joga a causa para baixo do layout e mata a hipótese de
transação divergente da [002](../medicao-002-moldura.md), que é a única que o mapa ainda
tinha de pé.

**Não tocado, de propósito:** os dois achados laterais da 004 (`orderFrontRegardless`
redundante e os 21 ms de `fullscreenDisplays()`) continuam não sendo causa e não foram
consertados aqui. `KnoblerApp.swift` não mudou uma linha.
