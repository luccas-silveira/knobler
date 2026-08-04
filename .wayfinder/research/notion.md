# Pesquisa — payload de webhook do Notion

- ticket: ../tickets/003-payload-webhook-notion.md
- data: 2026-08-04
- veredito: **o Notion serve, mas só por um dos dois caminhos** — a automação de
  database ("Send webhook"). O webhook de integração da API **não** serve
  sozinho.

## Resposta curta

Sim, o Notion faz POST num link arbitrário nosso. Existem **dois** mecanismos
distintos e eles não têm nada a ver um com o outro:

| | Automação de database ("Send webhook") | Webhook de integração (API) |
|---|---|---|
| Quem configura | usuário, na UI do Notion | dev, no painel de integrações |
| Plano | **qualquer plano pago** (Plus+); free não tem | grátis (é API) |
| Dispara em | mudanças da database escolhida / clique de botão | 26 tipos de evento do workspace |
| Corpo | JSON fixo, mas **com seleção de quais propriedades entram** | JSON fixo, esparso |
| Valores de propriedade | **inline** (as que você escolher) | **não** — só id/uuid |
| Serve pro card sem intermediário | **sim** | **não** (exige chamada extra à API) |

## Caminho A — automação de database (o que serve)

Onde: database → menu de automações → ação "Send webhook". Também disponível em
botões e botões de database.

Fatos confirmados na doc oficial (`notion.com/help/webhook-actions`):

- "Webhook actions are available to users on **paid plans**" — em automações de
  botão, botão de database e automação de database. Free não tem. (alta confiança)
- **Só POST.** Nenhum outro método. (alta)
- **Headers customizáveis** por par chave/valor — dá pra mandar o token do
  perfil do relay num header, sem depender de query string. (alta)
- Máx. **5 ações de webhook por automação**. (alta)
- **Não dá pra editar o corpo bruto**: o JSON é gerado pelo Notion. O que é
  customizável é *quais propriedades da página* entram nele. (alta)
- Só **propriedades da página de database** — conteúdo/blocos da página **não**
  são enviados. Em botão de database não dá pra selecionar propriedades. (alta)
- Não há preview do payload na UI; a própria doc manda usar webhook.site pra
  descobrir a forma. (alta)

O que sempre vem, mesmo sem escolher nada (fonte: matthiasfrank.de, guia mais
detalhado que a doc oficial neste ponto — **confiança média-alta**, não
verificado contra um POST real):

- id da entrada que disparou;
- metadados de sistema: `created_time`, `created_by`, `last_edited_time`,
  **`icon`**, `cover`, `parent`, `properties`;
- rastreio da automação: automation id, action id, event id, número da tentativa.

Mais as propriedades que o usuário marcar no setup, **com valor inline**.

### Forma do JSON — confiança média

Não achei em fonte primária um exemplo literal do corpo da automação (a doc da
Notion não publica um; os guias de terceiros descrevem os campos mas não colam
o JSON). O consenso das fontes e o formato de acesso citado
(`.properties.Title.title[0].text.content`, `.properties.Status.select.name`)
indicam que as propriedades vêm no **mesmo formato de objeto de propriedade da
API do Notion**, não achatadas em string. Ou seja, o mapeamento tem que descer
por dentro do tipo:

| Campo do card | Caminho provável | Observação |
|---|---|---|
| título | `data.properties.<Nome>.title[0].plain_text` | fallback `...title[0].text.content` |
| corpo | `data.properties.<Nome>.rich_text[0].plain_text` | conteúdo de bloco **não vem** |
| status/etiqueta | `data.properties.<Nome>.select.name` | `multi_select` é array |
| data | `data.properties.<Nome>.date.start` | |
| ícone | `data.icon.emoji` ou `data.icon.external.url` | pode ser `null` |
| URL de abrir | **não vem pronto** | ver abaixo |

**Antes de codar o preset, capture um POST real em webhook.site** e cole o JSON
— o ticket 008 ("colar JSON de exemplo") existe justamente pra isso, e o preset
do Notion depende dessa captura pra fixar os nomes de chave de nível 1
(`data`/`source` vs. outro envelope). Este é o único buraco desta pesquisa.

