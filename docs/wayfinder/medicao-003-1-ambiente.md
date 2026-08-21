# Medição 003.1 — Eventos de ambiente

Método: o mesmo harness da [medição 001](medicao-001-repro.md) — a `NotchView` de verdade
numa `NSHostingView` dentro de uma `NSWindow` fora de qualquer tela, fotografada a cada giro
de runloop e classificada pixel a pixel em fundo, moldura e conteúdo — com um eixo novo. As
transições da 001 mexem no **estado da interface** pelos pontos de entrada do app; as oito
transições novas mexem na **janela**, pelas mesmas chamadas que o `placeWindows`
(`Knobler/KnoblerApp.swift:1195`-`1196`, `setFrame(_:display: true)` seguido de
`orderFrontRegardless()`) e o `orderOut(nil)` (`:1205`) usam. A `Cena` do harness passou a
carregar a janela, então uma transição de ambiente é uma lista de chamadas de `NSWindow`
com o mesmo relógio das outras. Nada em `Knobler/*.swift` foi tocado: a instrumentação toda
vive no envelope (`tools/cortecheck/main.swift`). A métrica é a **lacuna de topo** — a
forma que "aparece apenas a metade de baixo" teria na imagem —, porque "moldura menor que o
conteúdo" está provada cega pela [003](tickets/003-qual-mecanismo-conserta.md).

## O número

**8 transições de ambiente, 17 chamadas de janela dirigidas, 15 com mudança observável no
estado da janela. 0 produziram lacuna de topo: `lacuna_topo_max = 0,0 pt` nas oito — mas
5 das 8 estão sem sensibilidade demonstrada.** O `corte` também é 0 nas oito, e a varredura
inteira — as 35 da 001 mais estas 8 — fecha em **43 combinações, 0 corte**.

Sensibilidade demonstrada quer dizer: existe um defeito injetado que **essa transição
acusou**. A revisão desta medição injetou um desvio de 40 pt gateado em `!janela.isVisible`,
ou seja, um defeito que só existe enquanto a janela está fora de ordem. Três transições o
acusaram com **40,0 pt** — `ambiente-orderout-volta-fechado`, `ambiente-orderout-volta-aberto`
e `ambiente-espaco-simulado`. As outras cinco não, e por dois motivos diferentes:

- `ambiente-orderout-durante-morph` **tinha** o defeito na tela (150 ms com a janela fora de
  ordem) e **não o acusou, em 2 de 2 corridas**, fotografando a 10,7 Hz. Este é o buraco de
  cadência, não de gate — e é o número que o "0 de 8" precisa carregar junto.
- `ambiente-placewindows-parado`, `ambiente-placewindows-durante-morph`,
  `ambiente-setframe-move-origem` e `ambiente-setframe-muda-tamanho` nunca deixam a janela
  fora de ordem, então o gate da injeção não as alcançava. Delas o teste não diz nada, nem a
  favor nem contra.

O zero destas cinco vale menos que o zero das outras três, e o documento não vai fingir o
contrário.

As duas chamadas sem mudança observável são os `setFrame` com o **mesmo** frame do
`ambiente-placewindows-*`: elas foram dirigidas de verdade (o app as faz assim, com
`display: true`), mas não há estado da janela que possa flipar para prová-las. Estão
contadas separadas de propósito — um "17 de 17" ali seria mentira.

