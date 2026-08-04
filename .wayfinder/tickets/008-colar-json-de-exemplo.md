# Colar JSON de exemplo

- map: ../map.md
- label: wayfinder:grilling
- status: closed
- assignee: sessão 2026-08-04 (008)
- blocked-by: — (007 fechado)

## Question

Permitir mapear offline, antes de qualquer POST chegar, colando um JSON.
Decidir: lê do clipboard num clique ou abre campo de texto pra colar e validar;
o que acontece com JSON inválido; se o JSON colado é só local (some ao fechar)
ou é gravado como `lastPayload` do perfil no relay; e como a UI deixa claro que
a árvore na tela é um exemplo, não algo que o serviço mandou de verdade.

## Resolução — 2026-08-04

**Mecânica: um clique, clipboard direto.** Botão "Colar JSON de exemplo" lê
`NSPasteboard.general.string(forType: .string)`, parseia com
`JSONSerialization` e monta a árvore via `JSONValue.from`. Sem campo de texto,
sem sheet, sem UI nova. O payload real do ClickUp tem ~3 KB e 25 chaves de
ruído (`reccurence`, `privacy`, `templating`, `_version_vector`): digitar ou
revisar isso num `TextEditor` nunca ia acontecer — o caminho real é copiar do
webhook.site e colar de uma vez. Bônus: evita `TextEditor` (é `ScrollView`,
logo invisível pro `tools/snapshot.sh`).

**JSON inválido: aviso inline com trecho do que foi lido.** No lugar do estado
vazio, uma mensagem não-bloqueante: "O que está copiado não é um JSON válido"
mais os primeiros ~80 caracteres do clipboard, para o usuário reconhecer o erro
clássico (copiou a página inteira em vez do corpo). Árvore anterior, se havia,
fica intacta. Nada de `NSAlert` — erro corriqueiro não merece modal, e modal
some sem deixar rastro na tela.

**Escopo: só local, memória da sessão.** Vive num `@State` do editor e some ao
fechar o sheet. O relay nunca sabe. Zero mudança na API; `lastPayloadAt` e
`payloadCount` (007) continuam significando "chegou POST de verdade", e o sinal
de saúde do painel não passa a contar evento que ninguém mandou. Reabrir o
editor exige colar de novo — aceito: o clipboard normalmente ainda tem o JSON e
é um clique. Nada de `UserDefaults`: estado novo pra migrar e sincronizar não
paga um Cmd+V.

**Marca de exemplo: faixa persistente no topo da árvore.** Enquanto a árvore for
colada, uma linha fixa acima dela: "Exemplo colado — nada chegou neste perfil
ainda" + "Descartar". Persistente, não toast: a confusão é duradoura (salvar o
mapping achando que testou o link), e toast some antes de causar efeito.

**Real vence o exemplo, e troca sozinho.** `lastPayloadAt` novo pelo polling de
2s do 007 substitui a árvore de exemplo na hora, e a faixa vira "Chegou um
payload de verdade — o exemplo foi trocado". O exemplo é andaime: o instante em
que o real chega é justamente o que se estava esperando. O trabalho não se
perde porque 005 nunca sobrescreve campo preenchido.

**O exemplo dispara o auto-mapeamento (005) como payload real.** Colar conta
como "payload novo": roda preset-primeiro/heurística-depois uma vez, mesmo
banner não-bloqueante. É o ponto do ticket — mapear offline antes de qualquer
POST. Quando o real chega, 005 roda de novo por `lastPayloadAt` novo e respeita
o que já está preenchido.

**Onde fica o botão:** no **estado vazio do editor** (ao lado de "Recarregar",
onde a pessoa trava hoje) e no **passo Primeiro envio do assistente** (013 fixou
o assistente como porta única de perfil novo; o protótipo 004 já o desenha lá).
**Não** entra como menu de fontes com árvore cheia: colar por cima de payload
real é raro e briga com "real vence".
