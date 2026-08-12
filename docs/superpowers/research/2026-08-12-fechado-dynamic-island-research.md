# Pesquisa — notch fechado com música idêntico à Dynamic Island

Spec: `docs/superpowers/specs/2026-08-12-fechado-dynamic-island-design.md`

A frente externa achou a implementação da Apple, não descrições dela. O indicador
da Dynamic Island é `MRUWaveformView` + `MRUAudioAnalyzer`, em
`MediaControls.framework`, usado por `MRUActivityNowPlayingView`. Os números
abaixo saem de decompilação de binário da Apple (iOS 18.2, confirmado ainda
válido no runtime 26.5) e de um asset de animação da própria Apple decodificado
byte a byte. Onde a fonte é fraca, está dito.

Cópias locais do material: `mru/*.m` (decompilado) e `caar3.py` (decodificador do
asset) no scratchpad da sessão — some quando a sessão morrer, então os números que
importam estão transcritos aqui.

## Achados externos

### A1 — A Apple usa FFT de áudio real; a spec decidiu remover exatamente isso

`MRUAudioAnalyzer` é um analisador de espectro com Accelerate: janela de Hann,
`vDSP_ctoz`, `vDSP_fft_zrip`, `vDSP_zvmags`, taxa de 48 kHz, alimentado por um tap
no processo do player (`MPCProcessAudioTap`, `+audioAnalyzerForPID:`). É a mesma
mecânica que o `AudioLevelTap.swift` do Knobler já implementa. O analisador só
roda com `playing && visible && routeSupportsWaveform && nowPlayingPID`; fora
disso o dado vira `+[MRUWaveformData zero]`. Não há laço, não há período de
repetição nesse caminho.

- Fonte: `MRUAudioAnalyzer.m` (ivars `_fftSetup`, `_hannWindow`, `_magnitudes`,
  `_tap`, `_pid`, `_sampleRate`), decompilado de `MediaControls.framework`;
  headers independentes de runtime iOS 16 e iOS 17 mostram os mesmos ivars.
- Contradiz a spec: **sim**, na decisão central.
- Pergunta que levanta: a spec mandou tirar a reação ao som para ficar idêntica
  ao iPhone, e o achado diz que o iPhone reage ao som. Manter o que já existe
  passa a ser o caminho do idêntico — e a permissão de gravação de áudio do
  sistema fica. Vale desfazer a decisão de remover?

### A2 — São 6 barras, não 5

`+[MRUWaveformData amplitudeCount] { return 6; }`, literal. `MRUWaveformView`
cria `[settings.stops count] - 1` barras, ou seja 7 bordas de banda. O Knobler
tem 5 barras e 6 bordas hoje.

- Fonte: `MRUWaveformData.m:41-43`; `MRUWaveformView.m`.
- Contradiz a spec: **parcial** (a spec não fixou número; fixa agora).
- Pergunta que levanta: adotar 6 barras aumenta a largura mínima do visualizador
  e mexe no orçamento da asa direita.

### A3 — Geometria exata do indicador

Área do acessório trailing: **22 × 22 pt**. Dentro dela, `layoutSubviews`:

```
slot   = largura / 6          = 3.667
barra  = slot * 0.5           = 1.833     (vão == largura da barra)
raio   = barra / 2            = 0.917     (cápsula perfeita)
centro = barra + i * slot ,  y = meio da área    (cresce do CENTRO, não da base)
```

Altura: `max(min(amplitude, 1) * altura, largura_da_barra)` — o piso é a própria
largura, então amplitude zero vira um ponto redondo, nunca some.

Hoje o Knobler usa uma área de 27 × 21, cinco barras, largura `w / (5 × 2.1)` e
vão `largura × 1.1` — barras mais grossas, vão maior, e o piso vem de um cálculo
diferente.

- Fonte: `MRUWaveformView.m:214-224` (layout) e `:468-497` (alturas e raio);
  `MRUActivityNowPlayingView.m:54` (22 × 22). Cross-check independente:
  `WaveformSize.liveActivity` no `MediaCoreUI` local também dá 22 × 22.
- Contradiz a spec: **parcial** — confirma "medidas absolutas", fixa os valores.
- Pergunta que levanta: 22 × 22 é menor que os 27 × 21 de hoje; o desenho fica
  mais discreto do que o usuário vê agora.

### A4 — A barra engorda no pico, não só cresce

`largura = largura_base + 0.66 × amplitude`, com o raio recalculado como
`largura / 2` a cada quadro. O Knobler só escala em Y.

- Fonte: `MRUWaveformView.m:477` (`xScaleMultiplier`, literal 0.66) e `:497`.
- Contradiz a spec: **parcial** (detalhe que a spec não previu).
- Pergunta que levanta: é um detalhe de 0,66 pt. Entra ou é ruído no Mac?