| Transição | O que dirige | Quadros | Cadência | Lacuna de topo |
|---|---|---|---|---|
| `ambiente-orderout-volta-fechado` | pilulinha fechada: `orderOut`, 0,30 s, `orderFrontRegardless` | 129 | 67 Hz | 0,0 pt |
| `ambiente-orderout-volta-aberto` | card do link aberto, mesmo ciclo | 35 | 18 Hz | 0,0 pt |
| `ambiente-orderout-durante-morph` | `orderOut` 50 ms depois do card começar a fechar, volta em 200 ms, reabre em 600 ms | 23 | 10 Hz | 0,0 pt |
| `ambiente-espaco-simulado` | a forma da troca de Space: `orderOut`, **0,35 s**, `orderFrontRegardless` | 36 | 18 Hz | 0,0 pt |
| `ambiente-placewindows-parado` | `placeWindows` literal: `setFrame(igual, display: true)` + `orderFrontRegardless` no mesmo giro | 112 | 69 Hz | 0,0 pt |
| `ambiente-placewindows-durante-morph` | o mesmo, no meio da troca de `mode` | 24 | 11 Hz | 0,0 pt |
| `ambiente-setframe-move-origem` | a janela muda de posição e volta (o que uma resolução nova faria) | 39 | 18 Hz | 0,0 pt |
| `ambiente-setframe-muda-tamanho` | a janela muda de tamanho com a view viva dentro (900×640 → 700×900 → 900×640) | 37 | 17 Hz | 0,0 pt |

Contagem de quadros e cadência são de uma corrida específica e dependem da máquina; a
lacuna de topo e o veredicto, não.

## Os controles — por que este zero não é um zero de instrumento

A 001 já provou que o detector enxerga (moldura sintética: excedente de **100,0 pt**) e que
enxerga **na `NotchView` de verdade** (a view real empurrada 60 pt pra baixo acusa lacuna de
**60,0 pt** em todos os quadros). Um evento de ambiente precisa de mais dois, porque ele tem
duas falhas silenciosas próprias:

- **A janela escondida cega a foto?** `controle-ambiente-orderout-parado`: pilulinha
  fechada, `orderOut` no primeiro passo e nada mais. Se o `cacheDisplay` parasse de devolver
  o desenho só por a janela estar fora de ordem, todo quadro medido durante um `orderOut`
  sairia vazio por artefato e a família inteira mediria o instrumento. Mede **32 pt em todos
  os quadros** (110 quadros na corrida citada, todos 32; a contagem varia com a máquina, o
  "todos" não). O harness aborta com código 1 se algum quadro sair diferente de 32.
- **O detector continua enxergando ATRAVESSANDO o evento?** `controle-ambiente-desvio`: a
  mesma injeção de 60 pt da 001, agora com o ciclo `orderOut`/`orderFrontRegardless` correndo
  por cima. Exige lacuna de **60,0 pt** e corte em **todos** os quadros — e sai
  **69/69** na corrida citada (o 69 é contagem de quadros e varia; o "todos" é o exato). Sem isso, "0 de 8" poderia ser o `orderOut` apagando a medida, não o app
  passando no teste.

Os quatro controles da 001 continuam valendo e continuam abortando com código 1.

## O evento aconteceu? A prova, chamada por chamada

Toda chamada de janela passa por um registro que fotografa `isVisible` e `frame` antes e
depois. Sem ele, um `orderOut` que não escondesse nada devolveria um zero: o harness teria
medido a ausência do evento, não a ausência do defeito.

```
orderOut:                              6 dirigidos, 6 com mudança observável
orderFrontRegardless:                  5 dirigidos, 5 com mudança observável
setFrame(origem):                      1 dirigido,  1 com mudança observável
setFrame(origem de volta):             1 dirigido,  1 com mudança observável
setFrame(tamanho):                     1 dirigido,  1 com mudança observável
setFrame(tamanho de volta):            1 dirigido,  1 com mudança observável
setFrame(igual)+orderFrontRegardless:  2 dirigidos, 0 com mudança observável
```

`visivel=sim → visivel=nao` nos seis `orderOut`, `nao → sim` nos cinco
`orderFrontRegardless`, `900x640@-20000,-20000 → 700x900@-20000,-20000` no `setFrame` de
tamanho. Os seis `orderOut` são cinco das transições mais o controle.

## Os quadros magenta: é quadro de verdade, não buffer sem desenho

