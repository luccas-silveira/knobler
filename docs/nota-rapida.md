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

## Tirar o mouse enquanto digita

O card fecha quando o mouse sai de cima do notch — com o foco no campo de
texto também, só que **depois de 3 segundos** em vez dos 0,3 s de sempre. É
tempo de voltar com o ponteiro sem perder o campo de vista. **Esc** solta o
foco e devolve o fechamento rápido.

Fechar não apaga nada: o texto volta na próxima vez que você abrir (hover ou
gesto).

## Sair da nota sem perdê-la

O swipe horizontal de dois dedos sobre o notch anda uma seção, e isso vale
**também** com a nota em foco: você sai pra Música, Prateleira, o que estiver
na faixa, e volta pela faixa de ícones ou pelo swipe de volta — o texto
continua onde estava. Só o interruptor do menu encerra a nota.

Se você **fixar** a seção Nota em Ajustes › Notch (o alfinete), ela fica
sempre no card, mesmo com o interruptor desligado. Entrar na seção liga a
nota na tela em que você está; se ela já estava ligada em outro monitor, o
dono migra pra cá com o texto.

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
