# 008 — A pilha expandida

Map: [Shelf de arquivos — empilhamento, ordem e saída](../map-shelf-de-arquivos.md)
Type: `wayfinder:prototype`
Status: aberto
Assignee: —
Blocked by: 004

## Pergunta

Sem um jeito de abrir a pilha, um drop de vinte fotos vira um bloco que só
existe inteiro: ou leva as vinte, ou nada. Expandir é o que devolve o controle
sobre um arquivo só.

Decisão já travada com o usuário: a pilha aberta **toma o card inteiro**, numa
grade de várias linhas, em vez de tentar caber na linha única da shelf. O
motivo é a mesma parede que criou a capacidade 8 — a linha não rola, e
`ScrollView` é uma vala conhecida deste projeto. Investigar o `ScrollView` foi
posto fora de escopo pelo usuário.

O que este protótipo tem que mostrar, barato, pra reagir em cima:

1. Como se abre e como se fecha a pilha.
2. A grade: quantos cabem, o que acontece com nome de arquivo comprido.
3. Dentro da pilha aberta: arrastar um arquivo pra fora, remover um no ✕.
4. Como a shelf volta ao normal — a pilha aberta é um estado da seção shelf, e
   o card já tem outras seções disputando o espaço.

Consultar a skill `impeccable`. Consultar `snapshot-ui` antes de qualquer
captura: a imagem da prateleira nos docs é tirada no app rodando e recapturá-la
mexe na máquina do usuário — **peça antes**.
