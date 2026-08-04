# Payload de webhook do GoHighLevel

- map: ../map.md
- label: wayfinder:research
- status: closed
- assignee: research subagent (concluído)
- blocked-by: —

## Question

Qual é a forma real do JSON que o GoHighLevel entrega num webhook de saída
(workflow → "Webhook" / Marketplace webhooks)? Precisamos, por tipo de evento
mais usado (contato criado, mensagem recebida, oportunidade mudou de estágio):
caminhos dos campos que virariam título, corpo, URL e ícone; o que é estável
entre eventos e o que varia; se existe campo de id útil pra dedupe.

Saída: `.wayfinder/research/ghl.md` com payloads de exemplo anotados.

## Resolution

Achados completos em [`.wayfinder/research/ghl.md`](../research/ghl.md).

**São dois sistemas incompatíveis**, não um:

- **Webhook de Marketplace/app** — envelope estável, camelCase, `type` no root,
  `webhookId` por entrega (dedupe real; o GHL retenta até 12 vezes).
- **Ação Webhook de workflow** — snake_case, sem `type`, sem assinatura, sem id
  de evento. E o corpo **é customizável**: "Webhook (Outbound)" tem payload
  padrão + Custom Data, e "Custom Webhook" (premium) é editor de raw JSON livre.
  Pior, mesmo o "padrão" varia com o gatilho do workflow.

Consequência dura pro mapa: **preset de forma fixa só é viável pro webhook de
Marketplace**. O de workflow tem que cair no mapeamento configurável — nenhum
preset consegue prever a forma.

Outros achados:

- A doc oficial se contradiz: o Integration Guide mostra envelope aninhado
  (`data: {...}`), mas o payload real do Webhook Logs Dashboard é **plano** e
  traz `webhookId`, `timestamp`, `versionId`, `appId`, que os schemas por evento
  omitem. Os schemas publicados estão incompletos.
- `ContactCreate` vem completo. `OpportunityStageUpdate` traz `pipelineStageId`
  (UUID) e **não** o nome do estágio nem o anterior — exige lookup.
  `InboundMessage` **não traz o nome do contato**, só `contactId`, e tem três
  formatos de `from` (E.164, `Nome <email>`, e `{}` vazio em provider custom).
- Nenhum evento traz avatar.

Lacuna: não existe JSON real capturado publicamente da ação de workflow —
virou ticket.
