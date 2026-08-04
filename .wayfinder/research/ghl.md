# Payload de webhook do GoHighLevel — forma real

> Ticket: `.wayfinder/tickets/001-payload-webhook-ghl.md`
> Pesquisa feita em 2026-08-04, offline (skill `ghl-api-docs`, mirror de
> `marketplace.gohighlevel.com/docs`, scrape de 2026-06-30) + busca web nas docs
> de suporte (`help.gohighlevel.com`).

## TL;DR pra quem vai desenhar o preset

1. **Existem DOIS sistemas de webhook de saída completamente diferentes.** Um preset
   não pode tratar os dois como a mesma coisa.
   - **Webhook de Marketplace/app** — envelope padronizado por evento, camelCase,
     `type` no root, `webhookId` e `timestamp` presentes, assinado com
     `X-GHL-Signature`. **Forma fixa e documentada.** É aqui que dá pra fazer preset.
   - **Ação "Webhook" dentro de um workflow** — payload snake_case, sem `type`,
     sem assinatura, **sem id de evento**, e o conteúdo **varia com o gatilho do
     workflow**. Na variante "Custom Webhook" (premium) o corpo é **100%
     escrito pelo usuário**. Preset com forma fixa aqui é impossível.
2. **Dedupe:** só o webhook de Marketplace tem id estável por entrega
   (`webhookId`, UUID). O webhook de workflow **não tem nada** — nem eventId, nem
   executionId, nem timestamp de execução.
3. **Não existe campo de avatar/foto em nenhum dos dois.** Ícone tem que ser
   derivado (iniciais do contato, ou ícone por `type`/canal).

---

## Parte 1 — Webhook de Marketplace / app

### Envelope: FLAT, não aninhado em `data`

⚠️ **Contradição na doc oficial, resolvida.** O "Webhook Integration Guide" mostra
num `curl` de teste um envelope aninhado:

```json
{ "type": "ContactCreate", "timestamp": "...", "webhookId": "test-123",
  "data": { "firstName": "John" } }
```

(fonte: `docs/webhook/WebhookIntegrationGuide.md:92-105`)

**Isso está errado / é só ilustrativo.** O payload real é **plano**: `type`,
metadados e os campos do recurso todos no mesmo nível. Evidência forte — um
payload real copiado do **Webhook Logs Dashboard** do próprio GHL:

```json
{
  "type": "OpportunityCreate",
  "locationId": "3jJ0coeqWCZMAosyGQ6K",
  "versionId": "6878cec452e7c8d29d4dd3d9",
  "appId": "6878cec452e7c8d29d4dd3d9",
  "id": "UHXrFfZGSH5rj7z5rdDP",
  "name": "Test 2",
  "assignedTo": null,
  "contactId": "VQxH1EeoFPg9uhhnCeJx",
  "pipelineId": "WQ7tyljQSXAg7GuTgYdd",
  "pipelineStageId": "403af14e-9afb-40b1-b394-0aa6bbe0cc5e",
  "status": "open",
  "dateAdded": "2025-11-07T12:40:44.510Z",
  "timestamp": "2025-11-07T12:46:45.953Z",
  "webhookId": "881b9415-5d35-4ff1-a667-0545b80b96c0"
}
```

