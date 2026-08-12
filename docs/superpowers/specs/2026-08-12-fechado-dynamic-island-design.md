# Notch fechado com música idêntico à Dynamic Island

**Data:** 2026-08-12
**Estado:** spec revisada no grill, pronta para o plano
**Pesquisa:** `docs/superpowers/research/2026-08-12-fechado-dynamic-island-research.md`

## Problema

O estado fechado com música — capa à esquerda, barras de áudio à direita — não
é igual ao da Dynamic Island do iPhone nem em aparência nem em comportamento.
As barras saem grossas demais, altas demais e com movimento errático.

A pesquisa mostrou que a causa não é a fonte do sinal. O indicador do iPhone é
um analisador de espectro de verdade, com a mesma mecânica que o Knobler já
usa: captura do processo do player, janela de Hann, FFT, bandas de frequência.
A diferença está no desenho — quantidade, espessura, vão, alturas, cor — e no
tratamento do sinal.

Objetivo: o estado fechado com música ficar visualmente indistinguível da ilha
compacta do iPhone.

## Escopo

Dentro:

- As barras: quantidade, espessura, vão, raio, cor, alturas, ritmo, tocando
  versus pausado.
- A capa: tamanho, raio de canto, escurecimento ao pausar.
- A regra de visibilidade: hoje pausar esconde tudo; passa a manter visível.
- O tratamento do sinal: número de bandas e a curva que vira altura.
- O que a análise não cobre: a animação de reserva quando não há áudio.

Fora:

- O card aberto de música. Só o estado fechado.
- Os outros ocupantes da asa direita — anel de atividade, microfone, pontinho
  da nota. Continuam como estão.
- Os HUDs de volume e brilho, que usam a mesma asa em outro modo.
- A largura fixa da asa, mesmo sabendo que ela já corta conteúdo hoje.

## Medidas do iPhone

Todos os números abaixo saem de decompilação de binário da Apple; a proveniência
de cada um está no dossiê. O que não tem fonte está marcado como calibração.

**Indicador (acessório trailing): área de 22 × 22 pt.**

```
barras = 6
passo  = largura / 6   = 3,667
barra  = passo / 2     = 1,833      (o vão é igual à largura da barra)
raio   = barra / 2                  (cápsula perfeita)
centro da barra i, em x = barra + i × passo
crescimento a partir do centro vertical, não da base
altura = max(amplitude × altura_total, largura_da_barra)
largura no pico = largura_base + 0,66 × amplitude
```

O piso da altura ser a própria largura é o detalhe que separa a cópia boa da
ruim: amplitude zero vira um ponto redondo, nunca um traço fino nem o
desaparecimento da barra.

**Capa (acessório leading): 22 × 22 pt, raio de 5,5 pt com canto contínuo.**
O acessório do iPhone tem 26 pt de largura, sobra horizontal que não se aplica
aqui. Ao pausar, a capa vai para opacidade 0,5 em 0,2 s.

**Sem capa:** cinza `#646464`, com transição de 0,5 s.

## Decisões

**A captura de áudio fica.** Decisão revista depois da pesquisa: o iPhone
analisa o som real, então remover a análise afastaria do objetivo em vez de
aproximar. A permissão de gravação de áudio do sistema continua, e o
interruptor "visualizador ao vivo" que já existe nos Ajustes passa a escolher
entre ouvir o som e tocar a curva de reserva.

**Seis bandas no lugar de cinco.** O iPhone divide o espectro em seis. As
bordas de frequência exatas dele não foram extraídas: as seis bordas do Knobler
saem de uma redivisão logarítmica da faixa que já usa hoje, e são ponto de
calibração visual, não achado.

**Cor: recorte, não tinta.** As barras deixam de ser pintadas com a cor
dominante da capa e passam a ser a máscara por onde a capa aparece, depois de
desfoque e realce de saturação — é assim que o iPhone faz, e é o que dá matizes
diferentes entre barras vizinhas. Junto vem a proteção da Apple para capa
escura ou clara demais: uma camada clareadora quando a luminância cai abaixo de
um limiar, escurecedora quando passa de outro. Os parâmetros de desfoque,
saturação e limiares não têm fonte e são calibrados por comparação visual.

