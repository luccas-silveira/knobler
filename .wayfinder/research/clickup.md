# Payload de webhook do ClickUp

Pesquisa do ticket `.wayfinder/tickets/002-payload-webhook-clickup.md`.
Data: 2026-08-04.

## TL;DR — a informação que importa

**Confirmado: o webhook de API do ClickUp NÃO manda o nome da tarefa.**

O corpo de um evento de tarefa tem exatamente três chaves de topo:

```
event         String  — "taskCreated" | "taskUpdated" | "taskStatusUpdated" | ...
task_id       String  — id curto da tarefa ("1vj37mc", "86ajvftct")
history_items Array   — o(s) delta(s) que dispararam o evento
webhook_id    String  — uuid do webhook registrado (não do evento)
```

Nada de `name`, `description`, `url`, `list.name`, `space`, `priority` ou
`assignees` da tarefa. Só o delta e quem fez.

**Consequência pro preset:** um preset ClickUp sem enriquecimento consegue
montar um card com *ação + autor + valor novo* (ex.: "John → em progresso"),
mas **não** com o nome da tarefa. Título com nome de tarefa exige uma chamada
extra `GET /api/v2/task/{task_id}` (que aí sim devolve `name`, `url`, `status`,
`list`, `assignees` — verificado ao vivo via MCP neste workspace). Isso é
uma decisão de arquitetura, não um detalhe: ou o preset é "burro" (só delta),
ou o Knobler precisa de um fetch autenticado por notificação.

Exceção: a ação **"Call webhook"** das Automações do ClickUp (produto, não API)
manda um payload diferente, com objeto `task` completo incluindo `name` —
confiança **média**, ver §6.

## 1. Payloads de exemplo, anotados

Fonte literal: <https://developer.clickup.com/docs/webhooktaskpayloads>.

### taskCreated

```jsonc
{
  "event": "taskCreated",
  "history_items": [
    {
      "id": "2800763136717140857",   // id do item de histórico — ESTÁVEL, ver §4
      "type": 1,
      "date": "1642734631523",       // epoch ms, STRING
      "field": "status",             // o que mudou
      "parent_id": "162641062",      // id da LISTA, não da tarefa
      "data": { "status_type": "open" },
      "source": null,                // origem (api, automation, ...) — costuma vir null
      "user": {                      // <- único texto humano garantido no payload
        "id": 183,                   // INTEIRO, não string (armadilha documentada)
        "username": "John",
        "email": "john@company.com",
        "color": "#7b68ee",
        "initials": "J",
        "profilePicture": null       // URL do avatar, ou null
      },
      "before": { "status": null, "color": "#000000", "type": "removed", "orderindex": -1 },
      "after":  { "status": "to do", "color": "#f9d900", "orderindex": 0, "type": "open" }
    },
    {
      "id": "2800763136700363640",
      "type": 1,
      "date": "1642734631523",
      "field": "task_creation",      // o marcador "foi criada agora"
      "parent_id": "162641062",
      "data": {},
      "source": null,
      "user": { "...": "igual acima" },
      "before": null,
      "after": null
    }
  ],
  "task_id": "1vj37mc",              // <- só o id. Sem nome.
  "webhook_id": "7fa3ec74-69a8-4530-a251-8a13730bd204"
}
```

Note: `taskCreated` chega com **dois** `history_items` (status inicial +
`task_creation`). Um preset que assume `history_items[0]` pega o item de status,
não o de criação.

### taskUpdated (mudança de descrição)

```jsonc
{
  "event": "taskUpdated",
  "history_items": [
    {
      "id": "2800768061568222238",
      "type": 1,
      "date": "1642734925064",
      "field": "content",            // "content" = descrição da tarefa
      "parent_id": "162641062",
      "data": {},
      "source": null,
      "user": { "id": 183, "username": "John", "...": "..." },
      "before": null,
      // after é uma STRING contendo JSON Quill/Delta escapado, não texto puro:
      "after": "{\"ops\":[{\"insert\":\"This is a task description update to trigger the \"},{\"insert\":\"\\n\",\"attributes\":{\"block-id\":\"block-24d0...\"}}]}"
    }
  ],
  "task_id": "1vj37mc",
  "webhook_id": "7fa3ec74-69a8-4530-a251-8a13730bd204"
}
```

`taskUpdated` é um guarda-chuva: `field` pode ser `content`, `name`, `assignee`,
`priority`, `due_date`, `tag`, `custom_field`, etc. **A forma de `before`/`after`
muda conforme o `field`** — às vezes string, às vezes objeto, às vezes array.
Não existe um caminho único que sirva de "corpo" pra todo `taskUpdated`.

