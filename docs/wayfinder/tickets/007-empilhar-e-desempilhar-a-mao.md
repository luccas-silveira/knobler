# 007 — Empilhar e desempilhar à mão

Map: [Shelf de arquivos — empilhamento, ordem e saída](../map-shelf-de-arquivos.md)
Type: `wayfinder:task`
Status: aberto
Assignee: —
Blocked by: 004

## Pergunta

Dentro da shelf, arrastar um item **sobre outro** junta os dois numa pilha. E o
caminho de volta: desempilhar devolve os arquivos a itens soltos.

A parte difícil é que a miniatura já é fonte de arraste, e por um caminho
incomum: `ShelfDragMonitor` é um monitor global de mouse que roda **antes** do
hit-testing do SwiftUI, porque NSViews embutidas no `NSHostingView` do notch
não recebem evento de mouse. Um arraste que começa numa miniatura e termina em
outra, dentro do mesmo painel, precisa de um alvo de drop em cada miniatura —
e o monitor precisa saber diferenciar "saiu do painel" de "parou em cima de um
vizinho", senão o 005 remove o item que na verdade só mudou de lugar.

**Isso deixou de ser suspeita e virou medida.** O 001 mediu um alvo de soltura
dentro do próprio app: devolve `copy`, igual ao Finder, e o contexto de
`sourceOperationMaskFor` não separa os dois
([medicao-001](../medicao-001-o-que-os-destinos-devolvem.md)). O sinal que
distingue é responsabilidade do 005, que já carrega isso escrito.

O que entra:

1. Soltar item sobre item cria pilha; soltar item sobre pilha entra na pilha.
2. Desempilhar pelo menu de contexto da pilha, devolvendo os arquivos à linha.
3. A interação com o 005: arraste que termina dentro da própria shelf **não**
   conta como saída.

Reordenar itens arrastando dentro da linha não está pedido e fica de fora.
