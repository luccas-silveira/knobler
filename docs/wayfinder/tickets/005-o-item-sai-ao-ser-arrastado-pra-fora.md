# 005 — O item sai da shelf ao ser arrastado pra fora

Map: [Shelf de arquivos — empilhamento, ordem e saída](../map-shelf-de-arquivos.md)
Type: `wayfinder:task`
Status: aberto
Assignee: —
Blocked by: 001, 002

## Pergunta

Arrastar um item da shelf pra fora e o destino aceitar: o item some da
prateleira. O arquivo original **não é tocado** — a shelf só esquece o caminho.

Implementar `draggingSession(_:endedAt:operation:)` em `DragThumbView` e
remover do store quando a operação de volta disser que houve aceite, conforme a
tabela medida no 001. O `sourceOperationMaskFor` continua `.copy` — anunciar
`.move` faria o Finder mover o arquivo de verdade, e está fora de escopo.

Dois casos precisam de resposta explícita, e a medição do 001 é quem informa:

- Soltar no vazio, sem destino: o item **fica**.
- Destino que aceita mas devolve `.none`: o item fica, e isso é o custo
  conhecido da regra. Se o 001 mostrar que isso é a maioria dos destinos, a
  regra de produto volta à mesa antes de escrever o código.

**Uma decisão de produto vem antes do código, e é do usuário.** A pesquisa (002)
mediu que as quatro concorrentes fazem da saída uma **opção**, com sair como
padrão de fábrica — Yoink, Dropover, Dropzone e OpenYoink. Este mapa travou a
saída como regra fixa antes de saber disso. Pergunte antes de escrever: regra
fixa, ou chave em Ajustes com sair ligado por padrão?

A remoção da **pilha** inteira não é aqui — é no 006, que já tem o modelo.