**Medidas absolutas.** As alturas do notch do Mac e da ilha do iPhone são
próximas o bastante para os mesmos pontos funcionarem. Nada de refazer as
medidas como fração da altura do notch: isso deixaria de bater ponto a ponto
com o iPhone em telas de altura diferente.

**Pausado permanece visível.** Segue o iPhone: capa e barras continuam no
notch, as barras caem para os seis pontinhos, a capa escurece, e a passagem é
uma transição com curva própria — o iPhone usa uma para tocando e outra para
pausar. Consequência aceita: o notch fica ocupado enquanto houver sessão de
música pausada em algum app.

**A espiada no hover sai.** Ela existia para revelar capa e barras escondidas
com a música pausada. Sem nada a revelar, o hover passa a abrir o card direto,
igual a com música tocando. Some o estágio intermediário e a espera que o
acompanhava.

**Motor: uma mola por leitura, todas as barras juntas.** Decisão revista depois
da pesquisa. Cada leitura nova do espectro reemite uma única animação de mola
sobre as seis barras — não há laço por barra nem defasagem programada, porque a
irregularidade vem do som. Isso também evita as três armadilhas conhecidas de
animação infinita em SwiftUI: atraso que muda de significado conforme a ordem
dos modificadores, animações que se empilham e fazem a CPU crescer com o tempo,
e animação infinita que não se cancela passando nada no lugar. Os números da
mola do iPhone não têm fonte e são calibrados por comparação visual.

**Sem áudio: a curva de reserva da Apple.** Quando a análise não está
disponível — permissão negada, visualizador ao vivo desligado, ou player sem
captura — as barras tocam a animação enlatada que a Apple usa no app Música,
extraída do asset original: ciclo de 2,66 s, doze quadros-chave uniformes,
interpolação cúbica, laço sem emenda. A tabela traz cinco sequências para seis
barras; a sexta repete uma delas defasada em meio ciclo, e isso é escolha
registrada, não achado. Substitui a senoide inventada de hoje. Os sessenta
valores estão transcritos no dossiê.

## Arquitetura

O visualizador continua sendo uma folha isolada da árvore de views — nada além
dele observa o estado de animação, e é isso que impede o notch inteiro de
redesenhar a cada quadro.

Três peças:

1. **Constantes e geometria, em arquivo próprio sem views.** Passo, largura,
   raio, posições, piso de altura, largura no pico, e a tabela da animação de
   reserva. Cada valor com a proveniência anotada ao lado: medida da Apple ou
   calibração. Precisa ficar fora de `NotchView.swift` por uma razão prática —
   os harnesses do projeto compilam só os arquivos listados, e a geometria
   dentro da view arrastaria a árvore SwiftUI inteira para dentro do check.

2. **A análise**, que passa de cinco para seis bandas. Mudança contida no
   arquivo que já existe.

3. **A view**, que monta as seis barras como máscara sobre a capa tratada e
   aplica a mola a cada leitura.

O contrato com o resto do app não muda: o visualizador continua recebendo o
objeto observável de níveis e a capa.

## Verificação

**Harness.** A geometria vira uma função pura com um `tools/*check*.swift` no
molde de `tools/colorpickercheck.swift`, com entrada em `tools/check.sh`. Ele
falha se a largura total, o número de barras, o piso de altura ou as posições
saírem do que a pesquisa fixou. A tabela da animação de reserva também entra:
primeiro valor igual ao último em cada sequência, senão o laço tem emenda.

**Snapshots.** `closed-music` e `closed-music-external` continuam sendo
inspeção visual, não detector de regressão — são dois dos quatro PNGs que já
mudam de hash a cada rodada. Os dois cenários que existem hoje para provar a
regra antiga, `closed-paused-hidden` e `closed-paused-peek`, viram um só: música
pausada com capa e barras visíveis. Esse é determinístico, porque as barras
ficam paradas.

