# 008 — A pilha expandida

Map: [Shelf de arquivos — empilhamento, ordem e saída](../map-shelf-de-arquivos.md)
Type: `wayfinder:prototype`
Status: fechado
Assignee: claude
Blocked by: 004

## Pergunta

Sem um jeito de abrir a pilha, um drop de vinte fotos vira um bloco que só
existe inteiro: ou leva as vinte, ou nada. Expandir é o que devolve o controle
sobre um arquivo só.

Decisão já travada com o usuário: a pilha aberta **toma o card inteiro**, numa
grade de várias linhas, em vez de tentar caber na linha única da shelf. O
motivo é a mesma parede que criou a capacidade 8 — a linha não rola, e
`ScrollView` é uma vala conhecida deste projeto. Investigar o `ScrollView` foi
posto fora de escopo pelo usuário.

O que este protótipo tem que mostrar, barato, pra reagir em cima:

1. Como se abre e como se fecha a pilha.
2. A grade: quantos cabem, o que acontece com nome de arquivo comprido.
3. Dentro da pilha aberta: arrastar um arquivo pra fora, remover um no ✕.
4. Como a shelf volta ao normal — a pilha aberta é um estado da seção shelf, e
   o card já tem outras seções disputando o espaço.

Consultar a skill `impeccable`. Consultar `snapshot-ui` antes de qualquer
captura: a imagem da prateleira nos docs é tirada no app rodando e recapturá-la
mexe na máquina do usuário — **peça antes**.

## Resposta

Clicar numa pilha abre ela em grade, no card inteiro. Cinco por linha, duas
linhas, miniatura de 48pt, dez por página — com "Mais" na décima célula quando
não cabe tudo, que é o mecanismo do `AnnotationDeckView`. Sem `ScrollView`.

**A conta de largura não é 430.** O card tem 430, mas a `NotchView` aplica
`.frame(width: larguraDoCard - 44)` ao conteúdo: a largura útil é **386**. Com
célula de 78 a grade estouraria; com 66 e espaçamento 10 dá 370, com 16 de
folga. A grade é montada em `HStack`s fixos e não em `LazyVGrid`, pelo motivo
que o `AnnotationDeckView` já documenta: o Lazy mede maior do que desenha e
empurra a primeira fileira pra fora do card.

O nome do arquivo fica em **duas linhas truncadas no meio**. Uma linha só, em
66pt, engolia o nome inteiro de uma captura de tela e sobrava `Capt…01.png` —
todas as células iguais. Em duas linhas sobra `Captura de tela 2…1.png`, que
distingue. Truncar no meio e não no fim porque numa pilha os nomes compartilham
o prefixo, e é o fim que diferencia.

### O estado, e por que ele não é `@State`

`ShelfStore.pilhaAberta`, irmão do `preview` — volátil, fora do `shelfItems`: o
notch não reabre amanhã na pilha que alguém olhou hoje. Não é `@State` da view
porque `NotchView.currentSize` precisa ler o estado pra calcular a altura, e um
`@State` seria invisível pra ele: o card sairia com moldura de 76pt em cima de
184pt de conteúdo, que é o descompasso contra o qual o arquivo avisa.

A altura entra como terceiro caso de `alturaDaSecao`, e **a ordem não é livre**:
os dois estados podem estar ligados ao mesmo tempo (converter a partir de dentro
da pilha aberta), e o `ShelfRowView.body` testa `preview` primeiro. A altura
testa `preview` primeiro também.

### A reconciliação, que é o coração do ticket

`ShelfEntry.id` vem do conteúdo, então tirar um arquivo **troca a identidade da
entrada** — guardar o id não ancora nada. `ShelfOrdem.pilhaAberta(_:em:)` ancora
pela interseção: a entrada que ainda contém algum dos arquivos abertos é a mesma
pilha. Por `capa` não daria — arrastar a capa pra fora fecharia uma pilha de
cinco que continua existindo.

Ela mora no `didSet` de `entradas` e não espalhada por mutador, porque a pilha
aberta some por caminhos que não são ação dela: `remover`, `clear`, a saída ao
arrastar, e até um `add` (o arquivo re-arrastado do Finder sai da pilha pelo
dedupe do 004). Todos passam por ali.

### O clique

Vem do `upMonitor` que o `ShelfDragMonitor` já tinha: soltou sem ter passado do
limiar de 3pt, na mesma miniatura em que apertou, na mesma janela. Não é
`.onTapGesture` pelo mesmo motivo que o arraste não é — o hit-testing do SwiftUI
blinda as NSViews embutidas no `NSHostingView`, e o monitor roda antes dele.
Nenhum código de hit-testing novo entrou.

Uma linha que não é opcional: `dragging` passou a ser zerado também no fim da
sessão de arraste. O `beginDraggingSession` assume o fluxo de eventos e aquele
`mouseUp` pode nunca chegar ao monitor — sem isso, `dragging` fica ligado e
engole o **próximo** clique.

### Gate e prova

Vinte asserções novas no `shelfordemcheck`, todas sobre regra pura: tirar do
meio preserva a posição; pilha que sobra com um deixa de ser pilha; entrada que
esvazia some; **tirar a capa não fecha a pilha**; a composição "abriu com 3,
tirou 1, segue aberta; tirou mais um, fecha"; e a paginação de 20 em 9+9+2, que
varre a pilha inteira sem repetir nem pular.

Dois cenários no harness: `foco-shelf-pilha` (7, uma página) e
`foco-shelf-pilha-cheia` (20, com o "Mais"). Os PNGs mostram a grade dentro da
moldura, o cabeçalho, o ✕ de cada célula, a truncagem em duas linhas e a faixa
de seções ainda visível. **As miniaturas saem com o ícone de "proibido"** — o
QuickLook não renderiza offscreen, e isso é conhecido.

Não verificado: o clique abrindo a pilha, a miniatura de verdade e o arraste de
um arquivo de dentro da pilha pra fora. Tudo isso é do 009, na tela.

### Achado colateral, pro 009

Na conta da linha fechada — item de até 58pt de nome, espaçamento 14 — oito
entradas pedem 562pt numa largura útil de 386. **A capacidade 8 não cabe na
linha**, e o botão "Limpar" ainda disputa o mesmo espaço. Nenhum snapshot mostra
isso porque o cenário `foco-shelf` tem três itens. Não é deste ticket.