A pergunta da 001 era se as fotos magenta puro — sem moldura e sem conteúdo — são o
`cacheDisplay` devolvendo um buffer que ninguém desenhou, ou um quadro real em que a árvore
não desenhou nada. **Não é buffer virgem: o `cacheDisplay` rodou e desenhou o irmão magenta
na mesma foto.** Essa é a parte que a evidência sustenta sozinha. "Quadro real em que a
árvore não desenhou nada" é a leitura mais provável, mas **com ressalva**: as duas provas
fortes abaixo saem do mesmo `cacheDisplay`, e uma cegueira sistemática dele ao
`compositingGroup` filtrado durante o `.blurReplace` produziria exatamente esses dois
resultados. A terceira evidência é a que quebraria o empate, e ela é justamente a que pode
ser cega ao caso. Três evidências, todas medidas:

1. **O fundo desenhou na mesma foto.** O magenta não é buffer virgem: é um
   `Color(red: 1, green: 0, blue: 1)` irmão da `NotchView` dentro da mesma raiz SwiftUI. Se
   o `cacheDisplay` tivesse devolvido um bitmap não desenhado, o fundo também não estaria
   lá. A captura rodou; quem não pôs pixel foi a `NotchView`.
2. **Uma segunda foto no mesmo giro de runloop dá o mesmo vazio.** Todo quadro vazio dispara
   um segundo `cacheDisplay` num bitmap novo, sem nenhum giro de runloop entre os dois —
   nada no modelo muda entre as duas fotos. **0 voltaram a mostrar o notch na segunda foto**,
   em nenhuma das três varreduras completas (38, 35 e 26 quadros vazios examinados). Se o
   vazio fosse do caminho de captura, a segunda foto o desmentiria em algum deles.
3. **Um segundo caminho de captura vê o mesmo vazio.** `CALayer.render(in:)` é outro
   mecanismo e desenha a árvore de **modelo**. Ele é aferido num quadro que ninguém discute
   (a pilulinha parada: `cacheDisplay = 32,0 pt`, camada = **32,0 pt**, concordam) e, nos
   quadros vazios, encontrou desenho em **0** — o exato é o numerador: o denominador é
   quantos quadros vazios a corrida conseguiu examinar por esse caminho, no máximo **8**
   (o teto de fotos por camada), e ele varia com a cadência. 0 nas três varreduras.

O que sustenta o "quadro real" é (1) e (2); (3) é corroboração com ressalva, porque
`CALayer.render(in:)` não aplica filtro de camada e a transição de `mode` é uma
`.transition(.blurReplace)` — a foto por camada pode ser cega justamente ao caso, mesmo com
o controle passando num quadro estático.

O mecanismo que o código sugere, e que é leitura, não medida: moldura e conteúdo do notch
vivem no mesmo `ZStack` sob um `.compositingGroup()` seguido de `.mask(shape)`
(`Knobler/NotchView.swift:182`, `:248`, `:249`). O `compositingGroup` junta os dois num
único buffer fora da tela antes da máscara — é exatamente por isso que o vazio nunca é
parcial: em **0** dos quadros vazios (das três varreduras) havia conteúdo desenhado sem
moldura. O grupo inteiro contribui zero pixel, ou contribui os dois.

**Alguns vazios voltam** — `subida > 0` em toda corrida medida, ou seja, sempre há vazio
entre uma altura menor e uma maior seguinte. Só isso, e o que vem a seguir, sobrevive à
repetição.

A única coisa **exata** do contorno é **`descida=0`**, que saiu zero em todas as corridas
medidas, minhas e da revisão (5/5): nenhum vazio cai entre uma altura maior e uma menor, o
que mata a explicação mais simples — a mola do morph passando por altura zero enquanto
encolhe.