**Comparação final.** A validação de "idêntico" é o usuário olhando o notch com
música tocando ao lado de um iPhone. Nenhum check automatizado substitui isso.

## Riscos

**A calibração é metade do trabalho.** Sem fonte: os números da mola, o
desfoque e a saturação da capa, os limiares de luminância, as bordas das seis
bandas. Todos vão sair de rodadas de comparação visual, e o plano precisa
prever esse laço em vez de tratá-los como constantes conhecidas.

**A barra que muda de largura pode custar CPU.** Hoje o desenho anima por
transformação justamente para não refazer o layout a cada quadro — foi o maior
custo de processador do app com música tocando. Com a barra engordando no pico,
a largura passa a variar, e a transformação sozinha não basta: ela deformaria a
ponta arredondada. Se a medição mostrar custo alto, o recuo é descer para a
camada de desenho do sistema, que é o que a Apple faz e o que os outros apps de
notch para Mac fizeram.

**A frequência de atualização é um ajuste em aberto.** O Knobler publica vinte
leituras por segundo; o iPhone varia entre cinco e quarenta e oito conforme o
espectro muda. Subir a frequência deixa o movimento mais fiel e custa mais
processador, com uma janela por monitor. Fica para a fase de calibração.

## Registrado, fora do escopo

A asa direita já estoura hoje: pontinho da nota, microfone e barras se empilham
e chegam a somar 69 pt num espaço de 44, e o excedente é cortado em silêncio
por uma máscara. Encolher as barras devolve cerca de 5 pt e não resolve. A
largura do notch fechado é um valor fixo que não consulta o conteúdo. Fica
anotado para uma decisão futura.

## Decisões do grill

- **A1** — desfeita a remoção da captura de áudio. Motivo: o indicador da
  Dynamic Island é um analisador de espectro real, com a mesma mecânica que o
  app já implementa; remover afastaria do objetivo.
- **A2, A3** — adotadas as medidas do iPhone tal e qual, seis barras em 22 × 22.
  Motivo: o alvo declarado é idêntico, e as barras mais finas resolvem a queixa
  original.
- **A4** — adotado o engordamento de 0,66 pt no pico. Motivo: barato, e é parte
  do que dá a textura do movimento.
- **A5** — adotado o recorte sobre a capa no lugar da tinta sólida. Motivo: é o
  que produz matizes diferentes entre barras vizinhas, o ganho visual mais
  perceptível da lista.
- **A6** — adotado o pausado com pontinhos e capa escurecida. Motivo: confirma e
  detalha a decisão que a spec já tinha.
- **A7** — descartada a animação em laço por barra da spec original, trocada por
  mola por leitura. Motivo: o laço por barra não é o que a Apple faz e é
  justamente o padrão que mais dá problema em SwiftUI.
- **A8** — adotada a curva de reserva da Apple no lugar da senoide. Motivo:
  movimento autêntico por sessenta números.
- **A9** — capa reduzida a 22 × 22 com raio 5,5 contínuo. Motivo: coerência com
  a decisão de medidas absolutas.
- **A10, A11** — incorporados como restrição de implementação e como risco de
  CPU, não como decisão de produto.
- **A12** — mantido como referência de calibração, não copiado. Motivo: aquele
  app escolheu escalar para o Mac, e aqui a decisão foi medida absoluta.
- **A13** — registrado que a captura é API pública a partir do próprio
  deployment target, o que remove o argumento de fragilidade.
- **A14, A15** — registrados e deixados fora do escopo por decisão explícita.
- **A16** — o interruptor "visualizador ao vivo" ganha significado novo: escolhe
  entre ouvir o som e tocar a curva de reserva, em vez de ligar e desligar.
- **A17** — sem efeito. A lista de remoções deixou de existir com A1.
- **A18** — os dois cenários de snapshot da regra antiga viram um.
- **A19** — removida a espiada no hover. Motivo: sem asas escondidas, ela não
  tem o que revelar.
- **A20** — a geometria nasce em arquivo próprio, sem views, para o check ser
  de uma linha.
