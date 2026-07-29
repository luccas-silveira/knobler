# Nota rápida

<!-- TODO screenshot: card expandido com o campo de texto da nota rápida, cursor piscando -->

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

## Segurar o card aberto pra digitar

O card normalmente fecha quando o mouse sai de cima do notch. Com o foco no
campo de texto, isso muda: **digitar segura o card aberto**, mesmo com o
cursor do mouse em outro canto da tela. **Esc** solta o foco do campo — depois
disso, tirar o mouse fecha o card normalmente, e o texto volta na próxima vez
que você abrir (hover ou gesto).

Digitar na nota **não** rouba o foco do app que está na frente: o notch é um
painel `nonactivating`, então o teclado continua indo pro app ativo assim que
você clica fora do campo — só enquanto o campo está focado é que as teclas vão
pra nota.

## Desligar apaga

Não existe timer nem prazo configurável. Desligar o interruptor no menu
**apaga o texto** e recolhe o card — é a única forma de limpar a nota. Se você quer manter o
que escreveu, copie antes de desligar.

## Limitações

- **Não sobrevive a reiniciar o Knobler.** A nota mora só em memória, junto
  com o resto do estado efêmero do notch.
- **Não convive com o histórico.** Com a nota ligada naquela tela, o puxão
  longo pra baixo não abre a cortina de histórico — o card é da nota.
- **Texto simples, sem formatação.** Negrito/itálico exigiriam
  `NSAttributedString` e uma barra de formatação — custo alto pra uma nota que
  costuma viver minutos.

## Permissões

Nenhuma permissão especial.
