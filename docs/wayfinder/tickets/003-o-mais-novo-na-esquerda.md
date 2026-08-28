# 003 — O mais novo na esquerda

Map: [Shelf de arquivos — empilhamento, ordem e saída](../map-shelf-de-arquivos.md)
Type: `wayfinder:task`
Status: em andamento
Assignee: claude
Blocked by: —

## Pergunta

Inverter a ordem da shelf: o item que acabou de entrar aparece na **esquerda**,
e o mais antigo é o que cai pela **direita** quando a prateleira enche.

Hoje `ShelfStore.add` faz `items.append` (novo à direita) e o excesso sai por
`removeFirst` (o mais antigo, que está à esquerda). Ou seja: a regra de idade
já está certa, o que está invertido é o lado.

Três comportamentos a acertar juntos:

1. O novo entra na frente da linha.
2. Soltar de novo um arquivo **que já está na shelf** puxa ele pra primeira
   posição. Hoje o `guard !items.contains(url)` ignora o repetido e ele fica
   onde estava — o usuário decidiu que re-arrastar é sinal de que voltou a usar
   aquele arquivo, e ele deixa de ser candidato a cair pela borda.
3. O excesso sai pela direita.

A escolha entre inverter na exibição e inverter no armazenamento é do ticket,
mas pesa: quem já tem `shelfItems` gravado no UserDefaults tem um array em
ordem de idade, e inverter o armazenamento faz a prateleira dessa gente
aparecer com a idade trocada no primeiro lançamento depois da atualização.

Este ticket fixa a semântica de ordem que o modelo de pilha (004) herda, e por
isso vem antes dele.
