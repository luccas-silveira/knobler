# 007 — Empilhar e desempilhar à mão

Map: [Shelf de arquivos — empilhamento, ordem e saída](../map-shelf-de-arquivos.md)
Type: `wayfinder:task`
Status: fechado
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

## Resposta

O modelo entrou em `ShelfOrdem`: `empilhar(_:em:entradas:)` junta arquivos na
entrada alvo **sem tirá-la do lugar** — diferente do `inserir`, que sempre abre
entrada nova na frente, porque aqui é o usuário que aponta onde a pilha se
forma. O dedupe entre entradas do 004 continua valendo, então a entrada de
origem perde os arquivos e some sozinha; soltar a entrada sobre ela mesma não
muda nada. `desempilhar(_:em:capacidade:)` devolve os arquivos à linha na
posição da pilha, e uma pilha de 20 numa prateleira de 8 perde o excesso pelo
fim, que é a regra do 003. Nove asserções novas no `shelfordemcheck`.

**O ponto que o ticket dava como difícil se resolveu tirando o SwiftUI do
caminho.** O empilhamento à mão é decidido em `draggingSession(_:endedAt:_:)`,
no fim da sessão de arraste, e não por um alvo de drop na miniatura vizinha: um
arraste AppKit iniciado dentro do `NSHostingView` não tem garantia de alcançar
esse alvo, nem de que ele rode antes do fim da sessão — e se a ordem invertesse,
a regra do 005 apagaria a pilha recém-formada. Do jeito que ficou não existe
ordem pra inverter: o mesmo método que decide a saída decide o empilhamento,
com um `if` antes do outro.

O alvo é `ShelfDragMonitor.view(at:)`, que já existia pra achar a miniatura sob
o cursor no começo do arraste. **Aqui a geometria é legítima**, ao contrário do
que o 005 rejeitou: o retângulo consultado é a miniatura de 30x30 sob o cursor,
não o painel de 700pt que cobre da barra de menu ao Dock. Soltar sobre uma
vizinha também conta como `dentroDoNotch`, então a saída não dispara.

Desempilhar é um item no menu de contexto, que só aparece quando a entrada é
pilha.

Não verificado: **nada disso renderiza offscreen.** Que a pilha se forme ao
soltar uma miniatura sobre a outra na tela é do 009, junto das folhas e do badge
que o 006 deixou na mesma situação.