Corolário útil: quando alguém renomeia a tarefa, `field == "name"` e aí sim
`after` é o nome novo em texto puro. É o **único** caso em que o nome chega
de graça.

### taskStatusUpdated

```jsonc
{
  "event": "taskStatusUpdated",
  "history_items": [
    {
      "id": "2800787326392370170",
      "type": 1,
      "date": "1642736073330",
      "field": "status",
      "parent_id": "162641062",
      "data": { "status_type": "custom" },
      "source": null,
      "user": { "id": 183, "username": "John", "...": "..." },
      "before": { "status": "to do",       "color": "#f9d900", "orderindex": 0, "type": "open" },
      "after":  { "status": "in progress", "color": "#7C4DFF", "orderindex": 1, "type": "custom" }
    }
  ],
  "task_id": "1vj38vv",
  "webhook_id": "7fa3ec74-69a8-4530-a251-8a13730bd204"
}
```

O melhor evento pra um preset sem enriquecimento: `before.status` → `after.status`
são strings legíveis, e `after.color` é um hex pronto pra tingir o card.

### taskCommentPosted

```jsonc
{
  "event": "taskCommentPosted",
  "history_items": [
    {
      "id": "2800803631413624919",
      "type": 1,
      "date": "1642737045116",
      "field": "comment",
      "parent_id": "162641285",
      "data": {},
      "source": null,
      "user": { "id": 183, "username": "John", "...": "..." },
      "before": null,
      "after": "648893191",          // id do comentário, como string
      "comment": {                   // <- único evento com corpo de texto pronto
        "id": "648893191",
        "date": "1642737045116",
        "parent": "1vj38vv",         // id da tarefa (redundante com task_id)
        "type": 1,
        "comment": [                 // rich text em blocos
          { "text": "comment abc1234", "attributes": {} },
          { "text": "\n", "attributes": { "block-id": "block-4c8f..." } }
        ],
        "text_content": "comment abc1234\n",   // <- USE ESTE: texto puro
        "user": { "id": 183, "username": "John", "profilePicture": null, "...": "..." },
        "reactions": [], "emails": [], "email_attachments": [],
        "threaded_replies": 0, "thread_followers": [ /* users */ ],
        "x": null, "y": null, "page": null, "view_id": null, "view_name": null
      }
    }
  ],
  "task_id": "1vj38vv",
  "webhook_id": "7fa3ec74-69a8-4530-a251-8a13730bd204"
}
```

### taskDeleted (o mínimo absoluto)

```json
{
  "event": "taskDeleted",
  "task_id": "1vj37mc",
  "webhook_id": "7fa3ec74-69a8-4530-a251-8a13730bd204"
}
```

Sem `history_items`. Qualquer parser que exija `history_items` quebra aqui.

## 2. Caminhos pro card de notificação

Notação: `$` = raiz do payload, `H` = `$.history_items[0]`.

| Slot do card | Caminho | Vale pra | Observação |
|---|---|---|---|
| **Título** | — | — | **Não existe.** Nome da tarefa não vem. Melhor aproximação sem fetch: `$.event` traduzido + `$.task_id` |
| Título (renomeação) | `H.after` (quando `H.field == "name"`) | `taskUpdated` | único caso de nome grátis |
| Título (com fetch) | `GET /task/{task_id}` → `.name` | todos | exige token; ver §5 |
| **Corpo** (status) | `H.before.status` → `H.after.status` | `taskStatusUpdated`, `taskCreated` | strings legíveis |
| **Corpo** (comentário) | `H.comment.text_content` | `taskCommentPosted` | texto puro, já sem markup |
| **Corpo** (descrição) | `H.after` | `taskUpdated` c/ `field=="content"` | **JSON Quill escapado**, precisa parse + join dos `ops[].insert` |
| **Corpo** (fallback) | `H.field` + `H.after` | qualquer | forma de `after` varia por `field` |
| **Autor** | `H.user.username` | todos com `history_items` | também `.email`, `.initials`, `.color` |
| **URL de abrir** | `"https://app.clickup.com/t/" + $.task_id` | todos, inclusive `taskDeleted` | construída, não vem no payload. Confirmado contra a API ao vivo: o campo `url` de uma tarefa real é exatamente esse formato |
| **URL do comentário** | `.../t/{task_id}?comment={H.comment.id}` | `taskCommentPosted` | confiança **baixa** (não documentado; forma vista na UI) |
| **Ícone / avatar** | `H.user.profilePicture` | todos | URL http, frequentemente `null`. Fallback: `H.user.initials` sobre `H.user.color` |
| **Cor de acento** | `H.after.color` | eventos de status | hex `#7C4DFF` |
| **Timestamp** | `H.date` | todos | epoch **ms** como **string** — converter |

