# Payload de webhook do Notion

- map: ../map.md
- label: wayfinder:research
- status: closed
- assignee: research subagent (concluído)
- blocked-by: —

## Question

O Notion consegue fazer POST num link nosso? Investigar as automações de
database (ação "Send webhook") e os webhooks de integração: qual é o JSON
entregue, se dá pra customizar o corpo, e se propriedades da página vêm
inline ou só como id. Se o Notion não conseguir mandar um payload útil sem
uma integração intermediária, isso é resposta válida — e provavelmente tira
o preset do Notion do mapa.

Saída: `.wayfinder/research/notion.md`.

## Resolution

Achados completos em [`.wayfinder/research/notion.md`](../research/notion.md).

O preset do Notion **fica**, mas só por uma das duas vias:

- **Automação de database ("Send webhook") — serve.** Plano pago (Plus+), só
  POST, headers customizáveis (dá pra mandar o token do perfil), corpo não
  editável mas com **seleção de quais propriedades entram**, e elas vêm inline
  com valor. Sempre vêm também `icon`, `cover`, `parent`, `created_time`/`by`,
  `last_edited_time`. Conteúdo de bloco nunca vem.
- **Webhooks de integração da API — não serve.** A doc é explícita: os eventos
  não carregam o conteúdo que mudou, só `entity: {id, type}` e ids. Viraria um
  card "page 0ef104cd… mudou". Título legível exigiria `GET /v1/pages/{id}`
  autenticado — cliente OAuth dentro do app/relay, outra feature.

Dois pontos que mudam o desenho:

1. **Não vem URL de abrir**, só o id. O deep link tem que ser *derivado*
   (`notion://www.notion.so/<id sem hífens>`). O preset do Notion precisa de uma
   **transformação**, não só caminhos de campo — diferente de GHL e ClickUp.
   Alternativa sem código: instruir uma propriedade fórmula `link()` na database.
2. Não existe fonte primária com o JSON literal da automação; os nomes das
   chaves de topo e o formato das propriedades estão em **confiança média**.
   Precisa de um POST real capturado antes de escrever o preset — virou ticket.
