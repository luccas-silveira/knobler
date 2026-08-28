# 001 — O que os destinos devolvem quando aceitam o arraste

Map: [Shelf de arquivos — empilhamento, ordem e saída](../map-shelf-de-arquivos.md)
Type: `wayfinder:measure`
Status: fechado (2026-08-28)
Assignee: sessão
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

## Resolução

[medicao-001-o-que-os-destinos-devolvem.md](../medicao-001-o-que-os-destinos-devolvem.md).

Nove arrastes sintéticos dirigidos por `tools/sondaarraste/`, que compila o
arquivo real da miniatura. **A operação separa aceitar de recusar em todos os
casos medidos:** sete destinos aceitaram e os sete devolveram `copy` (Finder,
Chrome, VS Code/Electron, Mail); dois recusaram e os dois devolveram `none`
(Lixeira e soltura sem destino). Zero divergência — nenhum `copy` sem o arquivo
chegar, nenhum `none` tendo aceitado. A regra do 005 tem base pra funcionar.

**O achado que muda o desenho:** um alvo de soltura **dentro do próprio app**
devolve `copy`, igual ao Finder, e o contexto pedido em `sourceOperationMaskFor`
não separa os dois — o AppKit pergunta pelos dois contextos antes de saber onde
a soltura vai cair. Escrita ingenuamente, a remoção do 005 apagaria o item que o
007 acabou de empilhar dentro da própria prateleira. O 005 precisa de outro
sinal: o ponto de soltura contra o quadro da janela do notch, ou uma marca posta
pelo alvo interno.

**A Lixeira recusa** com só `.copy` anunciado — arrastar da shelf pro lixo não é
um gesto que funcione hoje, e fazê-lo funcionar exigiria `.delete`.

Não medido: Slack (não instalado — a classe Electron saiu do VS Code), e nenhum
destino que aceite devolvendo `none` foi encontrado, o que não prova que não
exista.

## Verificação

A receita está na seção `## Verificação` do documento de medição.