Estável entre todos os eventos de tarefa: **só** `event`, `task_id`, `webhook_id`.
Tudo dentro de `history_items` é opcional (some no `taskDeleted`) e polimórfico.

## 3. Cabeçalhos

- `X-Signature`: HMAC-SHA256 do corpo cru com o `secret` devolvido no
  `POST /team/{team_id}/webhook`. Validar antes de confiar no payload.
- Sem cabeçalho de id de entrega. O dedupe tem que sair do corpo (§4).

## 4. Id estável pra dedupe

- `webhook_id` — **não serve**: é o id do registro do webhook, igual em todo evento.
- `task_id` — não serve sozinho: repete a cada mudança da mesma tarefa.
- **`history_items[].id`** — serve. É o id do registro de histórico no ClickUp,
  único por mudança e preservado em reentregas/retentativas.
- Chave recomendada: `"\(event):\(history_items[0].id)"`, com fallback
  `"\(event):\(task_id):\(date)"` pro `taskDeleted`, que não tem `history_items`.
- `history_items[].comment.id` também é único, mas só existe em comentário.

Confiança **média-alta**: a estabilidade de `history_items[].id` está implícita
na doc (é o id do registro de histórico, também retornado por
`GET /task/{id}` no histórico), mas a ClickUp não documenta explicitamente
"use isto pra idempotência".

Nota operacional: a ClickUp faz retentativa em falha e **suspende o webhook após
falhas consecutivas** (`health.status: "failing"` → `"suspended"`). Um endpoint
que responde 200 rápido e processa depois evita perder eventos.

## 5. O que exige chamada extra à API

Pra qualquer coisa além de "quem mudou o quê":

```
GET https://api.clickup.com/api/v2/task/{task_id}
Authorization: <personal token ou OAuth>
```

Verificado ao vivo neste workspace (via MCP, leitura apenas) — a tarefa traz:

```json
{
  "id": "86ajvftct",
  "custom_id": "PROJ-773",
  "name": "Criar novos anúncios",
  "status": "a fazer",
  "url": "https://app.clickup.com/t/86ajvftct",
  "assignees": [{ "id": 55152067, "username": "Felipe Valentini Remor" }],
  "due_date": "1785826800000",
  "list": { "id": "901317349777", "name": "Publicidade" }
}
```

Ou seja, o enriquecimento entrega de uma vez: **nome, url canônica, lista,
responsáveis, prazo e `custom_id`** (o "PROJ-773", ótimo pra título curto).

Custo: 1 request autenticado por notificação, com credencial guardada, mais
rate limit (100 req/min no plano Free Forever; maior nos pagos) e latência
entre o webhook chegar e o card poder ser mostrado.

## 6. Alternativa: webhook de Automação (não de API)

A ação **"Call webhook"** das Automações do ClickUp manda um payload diferente,
descrito como contendo um objeto `task` com `id`, `name`, `status`, `due_date`
e a hierarquia (list/folder/space) — isto é, **o nome vem junto, sem fetch**.

