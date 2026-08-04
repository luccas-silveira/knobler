# Configurar notificações externas sem tentativa-e-erro

<!-- wayfinder:map -->

## Destination

O fluxo de configuração de um perfil de webhook — criar, obter o link, mapear o
payload, ver o card certo — entregue **implementado no app** (e no relay quando
preciso), com gate em `tools/check.sh`, `docs/webhooks.md` atualizado e entrada
no `CHANGELOG.md`. O cenário âncora é o **primeiro perfil, do zero**: sair de
"liguei a opção" até "o card chegou com título e corpo certos" sem abandonar o
app e sem tentativa-e-erro.

## Notes

- Domínio: macOS, AppKit + SwiftUI, deployment target 14.2. Convenções em `CLAUDE.md`.
- Este mapa **carrega a execução** (override do "plan, don't do"): a última fase
  é implementar, testar e documentar. Até lá, tickets decidem.
- Superfícies: `Knobler/WebhookSettingsView.swift`, `Knobler/MappingEditorView.swift`,
  `Knobler/WebhookClient.swift`, `relay/`.
- Skills por sessão: `superpowers:brainstorming` antes de desenho novo,
  `grill-me` pros tickets de grilling, `superpowers:test-driven-development` e
  os harnesses `tools/*check*.swift` na fase de execução. Sem XCTest.
- Público: dev/power-user (ver `PRODUCT.md`). Painel não pode virar dev-tool denso.
- Presets decididos pelo usuário: **GHL, ClickUp, Notion**.
- Sem tracker remoto configurado — este diretório é o tracker.

## Decisions so far

- Destino é feature entregue no app, não spec — charting, 2026-08-04.
- Relay entra no escopo; mudanças aditivas na API dele são permitidas — charting.
- Cenário âncora: primeiro perfil, do zero — charting.
- Presets entram, restritos a GHL, ClickUp e Notion — charting.
- As quatro fontes de payload pro editor entram todas (espera ao vivo, colar
  JSON, preset com exemplo embutido, histórico dos últimos N) — charting.
- [Fase 0 — relay](tickets/016-fase-relay.md) — implementada: filtros em
  `render()` (lista fechada, falha suave), `lastPayloadAt`/`payloadCount` em
  `GET /profiles/:id` por `ALTER TABLE` solto, e os quatro testes herméticos do
  relay entraram no `tools/check.sh` (nunca tinham rodado na CI). **No ar**:
  deploy por rsync em `/opt/knobler-relay`, `npm test` 48/48 na VPS, colunas
  conferidas no banco de produção e `/health` público ok.
- [Fase 1 — presets no bundle](tickets/017-fase-presets.md) — os quatro caminhos
  em `Knobler/WebhookPresets.swift` (literal Swift, `versao: 1`) e o motor de
  prévia extraído pra `Knobler/WebhookTemplate.swift` com os três filtros de
  014. Gates `presetcheck` e `templatecheck` (31 checks). Dois desvios de 006:
  `mapaFixo`+`dicasDeForma` viraram uma lista só mais a flag
  `mapaAplicavelSemPayload`, e a assinatura passou a ser sempre AND
  (GHL workflow = `location.id` + `workflow.id`). Nada aparece na tela ainda —
  quem usa é o assistente (018).
- [Fase 2 — assistente de passos](tickets/018-fase-assistente.md) — o sheet de
  013 no ar: `Knobler/WebhookAssistantView.swift` (cinco passos, presets no passo
  Serviço, polling de `GET /profiles/:id` a cada 2s no Primeiro envio, editor
  como passo Mapa com os campos semeados pela receita e `_origem` gravada no
  mapping) e `Knobler/WebhookAssistant.swift`, sem SwiftUI, com o passo de
  retomada e a legenda da linha derivados do estado do perfil — gate
  `assistentecheck` (32 checks). A legenda precisa de `lastPayloadAt` por perfil;
  como `GET /profiles` não o devolve, o app faz um `GET /profiles/:id` por linha
  (N+1 anotado no código) em vez de mexer no relay já implantado.
- [Payload de webhook do GoHighLevel](tickets/001-payload-webhook-ghl.md) — são
  dois sistemas: o de Marketplace tem envelope estável e dedupe (`webhookId`); o
  de workflow tem corpo customizável e variável por gatilho, então preset de
  forma fixa só serve pro de Marketplace.
- [Payload de webhook do ClickUp](tickets/002-payload-webhook-clickup.md) — o
  webhook de API não manda o nome da tarefa, só `event`/`task_id`/`history_items`;
  preset útil só pra comentário e mudança de status, ou exige enriquecimento por API.
- [Payload de webhook do Notion](tickets/003-payload-webhook-notion.md) — a
  automação de database serve (propriedades vêm inline, plano pago); os webhooks
  de integração da API não servem (só ids). Não vem URL: o deep link é derivado
  do id, então o preset precisa de transformação, não só de caminhos.