### URL de abrir

Nenhuma fonte lista uma `url` no payload da automação — só o id da entrada. O
deep link é **derivável**: `notion://www.notion.so/<id sem hífens>` (ou
`https://www.notion.so/<id sem hífens>`, que o app captura). Isso significa que
o preset do Notion precisa de uma **transformação**, não só de um caminho de
campo — diferente de GHL/ClickUp. Alternativa sem código: instruir o usuário a
criar uma propriedade fórmula na database com `link` da página e incluí-la no
webhook. (confiança média-alta na derivação; o formato de link do Notion é
estável há anos)

## Caminho B — webhooks de integração da API (o que **não** serve)

Fonte primária: `developers.notion.com/reference/webhooks-events-delivery`.

- 26 tipos de evento: `page.created`, `page.properties_updated`,
  `page.content_updated`, `page.moved/deleted/undeleted/locked/unlocked`,
  `database.*`, `data_source.*` (novos na versão 2025-09-03), `comment.*`.
- Envelope: `id`, `timestamp`, `workspace_id`, `workspace_name`,
  `subscription_id`, `integration_id`, `type`, `authors[]`, `accessible_by[]`,
  `attempt_number` (1–8), `entity {id, type}`, `data {...}`.
- Exemplo real de `page.content_updated` (via Hookdeck): `data` traz
  `updated_blocks[]` (só ids) e `parent` (só id).
- A doc é explícita: **"The events themselves do not contain the full content
  that changed"** — payload esparso, só metadados e ids.
- Exige handshake de verificação (`verification_token`) na criação da inscrição.

Consequência pro Knobler: um evento desses vira um card
**"page 0ef104cd… mudou"**. Pra virar "Revisar contrato — Em progresso" é
preciso um `GET /v1/pages/{id}` autenticado com o token da integração — ou seja,
**cliente da API do Notion dentro do app/relay**, com OAuth ou token colado.
Isso é uma integração, não um preset de mapeamento. Fora do escopo do mapa.

## Recomendação

1. **Manter o preset do Notion**, mirando **exclusivamente** a automação de
   database. Descrever isso no preset ("requer plano pago do Notion").
2. **Não** implementar os webhooks de integração da API — payload inútil sem
   chamada extra autenticada; é outra feature.
3. Bloqueio: o preset não pode ser escrito com precisão sem **um POST real
   capturado**. Passo mais barato: criar uma database de teste, apontar a
   automação pro webhook.site (ou direto pro link do perfil, se o histórico de
   payloads do ticket 009 já existir), e colar o JSON.
4. Anotar a pegadinha da URL: o Notion não manda link; ou derivamos do id, ou o
   preset instrui uma propriedade fórmula. Decisão de desenho, não de pesquisa.

## Confiança

- **Alta**: existência das duas vias; exigência de plano pago; só POST; headers
  customizáveis; corpo não editável, só seleção de propriedades; conteúdo de
  bloco fora; payload da API é só id.
- **Média-alta**: lista dos metadados sempre incluídos (icon/cover/parent/…);
  derivação da URL a partir do id.
- **Média**: nomes exatos das chaves de topo e o formato de objeto de
  propriedade no corpo da automação. **Precisa de captura real.**

## Fontes

- [Notion — Use webhook actions in automations](https://www.notion.com/help/webhook-actions) (primária)
- [Notion — Database automations](https://www.notion.com/help/database-automations) (primária)
- [Notion Developers — Webhooks: events & delivery](https://developers.notion.com/reference/webhooks-events-delivery) (primária)
- [Hookdeck — Guide to Notion Webhooks](https://hookdeck.com/webhooks/platforms/guide-to-notion-webhooks-features-and-best-practices) (exemplo de payload da API)
- [Matthias Frank — How to set up Notion Webhooks](https://matthiasfrank.de/en/notion-webhooks/) (campos do payload da automação)
- [NoteForms — A Simple Guide to Notion Webhooks](https://noteforms.com/resources/notion-webhooks)
