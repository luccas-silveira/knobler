# 006 — Um drop de vários vira uma pilha

Map: [Shelf de arquivos — empilhamento, ordem e saída](../map-shelf-de-arquivos.md)
Type: `wayfinder:task`
Status: fechado
Assignee: claude
Blocked by: 004, 005

## Pergunta

Soltar cinco arquivos de uma vez cria **uma** entrada na shelf, não cinco.

Hoje `ShelfDropDelegate.performDrop` percorre os providers e chama `add()` em
cada um: um drop de uma pasta de fotos come a prateleira inteira e empurra pra
fora o que já estava lá. É a dor que originou este mapa.

O que entra:

1. Um drop com mais de um arquivo vira uma pilha, na primeira posição (regra do
   003). Drop de um arquivo só continua item solto.
2. A miniatura da pilha mostra que é pilha e quantos arquivos tem.
3. Arrastar a pilha pra fora leva os N arquivos juntos, e a pilha inteira sai da
   shelf — a regra do 005 aplicada ao conjunto.

Os providers chegam assíncronos e fora da main; agrupar exige esperar todos do
mesmo drop antes de criar a entrada, o que o laço de hoje não faz.

## Resposta

Um drop de N arquivos vira **uma** entrada, na frente da fila.

`ShelfDropDelegate.performDrop` separa os providers de `public.file-url` do
resto e os passa por `carregarJuntos`: cada callback escreve no próprio índice
de um buffer, na main, e o último chama `add(_:)` uma vez. O índice não é
detalhe — `capa` é a miniatura que a linha mostra e o alvo do menu de contexto,
então acumular por ordem de chegada faria a capa de um drop de 5 fotos ser
sorteada. Link e texto continuam cada um por si: "drop de vários arquivos" é o
caso todo-fileURL.

A pilha se anuncia com duas folhas atrás da miniatura, o número de arquivos num
badge e o nome trocado por "N arquivos".

A saída da pilha e o pasteboard de N arquivos são **a mesma mudança**, não duas:
`saiAoArrastar` perdeu o parâmetro `isPilha` e `startDrag` passou a montar um
`NSPasteboardItem` por arquivo. Landar uma sem a outra é perda de dado — a
entrada some da prateleira e o destino recebeu só a capa. O caminho de um
arquivo ficou byte a byte o de sempre (bytes da imagem + file-url no mesmo
item), porque é comportamento duramente conquistado pro alvo Electron.

Ponto não verificado: **as folhas e o badge não têm caminho de prova.** A shelf
não renderiza offscreen, então o `snapshot.sh` não vê nada disso — fica pro 009,
na tela.

Um provider que nunca chama de volta segura o drop inteiro em vez de perder um
arquivo só. Marcado com `// ponytail:`; sem timeout até aparecer na prática.
