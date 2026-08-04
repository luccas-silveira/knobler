# Capturar um POST real da ação Webhook de workflow do GHL

- map: ../map.md
- label: wayfinder:task
- status: closed
- assignee: sessão de captura 2026-08-04
- blocked-by: —

## Question

O research fechou o webhook de Marketplace com payload real (Webhook Logs
Dashboard), mas não existe JSON capturado publicamente da **ação Webhook dentro
de um workflow** — que é justamente a via que um usuário do Knobler usaria, por
não exigir app de Marketplace.

Trabalho manual (HITL), receita de ~5 min: criar um workflow de teste numa
location, gatilho simples (tag adicionada num contato), ação "Webhook
(Outbound)" apontando pra webhook.site, disparar, capturar corpo e headers.

Responder com o payload em mãos:
- `contact_id` vem mesmo? Que mais vem por padrão nesse gatilho?
- existe header de assinatura, ou o link é o único segredo?
- Custom Data aparece no mesmo nível ou aninhado?

Resolvido quando o payload real estiver anexado em
`.wayfinder/research/ghl.md`. Ele é o exemplo embutido do preset de GHL, se é
que um preset de workflow é viável.

## Resolução (2026-08-04)

Payload real capturado e anexado em `.wayfinder/research/ghl.md` (Parte 3, com
headers, tabela de veredito e descobertas novas). Receita usada: location
`adriN's Playground`, workflow do zero, gatilho **Tag de contato** sem filtro,
ação **Webhook** (a grátis) apontando pra webhook.site, Custom Data
`origem_knobler: captura-012`, disparo por tag num contato recém-criado.

```json
{
  "contact_id": "gxGfB9wxEy3anxbHB4nT",
  "first_name": "Knobler",
  "last_name": "Captura012",
  "full_name": "Knobler Captura012",
  "email": "knobler.captura012@example.com",
  "tags": "knobler-captura",
  "country": "BR",
  "date_created": "2026-08-04T14:53:09.703Z",
  "full_address": "",
  "contact_type": "lead",
  "location": {
    "name": "adriN's Playground",
    "address": "R. Olívio Menestrina - Vila Nova",
    "city": "Joinville",
    "state": "Santa Catarina",
    "country": "BR",
    "postalCode": "89237-130",
    "fullAddress": "R. Olívio Menestrina - Vila Nova, Joinville Santa Catarina 89237-130",
    "id": "t9Ww7bY1xJJ6ThFHZVPC"
  },
  "workflow": { "id": "d325be72-ae1d-490a-b6e7-62b404ecd35b", "name": "New Workflow : 1785854951058" },
  "triggerData": {},
  "contact": {
    "attributionSource": { "sessionSource": "CRM UI", "medium": "manual", "mediumId": null },
    "lastAttributionSource": {}
  },
  "attributionSource": {},
  "customData": { "origem_knobler": "captura-012" }
}
```

### As três perguntas do ticket

1. **`contact_id` vem mesmo?** **Vem** — e é a primeira chave. O research dava
   confiança **baixa** ("não assumir"); sobe pra **alta**. Além dele, o gatilho
   de tag manda o núcleo de contato (`first_name`, `last_name`, `full_name`,
   `email`, `tags`, `country`, `date_created`, `full_address`, `contact_type`),
   o bloco `location` completo, `workflow: {id,name}`, e três chaves de
   atribuição (duas vazias). Nada de `opportunity`/`calendar`/`task` — bate com
   a previsão de que o conteúdo segue o gatilho.
2. **Assinatura?** **Não existe.** Os únicos headers são `content-type`,
   `accept`, `accept-encoding`, `user-agent: axios/1.13.2`, `content-length` e
   um `traceparent` do próprio axios. **O link é o único segredo** — o que
   valida o modelo de token opaco do relay pra este caminho.
3. **Custom Data — mesmo nível ou aninhado?** **Aninhado**, em `customData`
   (camelCase, ilha no meio do snake_case).

### Divergências com o research

- `contact_id`: previsto como incerto, veio. (corrige a Parte 2)
- `tags` é **string csv**, não array.
- `full_name` existe e não estava no esquema da doc.
- `triggerData`, `contact.attributionSource`, `attributionSource` — três chaves
  não previstas, duas vazias.
- Campos vazios não são uniformemente omitidos (`full_address: ""` veio,
  `phone` não).
- Ausência de assinatura/dedupe: **confirmada por captura**, não mais por
  argumento de ausência na doc.

### Efeito nas decisões fechadas

- **006 (assinatura mínima)**: `first_name` **ou** `location.id` — o payload
  real tem os dois. **A assinatura sobrevive.** Sem ajuste.
- **005 (lista de chaves sem preset)**: **precisa de ajuste.** A normalização
  remove `_`, então `full_name` → `fullname` e `contact_id` → `contactid`, e
  nenhum dos dois está nas listas. Hoje um payload de workflow GHL sem preset
  sai com **título e id vazios**, embora o título óbvio esteja ali. Anotado em
  005: acrescentar `fullname` (e `firstname` depois dele) ao título e
  `contactid` ao id — edição de literal, não redecisão.
- **014 (filtros)**: nada a fazer. Não há data em epoch nem Quill neste payload;
  `date_created` é ISO e é do contato, não do evento.
- **Preset viável?** Sim, restrito ao núcleo de contato. Sem URL no corpo: o
  deep link sai de `location.id` + `contact_id` concatenados no template
  (dois tokens no mesmo campo, que `render()` já suporta).

Limpeza feita na conta: workflow despublicado e excluído, contato de teste e
tag `knobler-captura` removidos.