### A5 — A cor não é tinta: as barras são um recorte sobre a capa

As barras são brancas e servem de máscara — a capa aparece **através** delas,
depois de passar por desfoque e saturação. Há correção automática de capa muito
escura (camada branca em "lighten") e muito clara (camada preta). Sem capa, cinza
fixo `#646464`, com cross-fade de 0,5 s.

Os valores de desfoque, saturação e os limiares de luminância ficaram em dados
que o decompilador não expôs: **sem fonte confiável**.

- Fonte: `MRUWaveformView.m` (`-updateArtworkFilters`, `_barsView`,
  `_contentLayer`); símbolos `WaveformTheme.artwork(image:)` no `MediaCoreUI`.
- Contradiz a spec: **sim**. Hoje o Knobler pinta as barras com uma cor sólida
  extraída da capa.
- Pergunta que levanta: o recorte sobre a capa é o que dá o brilho colorido do
  iPhone. Copiar isso é mais caro que trocar uma cor, e os parâmetros do desfoque
  vão ter que ser calibrados no olho.

### A6 — Pausado: pontinhos, capa escurecida, curva de animação própria

Ao pausar, o analisador cai e o dado vira zero: com o piso do A3, as seis barras
viram seis pontos alinhados. Não somem e não congelam na altura em que estavam.
A capa escurece para opacidade 0,5 em 0,2 s. A transição de pausa usa duração e
amortecimento próprios, diferentes dos de tocando.

Por quanto tempo a ilha permanece visível depois de pausar: **sem fonte
confiável** — essa política mora no SpringBoard, não no framework analisado.

- Fonte: `MRUWaveformViewController.m` (`updateAnalyzer`, `pausedAnimationDuration`,
  `pausedSpringDamping`); `MRUActivityNowPlayingView.m` (`setDimsWhenPaused:`).
- Contradiz a spec: **não** — confirma "pausado permanece visível" e acrescenta o
  escurecimento da capa.
- Pergunta que levanta: o Knobler adota o escurecimento da capa no pausado?

### A7 — Movimento: uma mola por atualização, sem defasagem entre barras

Não existe duração por barra nem atraso escalonado. A cada dado novo do
analisador, todas as barras recebem **uma** animação de mola em conjunto. A
irregularidade que se vê vem do espectro, não da animação. A taxa de quadros é
variável conforme o quanto o espectro mudou: mínimo 5, máximo 48, e 30 em modo de
baixo consumo. Os números da mola (duração, amortecimento) ficaram em dados não
expostos: **sem fonte confiável**.

- Fonte: `MRUWaveformViewController.m` (`updateWaveformWithData:`,
  `framerateRangeForData:`); `MRUWaveformSettings.m` (literais 48 / 30 / 5).
- Contradiz a spec: **sim**. A spec escolheu "cada barra com laço próprio,
  duração e defasagem próprias" — isso é o oposto do que a Apple faz.
- Pergunta que levanta: com áudio real (A1), o motor certo é mola por atualização.
  Sem áudio real, o motor certo é o A8. O laço por barra não é nenhum dos dois.

### A8 — A Apple tem uma animação enlatada, e ela está decodificada

`BouncyBars.caar`, em `MediaCoreUI.framework`, é o fallback que o indicador do app
Música usa quando não há análise ao vivo. É um `CALayer` arquivado com
`CAKeyframeAnimation`, decodificado inteiro:

- canvas 100 × 100, **5 barras**, largura 12,5, raio 6,5, canto circular
- centros em x = 6,2 / 28,1 / 50,0 / 71,9 / 93,8 — passo 21,9, vão 9,4
- anima a **altura** com o centro fixo: cresce do meio
- ciclo de **2,66 s**, 12 quadros-chave uniformes (~0,2418 s cada), interpolação
  cúbica, repetição infinita, primeiro valor igual ao último (laço sem emenda)
- 3 variantes = as mesmas 5 sequências permutadas entre posições

Sequências (altura em % do canvas):

```
S1  49    51    42.9  78.9  65.5  31    47.3  51    53.2  68.8  70.9  49
S2  77    48    77    55.2  45.1  46.1  88.1  70    90.7  53.4  51.9  77
S3  60    68    58    82.9  68    79    61.4  88    57.1  82.9  62    60
S4  33    58.9  68    46.9  93.7  59.9  71.7  52    68.8  44    73    33
S5  40    24    48.9  57    42.1  33.9  25    72    29    58.8  50.1  40

A = S1 S2 S3 S4 S5    B = S5 S3 S1 S2 S4    C = S2 S1 S4 S3 S5
```

- Fonte: asset binário da Apple decodificado nesta máquina (`caar3.py`).
- Contradiz a spec: **parcial** — dá um caminho sintético muito melhor que o
  inventado, se o caminho sintético for escolhido.