Todo o resto do contorno **oscila com a cadência, sem teto, e não é conclusão**. As minhas três
varreduras completas mediram `patamar` 16, 16 e 1 e `borda` 0, 0, 0; cinco corridas da
revisão mediram `borda` 0, 2, 11, 17, 0, `terminaram vazias` 0, 1, 1, 3, 0 e `patamar` **0
em quatro das cinco**. Uma versão anterior deste documento leu esses números como "o vazio
sempre volta e nunca sobra no fim da série", e isso **não reproduz**: uma corrida lenta
termina a série com a árvore ainda vazia, e nesse caso o harness simplesmente não sabe se
ela voltou depois do último quadro. `patamar > 0` — o notch sumindo e voltando do mesmo
tamanho, que seria a forma mais limpa de "piscar" — apareceu nas minhas corridas e não nas
da revisão, e voltou a `17` na primeira corrida depois deste conserto; não é achado, é
sorte de amostragem.

Não é o sintoma relatado — some tudo, não a metade de cima. E, com o `patamar` fora da
evidência, o que sobra é mais modesto que "pisca": a árvore para de desenhar por um ou mais
quadros em cima de uma troca de `mode` e **volta** (`subida > 0` em toda corrida). Isso é
medido e não é artefato do instrumento; que ele apareça na tela do usuário como um piscar é
leitura, não medida.

## Mudanças no instrumento, e por que

- **Janela de observação de 0,8 s → 1,6 s.** As transições que fecham e reabrem o card
  fotografam a **2–11 Hz** (o `cacheDisplay` de um card de 530 pt custa ~200 ms), e com
  0,8 s os quadros vazios caíam no **fim** da série: sem um quadro depois deles, não dava
  para dizer se a árvore voltava a desenhar. A janela maior alivia isso, mas **não resolve**
  — numa corrida lenta a série ainda termina vazia (ver o contorno dos vazios).
- **Raiz do envelope ancorada no topo** (`.frame(maxWidth: .infinity, maxHeight: .infinity,
  alignment: .top)` no lugar do tamanho fixo). Sem isso, o `setFrame` que muda o tamanho da
  janela centralizaria o conteúdo e a lacuna de topo acusaria um corte que é layout do
  harness. Com a janela no tamanho de sempre é idêntico ao anterior — as 35 combinações da
  001 continuam em 0.
- **Teto de 8 fotos por camada por corrida.** A foto por camada custa ~200 ms e come a
  cadência justamente nas transições de `mode`, onde mais interessa amostrar: sem teto, o
  controle positivo caiu de **40 para 10 quadros**. Com teto, a segunda câmera responde a
  pergunta dos magenta sem estragar a varredura.
- **`CORTECHECK_FAMILIA`** roda uma família só — e **nunca** pula um controle.

## Limites — o que este "0 de 8" não cobre

- **Cinco das oito não têm sensibilidade demonstrada** — ver a seção do número. A injeção de
  revisão só existia com a janela fora de ordem, então as quatro transições de `setFrame` e
  `placeWindows` nunca a viram, e a `ambiente-orderout-durante-morph` a viu e não a acusou.

- **A troca de Space não existe neste código.** O brief cita um `applyVisibility` em
  `KnoblerApp.swift:1073` e um tratamento de troca de Space com 0,35 s de atraso: nenhum dos
  dois existe neste worktree. `grep -rn 'activeSpace' Knobler/` não devolve nada, e
  `git log -S activeSpaceDidChange --all` também não — o único observador de ambiente que
  mexe na janela é o `didChangeScreenParametersNotification` (`KnoblerApp.swift:362`), que
  chama `placeWindows`. (`NSWorkspace.didWakeNotification` é observado, mas só por
  `WebhookClient` e `Reminders`: nada ali toca a `NotchWindow`.) A `NotchWindow` tem `.canJoinAllSpaces` e `.stationary`
  (`Knobler/NotchWindow.swift:30`-`33`), ou seja: **numa troca de Space o app não esconde
  janela nenhuma**. O que a `ambiente-espaco-simulado` roda é a *forma* descrita no brief
  (esconder, esperar 0,35 s, devolver), não uma chamada que o app faça.