- [Forma da entrada: assistente guiado ou painel incrementado](tickets/004-forma-da-entrada.md)
  — **assistente de passos** (Nome → Serviço → Link → Primeiro envio → Mapa); o
  painel e o sheet ficam como lar de quem já tem perfil e ganham só melhorias
  pequenas (estado na linha, banner de mapa sugerido, fontes de payload como
  menu). Protótipo executável em `.wayfinder/prototypes/`. O conteúdo dos passos
  Serviço e Link **é** o preset: 006 tem que fechar antes de implementá-los.

- [Onde os presets vivem e como versionam](tickets/006-onde-os-presets-vivem.md)
  — preset é **receita no bundle**, em literal Swift, com grão de **caminho**
  (5 caminhos, não 3 serviços: GHL tem dois sistemas incompatíveis, ClickUp dois
  caminhos). Carrega instrução, ressalva, exemplo, **assinatura mínima**, mapa
  fixo só onde as chaves são universais e **dicas de forma** que viram semente do
  auto-mapeamento (005). Payload que não bate com a assinatura: o real vence, o
  mapa sugerido é desligado e o aviso é não-bloqueante — o preset nunca
  sobrescreve payload. Origem fica gravada em `_origem` **dentro do mapping**
  (chave desconhecida é ignorada pelo relay: zero migração); reaplicar é sempre
  manual. Versão = `Int` monotônico por preset; corrigir preset exige release.

- [Transformações no template](tickets/014-transformacoes-no-template.md) — o
  template ganha uma **lista fechada de três filtros** em pt-BR
  (`{{caminho | semHifens}}`, `| data`, `| quill`), um filtro por token, sem
  encadeamento nem argumentos. Roda **no relay** (`render()`, vale pra push e
  pra fila) e é espelhado no motor de prévia do app, que já é duplicado. O
  preset escreve; o usuário pode editar; a árvore clicável continua inserindo
  caminho cru. Filtro desconhecido ou inaplicável devolve o valor cru — falha
  suave. Concatenação com texto fixo já funcionava, então o caso ClickUp/URL
  não precisava de nada.

- [Como a árvore do payload chega ao editor ao vivo](tickets/007-arvore-ao-vivo.md)
  — **polling do `GET /profiles/:id` a cada 2s** enquanto o sheet está aberto e
  visível; nada de canal novo no socket (que é do device, só `type:"notify"`, e
  payload sem mapping nem vira mensagem). Contrato aditivo: `lastPayloadAt` e
  `payloadCount`. `lastPayloadAt` é a chave de "payload novo" pro resto do mapa.

- [Quando o assistente aparece e por onde se sai](tickets/013-quando-o-assistente-aparece.md)
  — **sheet sobre Ajustes**, aberto **sempre** por "Adicionar perfil" (porta
  única; o escape é "Outro serviço (sem preset)" dentro do passo Serviço).
  Fechar no meio deixa o perfil sem mapping, que já é o estado captura-only do
  relay; a retomada é **derivada** desse estado, nunca de um passo persistido.
  Mesmo assistente do segundo perfil em diante.

- [Regras do auto-mapeamento de campos](tickets/005-regras-do-auto-mapeamento.md)
  — **preset primeiro, heurística de fallback, campo a campo**. A dica de forma
  de 006 casa contra a árvore e entrega o template inteiro (com o filtro de 014);
  não casou, cai numa lista fechada de nomes de chave em busca por largura, só
  folhas, array sempre pelo índice 0, profundidade máxima 4, ícone nunca
  chutado. Campo preenchido **nunca** é sobrescrito; roda uma vez por
  `lastPayloadAt` novo; banner não-bloqueante com "Limpar sugestões". Nada casa
  = campos vazios e convite a clicar na árvore.

- [O que a Automação "Call webhook" do ClickUp manda de verdade](tickets/010-payload-da-automacao-do-clickup.md)
  — **manda o nome**: `payload.name`, mais `payload.text_content` (o texto já
  limpo, ao lado do Quill escapado em `payload.content`) e `payload.id` pra URL.
  **O preset de ClickUp por Automação não precisa de enriquecimento por API** —
  o `GET /task/{id}` fica valendo só pro webhook de API. Hierarquia, status e
  responsável vêm só como ids opacos. `date` do envelope é ISO 8601, não epoch.

- [Capturar um POST real da ação Webhook de workflow do GHL](tickets/012-capturar-payload-real-do-workflow-ghl.md)
  — `contact_id` **vem** (o research achava que não dava pra assumir), junto do
  núcleo de contato, `location{}` e `workflow{id,name}`. **Sem assinatura
  nenhuma nos headers**: o link é o único segredo. Custom Data chega **aninhado**
  em `customData`. `tags` é string csv. Preset viável, restrito ao núcleo de
  contato; a URL do contato tem que ser montada com dois tokens.

