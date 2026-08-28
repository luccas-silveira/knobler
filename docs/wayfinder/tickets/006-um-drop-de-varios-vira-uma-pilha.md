# 006 — Um drop de vários vira uma pilha

Map: [Shelf de arquivos — empilhamento, ordem e saída](../map-shelf-de-arquivos.md)
Type: `wayfinder:task`
Status: aberto
Assignee: —
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