- **Sono e troca de resolução ficaram de fora, por decisão de não mexer na máquina.**
  Adormecer o Mac ou trocar o modo do display são eventos de sistema que atingem a sessão
  gráfica do usuário, não só o harness. O que dá para simular sem tocar no hardware — a
  janela mudando de origem e de tamanho, que é o que o `placeWindows` faz depois de uma
  mudança de tela — está varrido; a parte que exige o WindowServer de verdade (o display
  reiniciando, o `backingScaleFactor` mudando, o app voltando do sono) não está.
- **Cadência, e este é o limite que morde.** Continua valendo o da 001, e pior nas
  transições de ambiente durante morph: **2–11 Hz**. E não é mais um limite teórico: na
  injeção de revisão, um defeito de **~150 ms** — nove quadros a 60 Hz — passou **inteiro**
  pela `ambiente-orderout-durante-morph`, em 2 de 2 corridas, com a transição fotografando a
  10,7 Hz. Um corte que dure menos que isso, nessas transições, este harness não pega.
- **A janela do harness é uma `NSWindow` comum, não a `NotchWindow`.** `NotchWindow.swift`
  não está em `tools/notchview-fontes.txt`, então o painel de verdade (nível
  `.mainMenu + 3`, `isOpaque = false`, `.canJoinAllSpaces`) não entra na compilação isolada.
  Para `orderOut`/`setFrame` a diferença é de política de janela, não de desenho — mas é uma
  diferença, e é onde eu olharia se um dia um desses eventos virar suspeito outra vez.
- **A prova (3) dos magenta tem ressalva** — ver a seção deles.

## Determinismo

A família `ambiente` rodou **3 vezes** e a varredura completa (43 combinações) rodou **3
vezes**: a coluna de veredicto das transições (`corte=N`) saiu com o **mesmo MD5 nas três**,
nos dois casos. O que varia entre corridas é a contagem de quadros por transição, a cadência
e quantos quadros vazios a corrida calha de pegar (12 a 24 na varredura completa) — não o
veredicto.

## Verificação