- [Colar JSON de exemplo](tickets/008-colar-json-de-exemplo.md) — **um clique
  lendo o clipboard**, sem campo de texto (o payload real do ClickUp tem 3 KB:
  ninguém revisa isso num `TextEditor`). JSON inválido vira aviso inline com os
  primeiros ~80 caracteres do que foi lido. O exemplo é **só local** (`@State`,
  some ao fechar): o relay nunca sabe, então `lastPayloadAt`/`payloadCount`
  seguem significando POST de verdade. Faixa persistente marca a árvore como
  exemplo; **payload real vence e troca sozinho**. Colar dispara o
  auto-mapeamento de 005 como se fosse payload novo. Botão no estado vazio do
  editor e no passo Primeiro envio do assistente.

- [Fases de execução: ordem, gates e docs](tickets/015-fases-de-execucao.md) —
  **relay primeiro** (fase 0, aditivo e deployável sozinho), depois app em
  fatias: presets → assistente → colar JSON → auto-mapeamento → filtros na
  prévia + docs + release. Achado: `relay/test/` **nunca rodou na CI** — entram
  em `check.sh` só os testes herméticos (`template`, `normalize`, `ratelimit`,
  `tokens`). O motor de prévia sai de dentro de `MappingEditorView.swift` pra
  três arquivos puros com um gate cada (`templatecheck` espelhando os casos do
  relay, `presetcheck`, `automapcheck`). Presets saem com **quatro** caminhos —
  Notion espera 011, nenhum preset é escrito só pela doc. Três imagens à mão,
  `docs/webhooks.md` num arquivo só, uma linha de CHANGELOG por fase e um
  `release.sh minor` no fim. Fases viram os tickets 016..022.

## Not yet specified

- **Prévia fiel ao card real.** Hoje a prévia é um retângulo `.quinary` com
  `Text` empilhado; não mostra ícone nem som. Reaproveitar a view do card de
  verdade depende de saber se ela renderiza fora da janela do notch.
- **Tokens não resolvidos.** `{{usr.nome}}` com typo renderiza vazio em silêncio.
  Falta decidir como sinalizar sem poluir a prévia. 014 já fixou o lado dos
  filtros (desconhecido ou inaplicável = valor cru), então sobra só o caminho.
- **Sinal de saúde no painel de perfis.** "último webhook há 3 min" em vez de
  "Campos mapeados" — forma já prototipada em 004, e 007 fixou a fonte
  (`lastPayloadAt`/`payloadCount`). Sobra só o texto de cada estado e o limiar
  de "faz tempo demais"; vira ticket junto com a linha de retomada de 013.
- **Descoberta da árvore clicável.** Nada na tela diz que clicar num valor
  insere no campo em foco, nem qual campo está em foco. 005 encostou nisso (o
  banner de "nada casou" convida a clicar), mas só cobre o caso em que o chute
  falha — falta o caso normal.

- **Link do perfil dentro do editor** — resolvido de raspão por 013 (o
  assistente retoma no passo Primeiro envio, que tem o link), mas o editor
  aberto direto num perfil com mapping continua sem ele. Menor do que era.
- **Renomear e duplicar perfil.** `updateProfile` já aceita `name`; a UI não expõe.
- **Campo "ID (dedupe)".** Nome críptico, sem ajuda inline, e o dedupe não existe
  no card. Documentar ou remover.
- **Enriquecimento por API.** Encolheu com a captura de 010: a **Automação** do
  ClickUp manda nome e texto limpo, então esse caminho não precisa de chamada
  extra. Sobram o webhook de **API** do ClickUp (`GET /task/{id}`, que segue sem
  o nome) e o Notion (`GET /pages/{id}`), este ainda por confirmar — 011 não foi
  executado. Continua sendo credencial guardada, rate limit e latência —
  arquitetura nova, não template. Só vira ticket se um caminho que o produto
  precise mesmo ficar dependente disso.
- **Filtro "só notificar se".** Configuração de perfil, mas fora do primeiro
  sucesso; revisitar quando o mapeamento estiver decidido.

## Out of scope

- **Comportamento do card** (botões de ação, atualizar card por `id`, barra de
  progresso, prioridade que fura silêncio). O destino é configurar, não o que o
  card faz; mexe em `NotchViewModel`/fila, não no painel.
- **[Histórico dos últimos N payloads no relay](tickets/009-historico-de-payloads.md)**
  — no cenário âncora ("primeiro perfil, do zero") existe um payload só e o
  último é sempre o certo. Histórico é problema de link maduro com vários tipos
  de evento, e custa esquema novo no banco do relay, retenção e API nova.
- **Entrega e segurança do transporte** (HMAC por perfil, fila no relay quando o
  Mac está offline, roteamento entre múltiplos Macs). Mesma razão: entrega, não
  configuração.
