---
name: snapshot-ui
description: Gerar, validar ou recapturar imagens da UI do Knobler — `tools/snapshot.sh`, os PNGs de `Snapshots/`, as imagens de `docs/images/` (painéis de Ajustes, novidades, prateleira) e o catálogo de views que não renderizam offscreen. Use ao rodar o harness de snapshot, ao adicionar cenário novo a ele, ao tirar screenshot da janela real de Ajustes, ao atualizar imagem de documentação, ou quando um PNG sai com o ícone de "proibido" ou com área preta no lugar do conteúdo.
---

# Snapshots e imagens da UI

`tools/snapshot.sh` compila a `NotchView` isolada com `swiftc` e renderiza cada
estado em `Snapshots/*.png` — é o jeito de "ver" a UI sem abrir o app.

```bash
./tools/snapshot.sh          # regenera Snapshots/*.png; leia os PNGs pra validar
```

`Snapshots/` é gitignored e serve só de QA visual local. As imagens usadas pelos
docs de usuário ficam em `docs/images/`.

## PNGs não determinísticos

⚠️ **Quatro PNGs não são determinísticos** e mudam de hash a cada rodada mesmo
sem mudança nenhuma de código: `closed-music`, `closed-music-external`,
`foco-atividade-indeterminada` e `update-installing` (visualizador animado,
barra de progresso). Neles o snapshot é inspeção visual, não detector de
regressão — não gaste tempo investigando o diff. O harness gera 57 PNGs no
total; os outros 53 são byte-idênticos entre rodadas.

## O que não renderiza offscreen

⚠️ **Qualquer view que dependa de um `NSView` real (janela/WindowServer de
verdade) não renderiza via `ImageRenderer` offscreen** — vira o ícone de
"proibido" no lugar do conteúdo. Casos confirmados até agora:

- `NavigationSplitView`/`HSplitView` (repro isolado).
- `TextField` — o rodapé do `AskCardView`, por isso `ask-simple.png` e
  `ask-multiselect.png` cortam antes da barra do campo de texto.
- `WKWebView` — a seção Link (o preview de site não tem PNG no harness) e
  `NovidadesWindow`, a janela de novidades: mesma vala, por isso
  `docs/images/novidades.png` também é manual.
- `ShelfThumbnailDragView` (um `NSView` com `NSImageView`, alimentado por
  `QLThumbnailGenerator`) — por isso `docs/images/expanded-shelf.png` é
  capturada no app rodando de verdade: o `foco-shelf.png` do harness sai com o
  ícone de "proibido" no lugar das miniaturas. O culpado é o `NSView`, não o
  ícone: `Image(nsImage: NSWorkspace.shared.icon(forFile:))` em SwiftUI
  renderiza normalmente (card de notificação e `historico-linhas.png`).
- `ScrollView` (`NSScrollView` por baixo) — sintoma diferente dos outros: não
  vira o ícone de "proibido", o conteúdo simplesmente não aparece (área inteira
  preta), mesmo com `LazyVStack` trocado por `VStack` simples. Confirmado na
  `HistoryListView` (seção de histórico) e na **thread** da `MessagesView` (a
  conversa aberta) — por isso a seção de histórico não entra populada no
  harness, só vazia (`foco-historico-vazio.png`, que não usa `ScrollView`), e
  não há cenário de conversa aberta. A **lista de peers** da `MessagesView` não
  usa `ScrollView` e renderiza normalmente: `messages-online.png` é gerado pelo
  harness e vale como detector de regressão.
- A seção `espelho` fica de fora: precisa de câmera real.

Ao adicionar cenário novo ao harness, desconfie de qualquer subview que envolva
um desses.

Por isso `settings-*.png` (8 painéis de Ajustes) e `mapping-editor.png` **não**
são gerados por `tools/snapshot.sh` — são mantidos à mão — junto com
`nota-placeholder.png` (campo da nota rápida: é um `TextEditor`, logo um
`ScrollView`; a receita de captura está num comentário em `docs/nota-rapida.md`).

## Capturar os painéis de Ajustes

Rode `Knobler.app/Contents/MacOS/Knobler --ajustes=<painel>` (painéis: `geral
notch desenho ditado pomodoro lembretes descanso webhooks mensagens
permissoes`), tire o screenshot da janela real e salve em `docs/images/`.

`screencapture -l<windowID>` captura a sombra própria do macOS (PNG com alpha) —
corte pra `802x554+55+37` antes de salvar (bordas reais da janela, sem halo).

⚠️ `-l` **reescala** a janela: num sheet o PNG sai com a janela-mãe em volta, e
coordenada de clique tirada dessa imagem erra o alvo. Pra automatizar clique +
captura use `screencapture -R x,y,w,h` com os bounds de
`CGWindowListCopyWindowInfo` e `sips -z` pra 1x. Clique sintético: SwiftUI só
responde com `CGWarpMouseCursorPosition` **mais** eventos `.mouseMoved` em
passos pequenos antes do down/up.

Numa tela Retina o PNG sai em @2x: o corte equivalente é
`sips -c 1108 1604 --cropOffset 74 110` seguido de `sips -z 554 802`.

## Capturar a janela de novidades

`docs/images/novidades.png` segue a mesma vala (`WKWebView` real): rode
`Knobler --novidades` — a flag mostra **tudo** e não grava a versão vista, então
tirar print não queima o estado da máquina. Rode de `/Applications` ou de
`~/Applications`: de `/tmp` o `installIssue` manda direto pro painel Permissões
e a página nem abre. Sai @2x mesmo (`screencapture -o -l<id>`, sem sombra e sem
halo, não precisa recortar).

## Recapturar `expanded-shelf.png`

⚠️ **Mexe na máquina do usuário — peça antes.** É a única imagem dos docs que
exige o card aberto com a prateleira em foco, e a receita passa por fechar o
Knobler que estiver rodando (senão são dois notches na mesma tela), escrever
`shelfItems` e `notchSectionOrder` via `defaults`, subir a build Debug, e então
**mover o cursor e clicar** — o hover só acorda com `CGWarpMouseCursorPosition`
em passos pequenos, e o clique no ícone da faixa encolhe o card, então o
ponteiro tem que subir logo depois ou o card recolhe antes do `screencapture`.

O `shelfItems` é um **array de arrays** de caminho: cada entrada da prateleira
é um grupo, e um grupo com dois ou mais arquivos é uma pilha.

```bash
defaults write com.zoi.knobler shelfItems \
  '(("/tmp/Relatório.pdf"),("/tmp/foto.png"),("/tmp/a.png","/tmp/b.png"))'
```

A terceira entrada acima é uma pilha, e escrever aqui é hoje o único jeito de
materializar uma. Um array plano de caminhos ainda funciona — o app o migra —
mas ele entra **invertido**, porque o formato plano é anterior à regra de "o
mais novo na esquerda".

Confira o resultado por `GET /status` (`notches[].focus == "shelf"`), não pelo
palpite. Restaure `defaults` e relance o app do usuário no fim. Um card
transitório (Ask, notificação) pode tomar o notch no meio e estragar a captura —
capture algumas vezes e escolha.
