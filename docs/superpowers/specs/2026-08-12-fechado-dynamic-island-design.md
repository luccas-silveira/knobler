# Notch fechado com música idêntico à Dynamic Island

**Data:** 2026-08-12
**Estado:** aprovado na fase de spec, pendente de pesquisa e grill

## Problema

O estado fechado com música — capa à esquerda, barras de áudio à direita — não
é igual ao da Dynamic Island do iPhone nem em aparência nem em comportamento.
As barras saem grossas demais, altas demais e com movimento errático, porque
são dirigidas pelo áudio real do player (captura de processo via CoreAudio +
FFT em cinco bandas). O iPhone não faz isso: o indicador de reprodução dele é
uma animação, não um analisador de espectro.

Objetivo: o estado fechado com música ficar visualmente indistinguível da ilha
compacta do iPhone.

## Escopo

Dentro:

- As barras: quantidade, espessura, vão, raio da ponta, cor, altura mínima e
  máxima, ritmo do movimento, tocando versus pausado.
- A capa: tamanho, raio de canto, transição na troca de faixa.
- A asa: largura da área, espaçamentos, como capa e barras entram e saem.
- A regra de visibilidade: hoje pausar esconde tudo; passa a manter visível.
- A remoção da captura de áudio do sistema e de tudo que ela arrasta.

Fora:

- O card aberto de música (`.music`). Só o estado fechado.
- Os outros ocupantes da asa direita — anel de atividade, ícone de microfone,
  pontinho da nota. Eles convivem com as barras hoje e continuam como estão.
- Os HUDs de volume e brilho, que usam a mesma asa em outro modo.

## Decisões tomadas

**Fonte de verdade: pesquisa.** Nenhuma medida do iPhone é medida diretamente.
Os números saem do dossiê da fase 2 — documentação da Apple, implementações
públicas que replicaram o indicador, análise de material em vídeo. Todo número
sem fonte confiável vira decisão explícita registrada no grill, não um palpite
silencioso no código.

**Idêntico ganha da reatividade.** Se a Apple anima sem ouvir o áudio, o
Knobler também anima sem ouvir. A reação ao som real era um ganho sobre o
iPhone, e é abandonada de propósito.

**A captura de áudio sai inteira.** `SystemAudioLevels` não alimenta mais nada
no app, então some junto com a permissão que ela pedia.

**Medidas absolutas.** As alturas do notch do Mac e da ilha do iPhone são
próximas o bastante para os mesmos pontos funcionarem. Nada de refazer as
medidas como fração da altura do notch: isso deixaria de bater ponto a ponto
com o iPhone em telas de altura diferente.

**Pausado permanece visível.** Segue o iPhone: capa e barras continuam no notch
com a música pausada, barras paradas, e a passagem entre tocando e pausado é
uma transição animada, não um corte. Consequência aceita: o notch fica ocupado
enquanto houver sessão de música pausada em algum app.

**Motor: animação declarativa por barra.** Cada barra tem um laço próprio de
subir e descer, com duração e defasagem próprias, entregue ao sistema de
animação. Substitui o recálculo de altura 30 vezes por segundo que existe hoje.
Custo de CPU praticamente desaparece e o pausar vira interpolação de graça.
Descer para a camada de desenho do AppKit fica como saída de emergência, só se
a animação declarativa não alcançar a fidelidade — decisão a tomar com a
comparação na mão, não antes.

## Arquitetura

O visualizador continua sendo uma folha isolada da árvore de views — nada além
dele observa o estado de animação, e é isso que impede o notch inteiro de
redesenhar a cada quadro. A dependência de dados muda de forma: hoje ele recebe
um objeto observável de níveis de áudio; passa a receber apenas se está tocando
e a cor da tinta.

Três peças:

1. **Constantes da ilha.** Um único lugar guarda todas as medidas levantadas na
   pesquisa — quantidade de barras, espessura, vão, alturas, durações,
   defasagens, raio da capa. Nomeadas pelo que significam, com a fonte anotada
   ao lado de cada uma.

2. **Geometria pura.** A tradução de "n barras com esta espessura e este vão" em
   largura total e posições é uma função sem UI dentro. É o que o harness testa.

3. **A view.** Monta as barras a partir das constantes e liga o laço de animação
   quando está tocando.

O contrato com o resto do app encolhe: quem monta o notch fechado deixa de
carregar o objeto de níveis de áudio de ponta a ponta (composição do app,
view do notch, harness de snapshot).

## Remoções

- `Knobler/AudioLevelTap.swift` inteiro.
- O caso `audioSistema` de `Knobler/Permissions.swift` — o rótulo, o texto de
  ajuda, a âncora do painel de Privacidade do sistema e as três listas que o
  citam.
- `NSAudioCaptureUsageDescription` em `project.yml`.
- A entrada do arquivo em `tools/snapshot.sh`.
- As menções em `docs/now-playing.md`, `docs/settings.md` e
  `docs/troubleshooting.md`.
- `docs/images/settings-permissoes.png` precisa ser recapturado: é imagem
  mantida à mão e vai passar a mostrar uma linha a menos.

## Verificação

**Harness.** A geometria e o perfil de alturas viram uma função pura com um
`tools/*check*.swift` no padrão da casa, com entrada em `tools/check.sh`. Ele
falha se a largura total, o número de barras ou os limites de altura saírem do
que a pesquisa fixou.

**Snapshots.** `closed-music.png` e `closed-music-external.png` continuam sendo
inspeção visual, não detector de regressão: são dois dos quatro PNGs que já
mudam de hash a cada rodada por causa da animação. Cenário novo a acrescentar:
o fechado com música **pausada**, que hoje não existe no harness porque pausar
escondia tudo.

**Comparação final.** A validação de "idêntico" é o usuário olhando o notch com
música tocando ao lado de um iPhone. Nenhum check automatizado substitui isso.

## Riscos

A pesquisa pode não achar números confiáveis para o ritmo do movimento —
duração e defasagem do laço são o mais difícil de extrair de material público.
Nesse caso o grill escolhe um valor, registra que foi escolha e não achado, e o
ajuste fino vira uma rodada de comparação visual com o usuário.

O visualizador é o único consumidor da captura de áudio hoje, mas a permissão
já concedida por usuários existentes permanece registrada no sistema deles. A
remoção não a revoga — só para de pedir e de mostrar.
