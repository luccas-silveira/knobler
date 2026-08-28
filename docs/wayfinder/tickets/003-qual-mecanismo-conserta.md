# 003 — Qual mecanismo conserta

Map: [O knob cortado ao meio](../map-corte-do-knob.md)
Type: `grilling`
Status: fechado (2026-08-21)
Assignee: sessão 003 (grilling com o usuário)
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

## Resolução

**A premissa do mapa caiu, e é isso que esta decisão registra.**

O que caiu, e como se mediu: a hipótese de trabalho era que moldura e conteúdo animavam
em transações diferentes e a moldura ficava menor que o conteúdo. A [001](001-reproduzir-o-corte.md)
injetou esse defeito na `NotchView` de verdade — moldura 60 pt menor — e o harness acusou
**0 de 34**. Não foi injeção inerte: o desenho mudou (o controle positivo saiu 0–470 em
vez de 0–530). Forma e conteúdo dividem o mesmo `ZStack` sob o mesmo `.mask(shape)`
(`NotchView.swift:181` e `:249`), então encolher `currentSize` encolhe os dois juntos.
**A classe inteira "moldura menor que o conteúdo" está morta como mecanismo do corte.**

O que sobreviveu da [002](002-auditar-moldura-contra-conteudo.md): o inventário. Os 20
identificadores que mudam a altura, os 7 amarrados a animação, os 13 que não estão e os 8
que mudam com o `mode` parado continuam medidos e continuam valendo. O que morreu foi a
conclusão que se tirava deles, não a contagem.

O que sobrou como pista: a única injeção que pintou a forma do sintoma relatado foi a
moldura empurrada 60 pt **pra baixo** — e nada no código auditado faz isso. E em toda
corrida algumas fotos saem sem moldura e sem conteúdo, sempre em cima de uma troca de
`mode`, enquanto o controle parado nunca some.

### Rotas apresentadas ao usuário, com o custo de cada uma

1. **Mais uma medição, de ambiente.** O harness da 001 dirigiu só mudanças de estado da
   interface. Nunca dirigiu troca de Space, `orderOut`/`orderFrontRegardless`, `setFrame`
   com a janela visível, nem acordar do sono. Custo: uma sessão, AFK, sem tocar na máquina
   do usuário. Mantém o destino "causa raiz achada" vivo.
2. **Autodiagnóstico na build normal.** Código permanente que grava a geometria quando
   moldura e conteúdo divergem. Revisita a decisão travada de não rodar build
   instrumentada — aqui o código vai na versão de sempre. Custo: código no app para
   sempre, e esperar o defeito acontecer.
3. **Conserto defensivo agora.** Refazer o layout em eventos suspeitos, sem causa. Custo:
   pode não pegar o caso real, e é literalmente o "enjambrado" que o usuário quer evitar.
4. **Redefinir o destino.** Blindar sem provar, com o gate na métrica viva. Custo: mapa
   fecha rápido com a causa em aberto.

### Escolhida, e por quem

**Rota 1**, escolhida pelo usuário. Nasce dela o ticket [003.1](003.1-eventos-de-ambiente.md).

O usuário também decidiu **trazer de volta ao escopo** os eventos de janela, tela cheia e
sono — como **suspeitos da causa**, não como área a consertar. Se a causa estiver lá, o
conserto vem junto; posicionamento em multi-monitor e comportamento em tela cheia
continuam fora.

### O que muda no 005

O gate não pode ser escrito contra "moldura menor que o conteúdo": essa métrica é cega,
provado acima. A métrica provada viva é a **lacuna de topo** — com a moldura empurrada
60 pt pra baixo, o harness acusa 60,0 pt em todas as combinações. O gate da 005 mira nela.

O gate — hoje o ticket [005](005-aplicar-e-travar-o-gate.md) — passa a ser bloqueado pela medição que vier depois, não por este
ticket.
