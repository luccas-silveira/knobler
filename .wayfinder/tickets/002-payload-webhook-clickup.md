# Payload de webhook do ClickUp

- map: ../map.md
- label: wayfinder:research
- status: closed
- assignee: research subagent (concluído)
- blocked-by: —

## Question

Qual é a forma real do JSON dos webhooks do ClickUp (`taskCreated`,
`taskStatusUpdated`, `taskCommentPosted`)? Mesmos itens do ticket do GHL:
caminhos pra título/corpo/URL/ícone, o que é estável entre eventos, campo de id.
Notar que o ClickUp manda `event` + `task_id` e às vezes exige buscar a tarefa
pra ter o nome — se for o caso, registrar, porque isso limita o que um preset
consegue mapear sem chamada extra.

Saída: `.wayfinder/research/clickup.md`.

## Resolution

Achados completos em [`.wayfinder/research/clickup.md`](../research/clickup.md).

O webhook de API do ClickUp tem quatro chaves de topo (`event`, `task_id`,
`history_items`, `webhook_id`) e **não manda o nome da tarefa** — nem descrição,
nem URL, nem lista, nem responsáveis. Só o delta e quem fez.

- Único texto humano garantido: `history_items[0].user.username`.
- Comentário é a exceção boa: `history_items[0].comment.text_content` já vem em
  texto puro. `taskStatusUpdated` também é usável cru (`before.status` →
  `after.status` legíveis, `after.color` é hex pronto).
- Nome de graça só em `taskUpdated` com `field == "name"` (aí `after` é o nome).
- URL de abrir é **construída**: `https://app.clickup.com/t/{task_id}`.
- `taskDeleted` não tem `history_items` — parser que assumir o array quebra.
- `taskUpdated` é polimórfico: `before`/`after` mudam de forma por `field`;
  descrição chega como JSON Quill escapado dentro de uma string.
- Dedupe: `history_items[].id`. `webhook_id` não serve (é o id do registro).
- Enriquecer custa `GET /api/v2/task/{task_id}` — credencial guardada, 1 request
  por notificação, rate limit, latência.

Consequência pro mapa: um preset de ClickUp **útil** não sai de mapeamento
puro de campos. Ou o preset se limita a comentário e mudança de status, ou o
app precisa de uma etapa de enriquecimento — que é arquitetura nova, não
template. Ficou uma saída a testar: a ação "Call webhook" das *Automações* do
ClickUp (produto, não API) aparentemente manda `task.name` junto — confiança
baixa-média, fonte terceira. Isso virou ticket próprio, porque decide se o
preset precisa de enriquecimento.