```bash
# só a família de ambiente, com todos os controles (~1 min)
CORTECHECK_FAMILIA=ambiente ./tools/cortecheck.sh

# Os valores EXATOS (refazem a conta): 8 combinações, 0 corte, lacuna_topo_max 0,0 pt
# nas oito, 17 eventos dirigidos / 15 com mudança observável, controle do desvio
# atravessando o orderOut = 60,0 pt, controle da camada = 32,0 pt nos dois caminhos,
# "sumiram na 2ª foto do mesmo giro" = 0, "com desenho na foto por camada" = 0.
# Dependem da máquina: contagem de quadros e Hz vêm como faixa medida. Quantos
# quadros vazios a corrida produz é **sem teto** — 6 a 38 nas corridas medidas, e
# não é banda: é cadência. Idem `patamar`, `borda` e "terminou vazia".

# a injeção de sensibilidade (de onde saem os 40,0 pt, os 150 ms e o "2 de 2").
# Ela NÃO está no harness: é um patch de revisão — aplicar, rodar, reverter.
#   1. no envelope do harness, um objeto observável com `@Published var deslocado`
#      e a raiz do `rodar` vestida por um ViewModifier que o observe, com
#      `.padding(.top, injecao.deslocado ? 40 : 0)`;
#   2. dentro do `evento(_:_:_:)`, depois de rodar a ação:
#      `if transicaoCorrente.hasPrefix("ambiente-") { injecao.deslocado = !j.isVisible }`;
#   3. no começo do `rodar`, `injecao.deslocado = false`, senão a transição
#      seguinte herda o desvio.
# Com isso o defeito só existe enquanto a janela está fora de ordem: as três
# transições que escondem a janela acusam lacuna 40,0 pt, a `orderout-durante-morph`
# não acusa (150 ms a 10,7 Hz), e as quatro de setFrame/placeWindows nunca o veem.

# as linhas que fecham a conta
CORTECHECK_FAMILIA=ambiente ./tools/cortecheck.sh \
  | grep -E 'controle|ambiente-|eventos de ambiente|dirigidos|vazios|contorno|TERMINARAM'
# → controle do ambiente (orderOut parado): alturas [32, 32, ...]  (TODAS 32)
#   controle do desvio atravessando o orderOut: lacuna_topo_max=60.0 pt, corte=N/N
#     (o N varia com a máquina; o exato é os dois lados serem iguais)
#   controle da camada (2ª câmera): cacheDisplay=32.0 pt, camada=32.0 pt — concordam
#   as 8 linhas ambiente-*: corte= 0 e lacuna_topo_max=  0.0 pt
#   contorno dos vazios: o exato é descida=0 (e subida > 0). patamar e borda são
#     SEM TETO — 0 a 17 nas corridas medidas, e a faixa já estourou duas vezes;
#     não trate como banda a bater
#   transições que TERMINARAM vazias: sem teto (0 a 3 medidos). NÃO é veredicto:
#     mede a cadência da máquina, não o app
#   quadros vazios examinados: N — sumiram na 2ª foto do mesmo giro: 0,
#     com desenho na foto por camada: 0/N — o exato é o 0; o N é quantos vazios
#     couberam no teto de 8, e varia com a cadência
#   eventos de ambiente dirigidos: 17 — com mudança observável na janela: 15

# o registro chamada a chamada (o antes → depois de cada evento)
CORTECHECK_VERBOSE=1 CORTECHECK_FAMILIA=ambiente ./tools/cortecheck.sh | grep '·'
# → ambiente-orderout-volta-aberto · orderOut: visivel=sim … → visivel=nao …
#   ambiente-setframe-muda-tamanho · setFrame(tamanho): … 900x640@… → 700x900@…

# a varredura inteira, 35 da 001 + 8 de ambiente (~3 min)
./tools/cortecheck.sh | grep -E 'combinações rodadas|com moldura menor|corte= *[1-9]'
# → combinações rodadas: 43
#   com moldura menor que o conteúdo: 0
#   a única linha com corte>0 é a do controle do desvio atravessando o orderOut
#     (é exatamente o que ele prova)

# determinismo. O `grep -E '^  [a-z]'` pega só as linhas de transição: a linha do
# controle do desvio imprime "corte=N/N", e esse N é contagem de quadros, que
# muda com a máquina — dentro do hash ele estragaria a comparação.
for i in 1 2 3; do CORTECHECK_FAMILIA=ambiente ./tools/cortecheck.sh > /tmp/amb$i.txt 2>&1; done
for i in 1 2 3; do grep -E '^  [a-z]' /tmp/amb$i.txt | grep -o 'corte= *[0-9]*' | tr -d ' ' | md5 -q; done
# → três hashes iguais (idem trocando a família pela varredura inteira)

# o custo da 2ª câmera, que é o motivo do teto de 8
CORTECHECK_SEM_CAMADA=1 ./tools/cortecheck.sh | grep 'controle positivo'
# → sem a foto por camada o controle positivo pega ~40 quadros; sem teto ele caía
#   para ~10. Com o teto de 8 fica no meio.

# o que o app faz de verdade com a janela (os pontos de entrada dirigidos)
grep -n 'setFrame\|orderFrontRegardless\|orderOut' Knobler/KnoblerApp.swift
# → 1195 setFrame(frame, display: true) · 1196 orderFrontRegardless() · 1205 orderOut(nil)

# não existe tratamento de troca de Space neste código
grep -rn 'activeSpace' Knobler/*.swift
# → nada
# e o retorno do sono não chega perto da janela do notch
grep -rn 'didWakeNotification' Knobler/*.swift
# → só WebhookClient (reconecta), Reminders e o registro de peças — nenhum toca
#   em NotchWindow nem chama placeWindows
grep -n 'canJoinAllSpaces' Knobler/NotchWindow.swift
# → 32

# o compositingGroup que junta moldura e conteúdo num buffer só
grep -n 'compositingGroup\|\.mask(shape)\|shape.fill' Knobler/NotchView.swift
# → 182 shape.fill(Color.black) · 248 .compositingGroup() · 249 .mask(shape)
```
