# 003 — Qual mecanismo conserta

Map: [O knob cortado ao meio](../map-corte-do-knob.md)
Type: `grilling`
Status: aberto
Assignee: —
Blocked by: 001, 002

## Pergunta

Com a repro e o inventário na mão, qual rota conserta a causa — e quanto cada uma custa?

Rotas em disputa, para a conversa não começar do zero:

- **Uma transação só.** Envolver as mudanças que mexem na altura num `withAnimation`
  único, para moldura e conteúdo nunca animarem separados. Diff pequeno, mas depende de
  achar todos os pontos de mutação.
- **Fonte única de verdade da altura.** `currentSize` deixa de ser soma de constantes e
  passa a ser medido do conteúdo. Elimina a classe inteira de divergência e é o diff maior.
- **Conserto defensivo.** A moldura nunca fica menor que o conteúdo, por construção, sem
  atacar a origem da dessincronia. Barato, esconde a causa.

Escolha do usuário, não do agente: as três têm perfis de risco diferentes e ele é quem
paga o custo. Apresente as três com o custo medido e recomende uma.

Se a 001 não reproduziu, esta conversa também decide se o mapa segue sem repro ou volta
para captura.
