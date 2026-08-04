# O que a Automação "Call webhook" do ClickUp manda de verdade

- map: ../map.md
- label: wayfinder:task
- status: closed
- assignee: sessão de captura 2026-08-04
- blocked-by: —

## Question

O research do webhook de API confirmou que ele não manda o nome da tarefa.
A ação **"Call webhook"** das *Automações* do ClickUp (o produto, não a API)
supostamente manda um payload mais rico, com `task.name` — confiança
baixa-média, fonte terceira. Se for verdade, o preset de ClickUp vive de
mapeamento puro; se não for, o preset exige uma etapa de enriquecimento por
API, que é arquitetura nova.

Trabalho manual (HITL): criar uma automação num espaço de teste do ClickUp
apontando pra um link de perfil do Knobler (ou pra um coletor qualquer que
mostre o corpo), disparar, e capturar o JSON cru.

Resolvido quando o payload real estiver capturado e anexado em
`.wayfinder/research/clickup.md`, dizendo em uma linha se ele basta pra um
preset sem enriquecimento.

## Resolução (2026-08-04)

Payload real capturado e anexado em `.wayfinder/research/clickup.md` (§8);
JSON completo em `.wayfinder/research/payloads/clickup-automacao-webhook.json`.
Receita: space **Teste** → lista **Lista 1** (`901327950786`), automação
`Quando Tarefa ou subtarefa criada → Webhook de chamada` (ação **`webhookv2`**,
não a "(antigo)"), coletor webhook.site, disparo por tarefa criada com nome,
descrição, prioridade e vencimento.

**Resposta em uma linha: a automação basta — preset de ClickUp por Automação
não precisa de enriquecimento por API.**

Esqueleto do JSON real (completo no arquivo acima):

```jsonc
{
  "auto_id": "d8e9382d-99ec-4d79-bc4a-9646bd2a0e46:main",
  "trigger_id": "6954dd13-7db2-4817-9fe7-dba3d463f26c",
  "date": "2026-08-04T15:04:00.876Z",
  "payload": {
    "id": "86ajvvnpa",
    "name": "Knobler captura 010",
    "content": "{\"ops\":[{\"insert\":\"Tarefa de teste …\"},{\"insert\":\"Call webhook\",\"attributes\":{\"bold\":true}},{\"insert\":\" do ClickUp (ticket 010).\\n\"}]}",
    "text_content": "Tarefa de teste para capturar o payload da automação Call webhook do ClickUp (ticket 010).",
    "html_content": null,
    "lower_name": "knobler captura 010",
    "priority": "2",
    "status_id": "p901313929324_0h9D6Zm2",
    "workspace_id": "9007072151",
    "subcategory": "901327950786",
    "time_mgmt": { "date_created": "1785855839804", "due_date": "1786384800000", "due_date_time": true, … },
    "ownership": { "owner": 81976356, "creator": 81976356, "source": "api", "created_by_email": null, … },
    "users": [ { "userid": 81976356, "type": "owner" } ],
    "lists": [ { "list_id": "901327950786", "type": "home" } ],
    "tags": [], "fields": [], "attachments": [], "checklists": [], "docs": [],
    "reccurence": {…}, "privacy": {…}, "templating": {…}, "states": {…}, "_version_vector": {…}
  }
}
```

### Comparação com o research

| Previsão do §6 (confiança baixa-média) | Real |
|---|---|
| manda `task.name` | **confirmado** — `payload.name`. Sobe pra **alta** |
| objeto chamado `task` | **não** — chama-se `payload`, e é o corpo inteiro da tarefa |
| hierarquia list/folder/space | só **ids** (`subcategory`, `workspace_id`, `lists[].list_id`); nenhum nome |
| `status`, `due_date` | `status_id` **opaco**; datas em epoch ms dentro de `time_mgmt` |

Bônus não previsto: **`text_content`** — o ClickUp entrega o texto limpo ao lado
do Quill escapado (`content`). E os headers não trazem assinatura (só tracing
Datadog/B3, que muda por entrega): o link é o único segredo.

### Efeito nas decisões fechadas

- **014 (filtros)**: **dois ajustes de fato, nenhuma redecisão.**
  (a) O filtro `quill` **não** é necessário neste caminho — mapear
  `payload.text_content` resolve. Ele continua necessário pro webhook de **API**
  (`history_items[0].after` de comentário), que é outro caminho de preset.
  (b) O `.date` do envelope **é ISO 8601**, não epoch ms como o ticket 014
  supôs. O epoch ms existe, mas em `time_mgmt.date_created`/`due_date`, como
  **string**. O filtro `data` precisa aceitar as duas formas, ou o preset aponta
  pro campo certo e a dica de forma carrega o filtro.
- **006 (assinatura mínima)**: o caminho "ClickUp API" usa `event` **e**
  `task_id` — **este payload não tem nenhum dos dois**, então não se disfarça de
  webhook de API: bom, as assinaturas não colidem. Mas o caminho de **Automação**
  precisa da sua própria assinatura, que 006 não escreveu (a tabela lista só
  "ClickUp API"). Proposta registrada em 006: `auto_id` **e** `payload.id`.
- **005 (lista de chaves sem preset)**: **precisa de ajuste.** `name` casa em
  `payload.name` (bom), mas a lista de **corpo** contém `content` e **não**
  `textcontent` — a busca por largura acharia `payload.content`, o **Quill
  escapado**, e o corpo do card sairia como JSON. Anotado em 005: pôr
  `textcontent` **antes** de `content` na lista de corpo. Edição de literal.
- **Enriquecimento por API** (fog do mapa): continua fora para o caminho de
  Automação; segue de pé só pro webhook de API.

Limpeza feita na conta: tarefa de teste, automação e webhook removidos.