Confiança **baixa-média**: vem de material de terceiro
(<https://consultevo.com/clickup-automation-webhook-payload-guide/>), não da
doc oficial de desenvolvedor, e não achei exemplo verbatim. **Se o preset puder
pedir ao usuário que configure uma Automação em vez de um webhook de API, isso
possivelmente elimina a necessidade de enriquecimento** — vale um teste real
antes de decidir a arquitetura.

## 7. Confiança e fontes

| Afirmação | Confiança |
|---|---|
| Forma dos 5 payloads (§1) | **Alta** — exemplos verbatim da doc oficial |
| Ausência do nome da tarefa | **Alta** — confirmada nos 4 exemplos oficiais |
| Formato da URL `app.clickup.com/t/{id}` | **Alta** — bate com o campo `url` de tarefas reais deste workspace |
| Campos devolvidos por `GET /task` | **Alta** — leitura ao vivo via MCP |
| `history_items[].id` como chave de dedupe | **Média-alta** |
| `?comment=` na URL do comentário | **Baixa** |
| Payload de Automação incluir `task.name` | **Baixa-média** — fonte terceira |

Fontes:
- <https://developer.clickup.com/docs/webhooktaskpayloads> (exemplos verbatim)
- <https://developer.clickup.com/docs/webhooks> (estrutura geral, `X-Signature`, tipagem)
- <https://developer.clickup.com/docs/webhooklistpayloads>
- <https://consultevo.com/clickup-automation-webhook-payload-guide/> (terceiro)
- MCP ClickUp deste workspace, somente leitura (`clickup_filter_tasks`)

---

## §8. Payload REAL da ação "Webhook de chamada" (Automação) — capturado 2026-08-04

Resolve o §6 (que era confiança baixa-média, fonte terceira). Captura própria
(ticket 010): workspace Zoi, space **Teste**, lista **Lista 1** (`901327950786`),
automação `Quando Tarefa ou subtarefa criada → Webhook de chamada` (a ação
**`webhookv2`**, não a "(antigo)"), coletor webhook.site. Disparo: tarefa criada
via API com nome, descrição em markdown, prioridade e data de vencimento.

JSON completo, verbatim: `research/payloads/clickup-automacao-webhook.json`.
Esqueleto:

```jsonc
{
  "auto_id": "d8e9382d-…:main",       // id da automação + branch
  "trigger_id": "6954dd13-…",
  "date": "2026-08-04T15:04:00.876Z",  // ISO 8601 — NÃO epoch ms
  "payload": {                          // <- tudo da tarefa vive aqui
    "id": "86ajvvnpa",
    "name": "Knobler captura 010",              // ✅ O NOME VEM
    "content": "{\"ops\":[{\"insert\":\"…\"}]}",  // Quill escapado
    "text_content": "Tarefa de teste para capturar…", // ✅ mesmo texto, limpo
    "html_content": null,
    "lower_name": "knobler captura 010",
    "priority": "2",                    // string numérica, não rótulo
    "status_id": "p901313929324_0h9D6Zm2",  // id, NÃO o nome do status
    "workspace_id": "9007072151",
    "subcategory": "901327950786",      // id da lista
    "time_mgmt": { "date_created": "1785855839804",  // epoch ms, STRING
                   "due_date": "1786384800000", … },
    "ownership": { "owner": 81976356, "creator": 81976356, "source": "api", … },
    "users": [ { "userid": 81976356, "type": "owner" }, … ],  // só ids
    "tags": [], "fields": [], "attachments": [], "checklists": [], "docs": [],
    "lists": [ { "list_id": "901327950786", "type": "home" } ],
    "reccurence": {…}, "privacy": {…}, "templating": {…}, "states": {…},
    "_version_vector": {…}
  }
}
```

Headers: `content-type: application/json`, `accept`, `user-agent: axios/0.33.0`,
`content-length`, mais tracing do Datadog/B3 (`x-datadog-*`, `x-b3-*`,
`traceparent`, `tracestate`). **Nenhuma assinatura** — o link é o único segredo.
Os headers de tracing mudam a cada entrega; não servem de dedupe.

### Veredito

| Hipótese do §6 | Real |
|---|---|
| Automação manda `task.name` sem fetch | **CONFIRMADO** — em `payload.name`. Confiança sobe de baixa-média pra **alta** |
| objeto `task` com hierarquia list/folder/space | **PARCIAL** — o objeto se chama `payload`, e a hierarquia vem só como **ids** (`subcategory`, `workspace_id`, `lists[].list_id`). Sem nomes de lista/pasta/space |
| status legível | **NÃO** — só `status_id` opaco (`p901313929324_0h9D6Zm2`) |
| responsável legível | **NÃO** — `users[].userid` numérico, sem nome nem e-mail. `created_by_email: null` |

### Consequência: preset de ClickUp sem enriquecimento é viável

Título (`payload.name`), corpo (`payload.text_content`) e URL
(`https://app.clickup.com/t/{{payload.id}}`) saem todos do payload. **Some a
necessidade de `GET /task/{id}`** para o caminho de Automação — ele continua
valendo só pro webhook de API (§1-§5), que não manda o nome.

O que continua fora de alcance sem chamada extra: nome do status, nome do
responsável, nome da lista. Nada disso é título nem corpo — é enfeite.

### Divergências que afetam decisões já fechadas

- **`text_content` existe.** O ClickUp já entrega o texto limpo **ao lado** do
  Quill escapado. O filtro `quill` de 014 continua necessário pro webhook de
  API (`history_items[0].after` em comentários), mas **não** pra este caminho —
  aqui o certo é mapear `text_content` e não filtrar nada.
- **`date` do envelope é ISO 8601**, não epoch ms. O epoch ms está dentro, em
  `time_mgmt.date_created`/`due_date` (strings). O filtro `data` de 014 tem que
  aguentar as duas formas ou o preset aponta explicitamente pro campo certo.
- **`priority` é `"2"`**, string numérica sem rótulo.
