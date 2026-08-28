# 005 — O item sai da shelf ao ser arrastado pra fora

Map: [Shelf de arquivos — empilhamento, ordem e saída](../map-shelf-de-arquivos.md)
Type: `wayfinder:task`
Status: fechado
Assignee: claude
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

## Resposta

**Chave em Ajustes › Prateleira, ligada de fábrica** — decisão do usuário, como
o 002 recomendou. `AppSettings.shelfSaiAoArrastar`.

A regra vive em `ShelfOrdem.saiAoArrastar(aceitou:dentroDoNotch:isPilha:habilitado:)`,
coberta por cinco asserções no `shelfordemcheck`. Sai quando os quatro batem.

O sinal que separa o arraste interno do externo **não é geometria**: o painel do
notch tem 700pt de largura e vai do topo da tela até o Dock, então um Finder no
meio da tela cairia dentro do frame. É um aperto de mão — `ShelfDropDelegate.performDrop`
liga `ShelfArrasteInterno.pendente` sincronamente, e `draggingSession(_:endedAt:_:)`
consome. O enum mora em `ShelfThumbnailDragView.swift` pra `tools/sondaarraste/`
seguir compilando só a miniatura.

`operation.contains(.copy)`, não `==`: `NSDragOperation` é OptionSet. A Lixeira
devolve `.delete` e o item fica — lado seguro do erro.

Pilha nunca sai: só a capa vai pro pasteboard, e remover a entrada inteira
levaria arquivos que ninguém arrastou. Isso é o 006.

Duas suposições que o gate não prova, e que o 009 confirma na tela:

- `ShelfDropDelegate.performDrop` dispara para um arraste que começa dentro da
  própria janela. O aperto de mão inteiro depende disso. Se não disparar, o
  arraste interno apaga o item — exatamente o que o 001 avisou.
- `performDrop` roda antes de `draggingSession(_:endedAt:_:)`.

Sem prova visual: a prateleira não renderiza offscreen, e a prova é o 009.
