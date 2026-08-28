# 007 — Empilhar e desempilhar à mão

Map: [Shelf de arquivos — empilhamento, ordem e saída](../map-shelf-de-arquivos.md)
Type: `wayfinder:task`
Status: aberto
Assignee: claude
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

## Estado

**Itens 2 e 3 fechados; o item 1 está escrito mas não provado.**

O modelo entrou em `ShelfOrdem`: `empilhar(_:em:entradas:)` junta arquivos na
entrada alvo **sem tirá-la do lugar** — diferente do `inserir`, que sempre cria
entrada nova na frente, porque aqui o usuário apontou onde a pilha se forma. O
dedupe entre entradas do 004 continua valendo, e soltar a entrada sobre ela
mesma não muda nada. `desempilhar(_:em:capacidade:)` devolve os arquivos à linha
na posição da pilha; uma pilha de 20 numa prateleira de 8 perde o excesso pelo
fim, que é a regra do 003. Nove asserções novas no `shelfordemcheck`.

Na UI: "Desempilhar" no menu de contexto da pilha, e um `.onDrop` por miniatura.

O alvo da miniatura cobre o do painel, então ele recebe **também** o que vem de
fora. A origem é o que separa os dois casos: arquivo que já está na prateleira é
empilhamento, qualquer outro é entrada nova — sem isso, um arquivo do Finder que
mira mal viraria pilha em vez de entrada, contradizendo o 006. Link e texto
reusam o `carregar` do delegate do painel, e a triagem é por identificador
exato, não por conformidade, pelo mesmo motivo do painel: um link do Chrome
conforma a `public.file-url` e sumiria calado no caminho de arquivo.

**O que falta provar, e é o item 1 inteiro:** um arraste que começa numa
miniatura é uma sessão `beginDraggingSession` do AppKit dentro do
`NSHostingView`. Não está provado que ela chega a um `.onDrop` do SwiftUI numa
miniatura irmã, nem que esse `.onDrop` roda **antes** de
`draggingSession(_:endedAt:)`. Se a ordem inverter, `ShelfArrasteInterno.consumir()`
devolve falso, a regra do 005 dispara e a pilha recém-formada some da prateleira
— os arquivos originais ficam intactos, mas a entrada não. A marca é ligada nos
dois lugares (painel e miniatura), o que é idempotente, mas só ajuda se o alvo
interno de fato rodar.

Nada disso renderiza offscreen. **A pergunta pro 009, na tela: o alvo interno
dispara, e antes do fim da sessão de arraste?** O caminho de medida existe — o
build Debug e a `SondaDoArraste` da medição 001.
