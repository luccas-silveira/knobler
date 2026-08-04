# Como a árvore do payload chega ao editor ao vivo

- map: ../map.md
- label: wayfinder:grilling
- status: closed
- assignee: —
- blocked-by: —

## Question

Hoje `MappingEditorView` só popula a árvore por `getProfile` sob clique manual
em "Recarregar". Decidir como o editor passa a mostrar o payload assim que ele
chega: polling do `GET /profiles/:id` enquanto o sheet está aberto, ou o relay
empurrando pelo WebSocket já existente (`WebhookClient` mantém um socket vivo).

Isso fixa o contrato com o relay que os tickets de colar JSON e de histórico
herdam: o que `GET /profiles/:id` devolve sobre o último recebimento
(`lastPayload`, `lastPayloadAt`, contagem) e se existe um canal de "chegou
payload no perfil X".

## Resolução (2026-08-04)

**Polling do `GET /profiles/:id` enquanto o sheet está aberto.** 2s fixos, para
ao fechar. Nada de canal novo no WebSocket.

### Por que não o socket

O socket de `WebhookClient` é do **device**, não do perfil, e carrega um único
tipo (`type: "notify"`, decodificado em `PushNotification`,
`Knobler/WebhookClient.swift:231`). Um payload capturado sem mapping nem chega
a virar mensagem — o relay responde `202 captured` e **não empurra nada**
(`relay/src/server.js:107`). Usar o socket exigiria: tipo de mensagem novo,
decodificação nova, roteamento pro sheet aberto e estado de "quem está
escutando o perfil X" no hub — tudo pra um sheet que fica aberto minutos. O
polling usa endpoint que já existe, morre sozinho quando o sheet fecha e não
tem estado nenhum no relay.

### Contrato com o relay (aditivo)

`GET /profiles/:id` passa a devolver dois campos novos:

- `lastPayloadAt` — epoch ms da última captura (`null` se nunca recebeu).
- `payloadCount` — total recebido no perfil, monotônico.

Coluna nova em `profiles` e escrita junto do `storeLastPayload` já existente.
O editor compara `lastPayloadAt`: mudou, repopula a árvore; igual, não toca em
nada (não pisca, não perde seleção, não roda o auto-mapeamento de novo).

`payloadCount` existe pra distinguir "chegou o mesmo payload de novo" de "não
chegou nada", e é o que alimenta o sinal de saúde do painel ("último webhook há
3 min") — a névoa do mapa que dependia deste contrato.

### Cadência

- 2s enquanto o sheet está aberto. Sem backoff, sem adaptação: a janela de vida
  é curta e o `/w/` é que tem rate limit, não a API autenticada.
- Para quando o sheet fecha e quando a janela perde a visibilidade
  (`occlusionState`) — não gastar rede com Ajustes atrás de outra janela.
- "Recarregar" continua existindo como forçar agora.

### O que 008 e 009 herdam

- **008 (colar JSON)**: a árvore tem uma fonte só — o estado do editor. Payload
  colado entra pelo mesmo caminho que o polling popula, e o polling **pausa**
  enquanto uma árvore colada estiver em cena (senão o próximo POST atropela o
  exemplo do usuário). Retomar é decisão de 008.
- **009 (histórico)**: `payloadCount` já dá o número de eventos; guardar os
  últimos N é extensão do mesmo endpoint (`GET /profiles/:id/payloads`), não
  contrato novo. O polling continua olhando só `lastPayloadAt`.

### Fica pra execução

- `relay/src/db.js` (coluna `last_payload_at`, `payload_count`) +
  `relay/src/server.js:155` + caso em `relay/test/server.test.js`.
- `ProfileDetail` em `Knobler/WebhookClient.swift:311` e o timer no sheet.
