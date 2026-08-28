# 009 — As três mudanças no app rodando

Map: [Shelf de arquivos — empilhamento, ordem e saída](../map-shelf-de-arquivos.md)
Type: `wayfinder:task`
Status: aberto
Assignee: —
Blocked by: 006, 007, 008

## Pergunta

O destino deste mapa é o app rodando, não o código escrito. Até aqui nada foi
visto na tela de verdade — a shelf é uma das seções que **não renderizam
offscreen** no harness de snapshot, então gate verde não prova nada sobre ela.

Subir a build e conferir, na tela:

1. **Ordem** — soltar três arquivos em sequência e ver o último na esquerda;
   soltar de novo o primeiro e ver ele pular pra frente; encher a prateleira e
   ver o mais antigo sair pela direita.
2. **Empilhamento** — soltar cinco de uma vez e ver uma entrada; arrastar um
   item sobre outro e ver a pilha nascer; abrir a pilha, tirar um arquivo,
   desempilhar o resto.
3. **Saída** — arrastar pra fora pro Finder e ver o item sumir da shelf **e o
   arquivo original continuar onde estava**; arrastar pra um destino que
   recusa e ver o item ficar; arrastar dentro da própria shelf e ver que não
   conta como saída.

Fechar com `./tools/check.sh` verde e o CHANGELOG escrito em `## [Unreleased]`,
mais a novidade em `Knobler/Novidades/<versão>.html` — é entrada `Added`, logo
MINOR, e o `release.sh minor` aborta sem ela.