- Pergunta que levanta: se a decisão for não ouvir o áudio, tocar a curva que a
  Apple desenhou é mais fiel que qualquer senoide — mas são 5 barras, não 6.

### A9 — Geometria do lado da capa

Acessório leading: **26 × 22 pt** (não quadrado). Raio de canto **5,5 pt** com
cantos contínuos quando a capa é quadrada, 3,0 pt quando não é. A imagem é
buscada em 30 × 30. Sem capa, o Knobler precisa decidir sozinho: o caminho da
Apple aqui é o SpringBoard entregar o ícone do app como capa, o que é
**inferência, sem fonte**.

- Fonte: `MRUActivityNowPlayingView.m:45` (26 × 22); `MRUArtworkCornerRadius` /
  `MRUFlippingArtworkView`; `MRUWaveformController.m` (30 × 30).
- Contradiz a spec: **parcial**. Hoje o Knobler usa 25 × 25 com raio 7.
- Pergunta que levanta: a capa passa a ser levemente retangular e com canto menor.

### A10 — Armadilhas de animação em laço no SwiftUI

Três coisas documentadas mordem a abordagem "laço infinito por barra":
`repeatForever` combinado com atraso muda de significado conforme a ordem dos
modificadores e há relato de o atraso simplesmente não valer; cada novo valor
publicado **empilha** outra animação infinita, e a CPU sobe com o tempo (relato de
95% num caso); e cancelar uma animação infinita passando `nil` não funciona — é
preciso reemitir a mesma animação sem a repetição. Some a isso que animação
continua rodando com a janela ocluída se ninguém parar: a saída é observar a
mudança de oclusão da janela, como faz o `DynamicNotch`.

- Fonte: `https://sarunw.com/posts/animation-delay-and-repeatforever-in-swiftui/`,
  `https://stackoverflow.com/questions/71537623/`,
  `https://developer.apple.com/forums/thread/767243`,
  `https://stackoverflow.com/questions/59133826/`,
  `https://developer.apple.com/documentation/appkit/nswindow/occlusionstate`.
- Contradiz a spec: **sim**, contra o motor escolhido.
- Pergunta que levanta: o motor escolhido na spec é justamente o que mais dá
  problema em SwiftUI.

### A11 — Escalar só em Y deforma a ponta da cápsula

`scaleEffect` em Y não recalcula o raio, então a ponta arredondada achata ou
estica. A Apple anima a altura da camada, com o raio recalculado. O Knobler usa
`scaleEffect` hoje — e foi escolha deliberada, para animar por transformação em
vez de relayout.

- Fonte: documentação do `Capsule`; `MRUWaveformView.m:497`
  (`setCornerRadius: largura * 0.5` a cada atualização).
- Contradiz a spec: **parcial**.
- Pergunta que levanta: numa barra de 1,8 pt de largura, a deformação da ponta é
  visível ou irrelevante?

### A12 — Um app de notch para macOS já resolveu isso

`jackson-storm/DynamicNotch`, em
`Features/NowPlaying/Components/LightweightNowPlayingEqualizerView.swift`: 6
barras, largura 2, vão 2, altura 16, escala mínima 0,32, animação de 0,2 s
`easeInEaseOut` a cada 0,12 s, taxa de quadros presa em 24, raio
`largura × 0,65` com canto contínuo, e — por dedução independente — pausado com
escala igual a `largura / altura`, os mesmos pontinhos da Apple. Para e retoma
observando a oclusão da janela. `boring.notch` usa 4 barras com escala aleatória
e é bem menos fiel.

- Fonte: repositórios clonados no scratchpad da sessão.
- Contradiz a spec: **não**.
- Pergunta que levanta: serve de referência de calibração para o Mac, onde 22 pt
  pode ficar pequeno demais.

### A13 — O tap de áudio do Knobler é legítimo no target

`AudioHardwareCreateProcessTap` está marcado como disponível a partir do macOS
14.2, exatamente o deployment target do projeto. Não é gambiarra nem exige
guarda de disponibilidade.

- Fonte: `AudioHardwareTapping.h:44` no SDK local.
- Contradiz a spec: **não**, mas remove o argumento "o tap é frágil".

## Achados internos

### A14 — A largura do notch fechado é binária, não derivada do conteúdo

`currentSize` no caso fechado devolve `notchSize.width + 44 × 2` quando há
conteúdo, ou o literal 200 sem notch real. Nenhum dos dois consulta a largura
real da capa ou das barras. E tudo é cortado em silêncio por uma máscara, então
excesso não aparece como estouro: some.

- Fonte: `Knobler/NotchView.swift:349-367`, `:141`, `:249-250`.
- Contradiz a spec: **não**, mas a spec ignorou.
- Pergunta que levanta: mudar as medidas da capa e das barras muda o quanto sobra
  dentro dos 44 pt por asa.