Fonte: `docs/webhook/WebhookLogsDashboard.md:159-176`
(<https://marketplace.gohighlevel.com/docs/webhook/WebhookLogsDashboard>).
**Confiança: alta** — é um payload de log, não um exemplo de schema; e bate com o
que já foi observado ao vivo no projeto blacklist (`req.body.type` no root,
`from`/`to` no root — ver seção "Gotchas" da skill `ghl-api-docs`).

Repare que esse payload real traz **quatro campos que a doc por evento não lista**:
`versionId`, `appId`, `timestamp`, `webhookId`. Ou seja, **as páginas de schema por
evento estão incompletas** — elas descrevem o "miolo", o gateway acrescenta o
envelope. Confirmação independente: `ExternalAuthConnected.md:25` declara
`required: ["type","appId","locationId","companyId","authType","timestamp","webhookId"]`.
**Confiança de que `webhookId`/`timestamp` vêm em todo evento: alta** (dashboard de
logs indexa por `webhookId`; o guia de integração usa `req.body.webhookId` como
chave de dedupe no exemplo canônico, `WebhookIntegrationGuide.md:353-365`).

### Estável entre TODOS os eventos

| Campo | Nota |
|---|---|
| `type` | nome do evento, ex. `"ContactCreate"`, `"InboundMessage"`, `"OpportunityStageUpdate"` |
| `locationId` | subconta. Sempre presente (em eventos de agência vem `companyId`) |
| `webhookId` | **UUID por entrega — a chave de dedupe** |
| `timestamp` | ISO 8601, momento do envio (≠ `dateAdded`, que é do recurso) |
| `versionId` / `appId` | ids do app marketplace que recebe |

### O que VARIA

- **O nome do id do recurso.** Não há um campo `id` universal:
  - `ContactCreate` → `id` é o **contactId**
  - `Opportunity*` → `id` é o **opportunityId** e o contato vem em `contactId`
  - `InboundMessage` → **não tem `id`**; tem `messageId` (e nem sempre — ver abaixo),
    `conversationId`, `contactId`
- **Praticamente todo o resto.** Cada evento tem seu próprio conjunto de chaves.
  Não existe sub-objeto comum tipo `contact: {...}`.
- Naming: **camelCase** (`firstName`, `pipelineStageId`).

### Assinatura, entrega, retry

- Header atual **`X-GHL-Signature`** (Ed25519, base64 sobre o corpo bruto).
  Legado `X-WH-Signature` (RSA-SHA256) **deprecado em 2026-07-01** — já passou.
  Chaves públicas em `docs/webhook/WebhookIntegrationGuide.md:198-227`.
- Qualquer resposta **não-2xx** = falha → até **12 retentativas** com backoff
  exponencial + jitter (`WebhookIntegrationGuide.md:398-428`). Ou seja:
  **o mesmo `webhookId` pode chegar várias vezes** — dedupe não é otimização, é
  requisito.
- Sempre responder 200 e processar async.

---

### Evento: contato criado (`ContactCreate`)

Exemplo da doc oficial (`docs/webhook/ContactCreate.md:104-136`,
<https://marketplace.gohighlevel.com/docs/webhook/ContactCreate>), **acrescido do
envelope real** (`webhookId`/`timestamp`/`versionId`/`appId`) — marcado abaixo,
porque a página do evento omite:

```jsonc
{
  "type": "ContactCreate",
  "locationId": "ve9EPM428h8vShlRW1KT",
  "id": "nmFmQEsNgz6AVpgLVUJ0",   // ← contactId
  "address1": "3535 1st St N",
  "city": "ruDolomitebika",
  "state": "AL",
  "companyName": "Loram ipsum",
  "country": "DE",
  "source": "xyz form",           // origem: útil como subtítulo
  "dateAdded": "2021-11-26T12:41:02.193Z",
  "dateOfBirth": "2000-01-05T00:00:00.000Z",
  "dnd": true,
  "email": "JohnDeo@gmail.comm",
  "name": "John Deo",             // nome completo já montado
  "firstName": "John",
  "lastName": "Deo",
  "phone": "+919509597501",
  "phoneLabel": "Mobile",
  "postalCode": "452001",
  "tags": ["id magna sed Lorem", "Duis dolor commodo aliqua"],
  "website": "https://www.google.com/",
  "attachments": [],
  "assignedTo": "nmFmQEsNgz6AVpgLVUJ0",   // userId, não contactId
  "customFields": [ { "id": "BcdmQEsNgz6AVpgLVUJ0", "value": "XYZ Corp" } ]

  // + no payload REAL, não listado nessa página:
  // "webhookId": "<uuid>", "timestamp": "<iso>", "versionId": "...", "appId": "..."
}
```

**Atenção:** quase todo campo aqui é opcional. Um contato criado por SMS entrante
chega com `phone` e mais nada de nome. Um preset **precisa** de fallback em cadeia.

Mapeamento pro card:

| Slot do card | Caminho | Fallback |
|---|---|---|
| Título | `name` | `firstName + " " + lastName` → `email` → `phone` → `"Contato sem nome"` |
| Corpo | `source` ("via xyz form") | `email` → `phone` → `tags.join(", ")` |
| URL | `https://app.gohighlevel.com/v2/location/{locationId}/contacts/detail/{id}` | — |
| Ícone | **não existe** campo de foto | iniciais de `name`, ou ícone genérico "pessoa" |
| Dedupe | `webhookId` | — |

⚠️ O formato da URL (`/v2/location/{id}/contacts/detail/{contactId}`) **não está em
nenhuma doc do mirror** — é o padrão observado da UI e o prefixo `/v2/location/{id}/…`
está confirmado nas notas de Custom Pages da skill. **Confiança: média. Verificar
abrindo um contato no painel antes de codar.** Em conta whitelabel o host muda
(ex. `app.zoitech.com.br`) — o preset provavelmente precisa de um campo "domínio do
painel" configurável.

---

### Evento: mensagem recebida (`InboundMessage`)

Este é o **menos estável dos três**, porque o mesmo `type` cobre 8 canais
(Call, Voicemail, SMS, GMB, FB, IG, Email, Live Chat) com schemas diferentes.
Fonte: `docs/webhook/InboundMessage.md`,
<https://marketplace.gohighlevel.com/docs/webhook/InboundMessage>.

SMS (exemplo oficial, `InboundMessage.md:95-115`):

```jsonc
{
  "type": "InboundMessage",
  "locationId": "l1C08ntBrFjLS0elLIYU",
  "attachments": [],
  "body": "This is a test message",       // ← o texto
  "contactId": "cI08i1Bls3iTB9bKgFJh",
  "contentType": "text/plain",
  "conversationId": "fcanlLgpbQgQhderivVs",
  "dateAdded": "2021-04-21T11:31:45.750Z",
  "direction": "inbound",
  "messageType": "SMS",
  "status": "delivered",
  "conversationProviderId": "cI08i1Bls3iTB9bKgF01",
  "chatWidgetId": "67b0cc8cf14b19d85ace7s35",
  "from": "+15551234567",
  "to": "+15559876543",
  "messageTypeId": 2,
  "messageTypeString": "TYPE_SMS"
  // sem "messageId" nesse exemplo (!) — ver aviso abaixo
}
```

Chamada (`InboundMessage.md:119-139`) — **sem `body`**, o conteúdo é gravação:

```jsonc
{
  "type": "InboundMessage",
  "locationId": "0d48aEf7q67DAu134bpy",
  "attachments": ["call recording url"],  // ← única "carga" da chamada
  "contactId": "gblakL5aYQC4glDtP1r2t3",
  "conversationId": "SGDqZrzmwTr19d10aHkt9F",
  "dateAdded": "2024-05-08T11:57:42.250Z",
  "direction": "inbound",
  "messageType": "CALL",
  "userId": "xsmF1xxhmC92ZpL1lj7aLa",
  "messageId": "tyW42xCD0HQpb3hhfLcx",
  "status": "completed",
  "callDuration": 120,
  "callStatus": "completed",
  "from": "+15551234567", "to": "+15559876543",
  "messageTypeId": 1, "messageTypeString": "TYPE_CALL"
}
```

Voicemail: idêntico à chamada, mas `status: "voicemail"`, `messageTypeId: 10`,
`messageTypeString: "TYPE_VOICEMAIL"`, sem `callDuration`.

Email (`InboundMessage.md:247-266`) — schema **diferente**:

```jsonc
{
  "type": "InboundMessage",
  "locationId": "kF4NJ5gzRyQF2gKFD34G",
  "body": "<div style=\"...\">Testing Email Notification</div>",  // ← HTML!
  "contactId": "3bN9f8LYJFG8F232XMUbfq",
  "conversationId": "yCdNo6pwyTLYKgg6V2gj",
  "dateAdded": "2024-01-12T12:59:04.045Z",
  "direction": "inbound",
  "messageType": "Email",
  "emailMessageId": "sddfDSF3G56GHG",     // id próprio, não messageId
  "from": "Internal Notify <sample@email.service>",  // NÃO é E.164 nem e-mail cru
  "threadId": "sddfDSF3G56GHG",
  "subject": "Order Confirmed",           // só existe em Email
  "to": "testprasath95@gmail.com",
  "ccList": ["cc@example.com"], "bccList": ["bcc@example.com"],
  "conversationProviderId": "cI08i1Bls3iTB9bKgF01"
}
```

**Armadilhas confirmadas ao vivo** (não estão na doc; fonte: notas "Gotchas" da
skill `ghl-api-docs`, testadas contra a API real em 2026-07 no projeto blacklist —
**confiança alta**):

- Em **Conversation Provider custom**, `messageType` é `"Custom"` e
  **`from`/`to` chegam como `{}` (dicts vazios)** — não são strings. Um parser que
  assume `String` quebra. Pra ter o telefone, resolver via
  `GET /contacts/{contactId}` (o `contactId` sempre vem).
- Push do canal custom chega sem preview de texto.

O que é estável dentro de `InboundMessage`: `type`, `locationId`, `contactId`,
`conversationId`, `dateAdded`, `direction`, `messageType`.
O que varia: **`body` (ausente em CALL), `messageId` (ausente no exemplo de SMS),
`subject` (só Email), `from`/`to` (string E.164 | "Nome <email>" | `{}`),
`callDuration`/`callStatus` (só CALL), `emailMessageId`/`threadId` (só Email).**

Mapeamento pro card:

| Slot | Caminho | Observação |
|---|---|---|
| Título | **não vem no payload** — só `contactId` | ⚠️ precisa de `GET /contacts/{contactId}` pra ter nome. Fallback: `from` quando for string; senão "Nova mensagem" |
| Corpo | `body` | Email: **é HTML**, precisa stripar tags. CALL: usar `"Chamada · {callDuration}s"`; voicemail: `"Recado de voz"` |
| Subtítulo/canal | `messageType` | mapear pra rótulo pt-BR |
| URL | `https://app.gohighlevel.com/v2/location/{locationId}/conversations/{conversationId}` | mesma ressalva de confiança média |
| Ícone | derivar de `messageType` (SMS/Email/WhatsApp/IG/FB/Call) | não há avatar |
| Dedupe | `webhookId` (envelope) | **não** use `messageId`: nem sempre vem |

---

### Evento: oportunidade mudou de estágio (`OpportunityStageUpdate`)

Exemplo oficial (`docs/webhook/OpportunityStageUpdate.md:57-72`,
<https://marketplace.gohighlevel.com/docs/webhook/OpportunityStageUpdate>):

```jsonc
{
  "type": "OpportunityStageUpdate",
  "locationId": "ve9EPM428h8vShlRW1KT",
  "id": "wWhVuzqpRuOA1ZVWi4FC",          // ← opportunityId
  "assignedTo": "bNl8QNGXhIQJLv8eeASQ",  // userId
  "contactId": "cJAWDskpkJHbRbhAT7bs",
  "monetaryValue": 40,
  "name": "Loram ipsu",                  // ← nome da OPORTUNIDADE, não do contato
  "pipelineId": "VDm7RPYC2GLUvdpKmBfC",
  "pipelineStageId": "e93ba61a-53b3-45e7-985a-c7732dbcdb69",
  "source": "Loram ipsu",
  "status": "open",
  "dateAdded": "2021-11-26T12:41:02.193Z"
}
```

🚨 **A pior notícia pro card:** o payload traz **`pipelineStageId` (um UUID), não o
nome do estágio**. Nem o nome do pipeline. E **não traz o estágio anterior** — não
dá pra escrever "Lead → Proposta" só com o webhook. Confiança: alta (o schema
completo tem 11 campos e nenhum é nome de estágio).

Pra virar texto humano é obrigatório resolver `pipelineId`/`pipelineStageId` via
`GET /opportunities/pipelines?locationId=…` (e cachear — os pipelines mudam pouco).
Mesma história do contato: `name` é da oportunidade, o nome da pessoa exige
`GET /contacts/{contactId}`.

`OpportunityStatusUpdate` (open/won/lost/abandoned) e
`OpportunityMonetaryValueUpdate` têm **exatamente o mesmo schema** — só o `type`
muda. Isso é bom: um único parser cobre a família `Opportunity*`.

| Slot | Caminho | Observação |
|---|---|---|
| Título | `name` | nome da oportunidade |
| Corpo | estágio resolvido a partir de `pipelineStageId` + `monetaryValue` + `status` | precisa de lookup na API |
| URL | `https://app.gohighlevel.com/v2/location/{locationId}/opportunities/list` | ⚠️ **não achei deep-link pra uma oportunidade específica**; confiança baixa |
| Ícone | genérico de funil / por `status` | — |
| Dedupe | `webhookId` | `id` é estável mas repete a cada mudança de estágio — **não serve sozinho** |

---

## Parte 2 — Ação "Webhook" dentro de um workflow

Fonte: docs de suporte GHL, buscadas na web (não estão no mirror do marketplace).
São **duas ações distintas**:

| | **Webhook (Outbound)** — grátis | **Custom Webhook** — Premium Action |
|---|---|---|
| Corpo | **fixo** (payload padrão grande) + seção `Custom Data` opcional (key/value) | **totalmente escrito pelo usuário** (raw JSON / form / key-value) |
| Método | POST | GET/POST/PUT/DELETE |
| Headers / query params | não configuráveis | sim |
| Auth | nenhuma | Bearer / API Key / Basic / OAuth2 / custom header |
| Custo | grátis | consome execução premium |

Fontes:
<https://help.gohighlevel.com/support/solutions/articles/155000003299-workflow-action-webhook-outbound-> (atualizada 2026-03-16)
e <https://help.gohighlevel.com/support/solutions/articles/155000003305-actions-custom-webhook> (2025-12-11).
**Confiança: alta** (verbatim da doc oficial).

### Resposta direta à pergunta do ticket

> "se o corpo do webhook de workflow é customizável pelo usuário (isso muda tudo:
> se for, um preset não pode assumir forma fixa)"

**Sim, é customizável — e pior do que só isso.** Três eixos de variação:

1. Na **Custom Webhook**, o corpo é literalmente um editor de JSON livre. **Zero**
   garantia de forma. Um preset aqui só pode ser "mapeamento configurável pelo
   usuário" (JSONPath escolhido na UI do Knobler), nunca forma fixa.
2. Mesmo na **Webhook (Outbound)** "fixa", o conteúdo **depende do gatilho do
   workflow**: a doc diz explicitamente que campos de contato e `location` vêm
   sempre, mas `opportunity`, `calendar`, `task`, `note`, `message`, `order`,
   `invoice` só aparecem se o trigger for daquele objeto. Um workflow com trigger
   "Tag Added" manda **só dados de contato**.
3. A seção **Custom Data** deixa o usuário injetar chaves arbitrárias.

Esquema do payload padrão da Webhook (Outbound), transcrito da doc oficial
(é **pseudo-JSON com comentários, sem valores — a doc não publica um exemplo real**;
os typos `pipleline_stage` e `appoinmentStatus` são do original):

```jsonc
{
  // campos de contato, no ROOT, em snake_case
  first_name, last_name, full_name, email, phone, tags,
  address1, city, state, country, timezone, date_created,
  postal_code, company_name, website, date_of_birth,
  contact_source, full_address, contact_type, gclid,
  ...campos personalizados do contato...

  location: { name, address, city, state, country, postalCode, fullAddress, id },  // ~sempre
  // oportunidade, se aplicável — no ROOT, não aninhada:
  opportunity_name, status, lead_value, opportunity_source, source,
  pipleline_stage, pipeline_id, id, pipeline_name,
  campaign: { id, name },
  user: { firstName, lastName, email, phone, ... },
  calendar: { id, calendarName, title, appointmentId, startTime, endTime, status, ... },
  order: { ... }, invoice: { ... },
  task: { title, body, dueDate },
  note: { body },
  message: { type, body, direction, status },
  workflow: { id, name }
}
```

Observações críticas:

- **snake_case no root** (`first_name`), enquanto Marketplace usa camelCase
  (`firstName`). Parser diferente. Confiança: alta.
- **Sem `type`.** Não dá pra saber que evento é olhando o corpo — só pelo
  `workflow.name`, que é texto livre escrito pelo usuário.
- **Sem `webhookId`, sem `timestamp` de execução, sem eventId.**
  → **Não existe dedupe confiável para o webhook de workflow.** Confiança: alta
  quanto à ausência na doc; média como fato absoluto (não capturei um payload real).
  Melhor mitigação: dedupe do lado do Knobler por hash do corpo + janela de tempo,
  ou exigir Custom Webhook com um campo de idempotência montado à mão.
- **Sem assinatura.** Nem `X-GHL-Signature` nem nada. `X-GHL-Signature` é
  **exclusivo** dos webhooks de Marketplace. Autenticação, se houver, é a que o
  usuário configurar na Custom Webhook (header/Bearer). Confiança: alta, mas é
  argumento por ausência na doc.
- `contact_id` **não aparece no schema oficial** (o único `id` do schema está no
  bloco de oportunidade), apesar de muita gente afirmar que vem. **Confiança baixa
  — não assumir.**

### Lacuna conhecida

Não existe, publicamente, **nenhum JSON real capturado** da ação Webhook de
workflow (procurado em webhook.site/Make/n8n/fóruns; só se acha a doc e paráfrases
dela). O esquema acima é da doc, não de captura.

**Como fechar essa lacuna em ~5 min, se valer a pena:** criar um workflow numa
subconta de teste, ação Webhook (Outbound) apontando pra um endpoint
`https://webhook.site/...`, rodar `Test Workflow`. Isso resolve de uma vez:
o JSON real com valores, a presença ou não de `contact_id`, o formato do bloco
`Custom Data`, e os headers (fechando a questão da assinatura). A própria doc
recomenda esse caminho e admite que os Execution Logs **não** mostram o payload.

---

## Recomendação pro preset do Knobler

- **Preset "GoHighLevel" de forma fixa: só para webhooks de Marketplace/app.**
  Chave `type` como discriminador, `webhookId` pra dedupe, mapeamento por evento.
  Vale a pena — é o caso estável e documentado.
- **Webhook de workflow: tratar como "webhook genérico"**, com mapeamento de campos
  configurável pelo usuário. Assumir forma fixa vai quebrar no primeiro cliente que
  usar Custom Webhook ou um trigger diferente.
- Três eventos, três níveis de trabalho extra:
  `ContactCreate` já vem completo; `OpportunityStageUpdate` **exige** lookup de
  pipeline pra virar texto legível; `InboundMessage` **exige** lookup de contato
  pro título e tem 3 formatos de `from` (incluindo `{}`).
- Nenhum evento traz avatar. Ícone = derivado.
- Retry até 12x ⇒ dedupe por `webhookId` não é opcional.

## Fontes

Mirror offline (skill `ghl-api-docs`, `~/.claude/skills/ghl-api-docs/docs/`):
- `webhook/WebhookLogsDashboard.md:159-176` — **payload real capturado** (OpportunityCreate)
- `webhook/WebhookIntegrationGuide.md` — envelope, assinatura, retry, dedupe
- `webhook/ContactCreate.md`, `webhook/InboundMessage.md`, `webhook/OpportunityStageUpdate.md`
- `webhook/ExternalAuthConnected.md:25` — campos required do envelope
- `SKILL.md` seção "Gotchas verificados ao vivo" — `from`/`to` como `{}` etc.

Web:
- <https://help.gohighlevel.com/support/solutions/articles/155000003299-workflow-action-webhook-outbound->
- <https://help.gohighlevel.com/support/solutions/articles/155000003305-actions-custom-webhook>
- <https://help.gohighlevel.com/support/solutions/articles/48001238167-guide-to-custom-webhook-workflow-action>
- <https://marketplace.gohighlevel.com/docs/webhook/WebhookIntegrationGuide>

---

## Parte 3 — Payload REAL da ação Webhook (Outbound) de workflow — capturado 2026-08-04

Preenche a "Lacuna conhecida" da Parte 2. Captura própria (ticket 012):
location `adriN's Playground` (`t9Ww7bY1xJJ6ThFHZVPC`), workflow do zero,
gatilho **Tag de contato** sem filtro, ação **Webhook** (a grátis, não a
Custom), Custom Data com um par `origem_knobler: captura-012`, coletor
webhook.site. Disparo: tag `knobler-captura` aplicada num contato criado na
hora, com nome/sobrenome/e-mail e nada mais.

Corpo, verbatim:

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

Headers recebidos (todos):

```
content-type: application/json
accept: application/json, text/plain, */*
accept-encoding: gzip, compress, deflate, br
user-agent: axios/1.13.2
content-length: 867
traceparent: 00-c5c35f92b33e5f75e6814720ff6ad355-88a13a743cb4e1bb-01
```

### O que a captura confirma e o que corrige

| Afirmação da Parte 2 | Veredito real |
|---|---|
| snake_case no root | **confirmado** (`first_name`, `date_created`, `contact_type`) |
| sem `type` | **confirmado** — só `workflow.name`, texto livre |
| sem `webhookId`/timestamp de execução/eventId | **confirmado** — não há dedupe |
| sem assinatura | **confirmado** — nenhum header de auth; o link é o único segredo. `traceparent` é do axios, não idempotência |
| trigger de tag manda só dados de contato | **confirmado** — zero blocos `opportunity`/`calendar`/`task` |
| `location: {…}` sempre presente | **confirmado**, com `id` |
| `contact_id` "confiança baixa, não assumir" | **CORRIGIDO: vem, e é o primeiro campo.** Sobe pra **alta** |
| Custom Data — nível? | **aninhado em `customData`** (camelCase, ilha no meio do snake_case) |

Descobertas novas, fora do esquema da doc:

- **`tags` é STRING csv**, não array (uma tag = `"knobler-captura"`; múltiplas
  presumivelmente separadas por vírgula — não testado com duas).
- **`full_name`** existe no root — não está no esquema transcrito da doc.
- **`triggerData: {}`** — vazio no gatilho de tag; provável portador do que
  disparou em outros gatilhos. Não confiável.
- **`contact.attributionSource` / `lastAttributionSource`** e um
  **`attributionSource: {}` de root** — três chaves de atribuição, duas vazias.
- **Campos vazios não são todos omitidos**: `full_address: ""` veio; `phone`,
  `address1`, `city` (do contato) não vieram. Omissão é por campo, não regra.
- `date_created` é a criação **do contato**, não da execução. Não serve de
  carimbo do evento.

### Consequência pro preset

Preset de "GHL workflow" é viável **para o núcleo de contato**: `full_name`,
`first_name`, `email`, `tags`, `contact_id` e `location.*` são estáveis e vêm
sempre. O que não dá é assumir qualquer coisa além disso — o resto varia com o
gatilho, exatamente como a Parte 2 previu. Sem URL de contato no corpo: o deep
link teria que ser derivado de `location.id` + `contact_id`
(`https://app.gohighlevel.com/v2/location/<location.id>/contacts/detail/<contact_id>`),
o que é concatenação de dois caminhos — hoje o template só concatena texto fixo
com **um** token por vez, mas dois tokens no mesmo campo já funcionam
(`render()` substitui todos), então isso é template, não arquitetura nova.
