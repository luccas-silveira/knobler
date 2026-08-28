# 004 — O modelo de pilha e a persistência

Map: [Shelf de arquivos — empilhamento, ordem e saída](../map-shelf-de-arquivos.md)
Type: `wayfinder:task`
Status: aberto
Assignee: —
Blocked by: 003

## Pergunta

A shelf hoje é `[URL]` — uma lista plana de caminhos, gravada em `shelfItems`
no UserDefaults como array de strings. Uma prateleira que mistura itens soltos
e pilhas não cabe nessa forma.

O que este ticket entrega:

1. **O tipo** que representa uma entrada da shelf, sabendo ser um arquivo só ou
   um conjunto. A capacidade continua **8 entradas**, e uma pilha ocupa uma.
2. **A persistência** — como isso vai pro UserDefaults, e o que acontece com a
   prateleira de quem já tem `shelfItems` gravado no formato antigo. Migrar ou
   descartar é decisão deste ticket.
3. **O que quebra junto**: `tools/shelfdropcheck.swift` lê o modelo, e a receita
   de captura da imagem da prateleira nos docs escreve `shelfItems` via
   `defaults` — trocar o formato invalida as duas. A skill `snapshot-ui` tem a
   receita.

Nada de UI aqui. As três frentes da fase 3 constroem sobre este modelo, e é por
isso que ele vem sozinho.
