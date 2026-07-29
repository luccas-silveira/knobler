# Nota rápida

![Card do notch aberto com o campo da nota vazio e o placeholder "Rascunho — some ao desligar"](images/nota-placeholder.png)

<!-- Esta imagem é MANUAL: o TextEditor é um ScrollView e não renderiza no
     harness offscreen (ver CLAUDE.md). Pra refazer: rodar o build novo, ligar a
     nota pelo menu ◐, achar o windowID do notch (layer 27 em
     CGWindowListCopyWindowInfo), `screencapture -o -l<id>` e recortar o card. -->

## O que faz

Um bloco de texto efêmero que mora no card expandido do notch — pra anotar
algo rápido (um número de pedido, um trecho pra colar depois) sem abrir
Notas ou um editor de verdade. Sem formatação, sem persistência: é rascunho,
não é lugar pra guardar coisa importante.

## Como usar

1. Menu da barra (**◐**) → **✎ Nota rápida** — o item ganha um check quando
   está ativo.
2. Ligar abre o notch na hora, já com o campo de texto focado, pronto pra
   digitar. Com mais de um monitor, a nota mora na tela onde o mouse estava
   quando você ligou — só ela abre, e desligar recolhe só ela.
3. Enquanto o interruptor estiver ligado, o texto volta toda vez que o notch
   abrir de novo (por hover ou pelo gesto normal) — a nota fica ali até você
   desligar.

Com o card **fechado** e texto guardado, um pontinho branco de 4 pt aparece na
asa direita do notch (do mesmo lado do indicador de microfone). É o lembrete de
que tem rascunho ali — sem ele dá pra esquecer e desligar achando que o campo
estava vazio.

![Notch fechado com o pontinho da nota na asa direita](images/closed-note.png)

## Segurar o card aberto pra digitar

O card normalmente fecha quando o mouse sai de cima do notch. Com o foco no
campo de texto, isso muda: **digitar segura o card aberto**, mesmo com o
cursor do mouse em outro canto da tela. **Esc** solta o foco do campo — depois
disso, tirar o mouse fecha o card normalmente, e o texto volta na próxima vez
que você abrir (hover ou gesto).

Enquanto o campo está focado, **notificação e HUD não tomam o card**. A
notificação espera na fila e aparece assim que você solta o campo; o HUD de
volume/brilho simplesmente não aparece durante a digitação. Ditado e mensagem
recebida ainda passam na frente — os dois têm campo de teclado próprio.

Digitar na nota **não** rouba o foco do app que está na frente: o notch é um
painel `nonactivating`, então o teclado continua indo pro app ativo assim que
você clica fora do campo — só enquanto o campo está focado é que as teclas vão
pra nota.

## Desligar copia e apaga

Não existe timer nem prazo configurável. Desligar o interruptor no menu
**apaga o texto** e recolhe o card — é a única forma de limpar a nota.

Antes de apagar, o texto **vai pro clipboard**: se você desligou sem querer,
é só colar (⌘V) de volta. Vale pros três jeitos de perder a nota — o
interruptor, desconectar o monitor dono, e sair do Knobler. Nota vazia (ou só
com espaço e enter) não mexe no clipboard.

⚠️ O que você tinha copiado antes é sobrescrito. Perder a nota é pior que
perder o clipboard, mas vale saber.

## Limitações

- **Não sobrevive a reiniciar o Knobler.** A nota mora só em memória, junto
  com o resto do estado efêmero do notch — mas o texto vai pro clipboard ao
  sair, então dá pra colar de volta depois de abrir o app.
- **Toma o card inteiro.** Com a nota ligada naquela tela, a faixa de seções
  some do rodapé e o swipe horizontal não troca de seção — o card é da nota, e
  nada oferece um caminho pra fora do campo de texto. Com o notch fechado o
  swipe horizontal continua pulando faixa, normal.
- **Texto simples, sem formatação.** Negrito/itálico exigiriam
  `NSAttributedString` e uma barra de formatação — custo alto pra uma nota que
  costuma viver minutos.

## Permissões

Nenhuma permissão especial.