### A15 — A asa direita já estoura no pior caso

Pontinho da nota e ícone de microfone empilham livremente com as barras; só o
anel de atividade as exclui. Pior caso hoje: 4 + 8 + 10 + 8 + 27 = 57 pt mais 12
de padding = 69 pt dentro de uma asa de 44 — cortado pela máscara sem aviso.

- Fonte: `Knobler/NotchView.swift:761-789`.
- Contradiz a spec: **não** (a spec deixou esses ocupantes fora do escopo).
- Pergunta que levanta: encolher as barras para 22 pt melhora o pior caso em 5
  pt, mas não resolve. Corrigir agora ou registrar e deixar?

### A16 — Já existe um interruptor "visualizador ao vivo" nos Ajustes

`AppSettings.liveAudioVisualizer` controla se o tap liga, com linha própria no
painel de Ajustes. A spec falou em remover a captura sem mencionar que o usuário
já pode desligá-la.

- Fonte: `Knobler/AppSettings.swift:31`, `Knobler/SettingsView.swift:333`,
  `Knobler/KnoblerApp.swift:903`.
- Contradiz a spec: **parcial**.
- Pergunta que levanta: se o áudio real ficar (A1), esse interruptor passa a
  escolher entre ouvir o som e tocar a curva enlatada do A8 — vira uma decisão
  boa em vez de um degradê.

### A17 — A spec esqueceu quatro pontos de remoção

Não estão listados: `visualizerTapped` exposto no `/status` da API local
(`KnoblerApp.swift:633`), a chave já materializada em `Knobler/Info.plist:27-28`
(o arquivo é versionado **e** gerado), quatro menções no `README.md` (incluindo o
número "~11% de um core com música tocando", que muda), e os dois call-sites do
harness de snapshot (`tools/main.swift:577` e `:634`).

- Fonte: varredura do repositório.
- Contradiz a spec: **parcial** (omissão).
- Pergunta que levanta: nenhuma — é lista a completar no plano.

### A18 — Dois cenários de snapshot perdem o sentido

`closed-paused-hidden` ("deve parecer ilha vazia") e `closed-paused-peek`
("asinhas com pontinhos") existem justamente para provar a regra que a spec
inverte. Com pausado visível, os dois passam a renderizar a mesma coisa que o
cenário novo.

- Fonte: `tools/main.swift:167-177`.
- Contradiz a spec: **parcial** (consequência não mapeada).
- Pergunta que levanta: os dois viram um só, ou o "peek" ganha outro papel?

### A19 — O estágio de "espiada" no hover perde a função

O peek existe para revelar as asas escondidas quando a música está pausada. Com
as asas sempre visíveis, o estágio some de utilidade: hoje ele atrasa a abertura
do card completo em duas etapas.

- Fonte: `Knobler/NotchViewModel.swift:387-394`, `:368-370`.
- Contradiz a spec: **sim**, por consequência.
- Pergunta que levanta: o hover passa a abrir o card direto, ou o atraso de duas
  etapas continua valendo por outro motivo?

### A20 — A geometria pura tem que nascer fora do NotchView

Os harnesses do projeto compilam só os arquivos listados. Se a geometria ficar
dentro de `NotchView.swift`, o check arrasta a árvore SwiftUI inteira — o
precedente do `eventoscheck` são 22 arquivos para isolar um view model. Num
arquivo próprio sem views, o check é uma linha.

- Fonte: `tools/check.sh:53-61`, `:127-136`; molde em `tools/colorpickercheck.swift`.
- Contradiz a spec: **não**, detalha.

## Fila do grill

Ordenada por dependência.

1. **A1 — A Apple analisa o áudio real; a spec mandou remover isso.** Trava A7,
   A8, A16, e a lista inteira de remoções.
2. **A5 — Barras como recorte sobre a capa, não barras tingidas.** Trava a
   decisão de esforço visual e o formato do parâmetro de cor.
3. **A7 e A8 — Que motor de animação, agora que o laço por barra é o pior dos
   três?** Depende de A1.
4. **A2 e A3 — Seis barras de 1,8 pt numa área de 22 × 22 é bem menor do que
   está hoje.** Aceitar o tamanho do iPhone ou calibrar para a tela do Mac (A12)?
5. **A9 — Capa 26 × 22 com raio 5,5 no lugar de 25 × 25 com raio 7.**
6. **A19 e A18 — O que acontece com a espiada no hover e com os dois cenários de
   snapshot que provam a regra antiga.**
7. **A15 — A asa direita já estoura no pior caso.** Corrigir junto ou registrar?
8. **A4, A6, A11 — Detalhes finos:** barra que engorda no pico, capa que escurece
   ao pausar, ponta da cápsula deformada por escala em Y.
