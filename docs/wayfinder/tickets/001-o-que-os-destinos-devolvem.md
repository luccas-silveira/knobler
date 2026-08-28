# 001 — O que os destinos devolvem quando aceitam o arraste

Map: [Shelf de arquivos — empilhamento, ordem e saída](../map-shelf-de-arquivos.md)
Type: `wayfinder:measure`
Status: aberto
Assignee: —
Blocked by: —

## Pergunta

A regra travada é "o item sai da shelf em qualquer arraste bem-sucedido pra
fora". Ela depende de o Knobler conseguir distinguir **aceito** de **recusado**
quando a sessão de arraste termina — e isso ainda não foi olhado.

Hoje `DragThumbView` não implementa `draggingSession(_:endedAt:operation:)`, e
`sourceOperationMaskFor` devolve `.copy` fixo. A pergunta é o que chega naquele
callback, por destino, com só `.copy` anunciado:

- Finder (soltar numa pasta e soltar na Mesa)
- Chrome (um campo de upload e uma área de anexo)
- Slack ou outro app Electron
- Mail (anexar)
- soltar no vazio, sem destino nenhum

Pra cada um: qual `NSDragOperation` volta, e ela separa aceitar de recusar.

Se algum destino devolver `.none` mesmo tendo aceitado o arquivo, a remoção não
dispara ali, e a decisão de produto precisa voltar à mesa — por isso este ticket
vem antes de escrever a remoção.

**Não anuncie `.move` na sondagem.** A shelf guarda o caminho do original, e
`.move` faria o Finder mover o arquivo do usuário de verdade.

Um motivo a mais pra medir em vez de confiar: o Dropzone **perdeu** a
remoção-ao-arrastar num bug do macOS Sequoia e só descobriu por reclamação de
usuário no fórum (2024-09-04, corrigido na 4.80.20). A base deste mecanismo já
quebrou sozinha numa shelf comercial madura — ver [pesquisa-002](../pesquisa-002-shelfs-do-macos.md).

A medição precisa de mão humana pra fazer os arrastes; o agente prepara a build
instrumentada e entrega a lista do que arrastar pra onde.
