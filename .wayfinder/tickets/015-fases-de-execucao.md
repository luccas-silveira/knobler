# Fases de execução: ordem, gates e docs

- map: ../map.md
- label: wayfinder:grilling
- status: closed
- assignee: claude (sessão 2026-08-04)
- blocked-by: — (004, 005, 006, 007, 008, 013, 014 fechados; 009 fora de escopo)

## Question

Todas as decisões de desenho estão tomadas. Falta o plano que vira código.

Decidir:

- **Ordem das fases.** O que é fatiável e entregável sozinho: preset no bundle
  (006) → assistente (004/013) → colar JSON (008) → auto-mapeamento (005) →
  filtros (014, que tocam relay + app). Quais fases dependem de qual, e o que
  precisa ser aditivo no relay antes do app (`lastPayloadAt`/`payloadCount` de
  007, `render()` com filtros de 014).
- **Gates novos em `tools/check.sh`.** Não há XCTest: cada área ganha um
  harness `tools/*check*.swift`. Quais nascem — presets (assinatura mínima bate
  com o exemplo embutido?), auto-mapeamento (005: dica de forma, busca por
  largura, campo preenchido não é sobrescrito), filtros (014, precisa espelhar
  o teste do relay em `relay/test/`). Cuidado com `-parse-as-library` em
  harness escrito como `main.swift`; entrada nova em `tools/check.sh` ou a CI
  não vê.
- **Imagens de `docs/images/` a recapturar.** O painel de webhooks e o editor
  mudam. `settings-webhooks.png` e `mapping-editor.png` são mantidos à mão
  (`Knobler --ajustes=webhooks` + `screencapture -l<id>`, corte 802x554+55+37).
  O assistente é sheet sobre Ajustes: decidir se ganha imagem própria. Estados
  com `TextEditor`/`ScrollView` não saem pelo `tools/snapshot.sh`.
- **Texto de `docs/webhooks.md`.** O que reescrever quando o assistente vira a
  porta única de perfil novo, e onde documentar os três filtros de 014.
- **`CHANGELOG.md` e release.** Uma entrada em `## [Unreleased]` por fase ou
  uma no fim; `./tools/release.sh minor` no fechamento.

Dependência interna: a fase que escreve o **preset do Notion** depende de 011
(capturar payload real) — GHL e ClickUp tiveram a documentação contrariada pela
captura real (010, 012), então o Notion não deve ser escrito só pela doc.

## Resolução (2026-08-04)

### Achado que mudou o desenho dos gates

`relay/test/*.test.js` **nunca rodou na CI**: `tools/check.sh` não tem entrada
de relay e o `ci.yml` só chama `check.sh`. Os testes existem e só rodam à mão
(`npm test` dentro de `relay/`). Como 014 põe os três filtros dentro de
`render()`, isso deixaria a mudança sem gate nenhum.

Fecha assim: entram em `check.sh` só os testes **herméticos** (sem
`better-sqlite3`/`ws`) — `template`, `normalize`, `ratelimit`, `tokens`, via
`run relay-<nome> node --test relay/test/<nome>.test.js`. `db`, `hub` e
`server` seguem fora da CI: exigiriam `npm ci` com build nativo no runner e
`node_modules` instalado pra rodar `check.sh` local. Custo aceito
conscientemente: o `GET /profiles/:id` de 007 fica coberto só por revisão.

### Ordem: relay primeiro, app em fatias

Fase 0 junta tudo do relay porque é aditivo e deployável sozinho, e porque o
app não pode construir contra contrato inexistente (o passo Primeiro envio do
assistente depende de `lastPayloadAt`).

0. **Relay** — `lastPayloadAt` e `payloadCount` em `GET /profiles/:id` (007);
   os três filtros em `render()` (014); testes em `relay/test/`; gates node em
   `check.sh`.
1. **Presets no bundle** (006) — **quatro** caminhos, não cinco (ver Notion).
2. **Assistente** (004/013) — sheet sobre Ajustes, porta única.
3. **Colar JSON** (008).
4. **Auto-mapeamento** (005).
5. **Filtros na prévia do app + docs + CHANGELOG + release.**

### Gates Swift: extrair antes de testar

O motor de prévia do app hoje é função solta dentro de
`MappingEditorView.swift` (~linha 188), arquivo de View com SwiftUI/AppKit —
arrastar isso pra um harness é inviável. Nascem três arquivos puros, um gate
cada:

```
swift_check templatecheck  Knobler/WebhookTemplate.swift tools/templatecheck.swift
swift_check presetcheck    Knobler/WebhookPresets.swift Knobler/WebhookTemplate.swift tools/presetcheck.swift
swift_check automapcheck   Knobler/WebhookAutoMap.swift Knobler/WebhookPresets.swift tools/automapcheck.swift
run relay-template         node --test relay/test/template.test.js
```

`templatecheck` roda **os mesmos casos** de `relay/test/template.test.js`:
espelho explícito, um lado quebra se o outro divergir — e divergir aqui
significa prévia mentindo sobre o card. `presetcheck` valida que a assinatura
mínima de cada preset bate com o exemplo embutido e que a versão é `Int`
monotônico. `automapcheck` cobre dica de forma, busca por largura, profundidade
4, array pelo índice 0 e "campo preenchido nunca é sobrescrito".

### Notion fica de fora do primeiro release

011 segue travado (workspace novo cai em onboarding; automação "Send webhook" é
plano pago). Os presets 006 saem com **quatro** caminhos — GHL Marketplace, GHL
workflow, ClickUp API, ClickUp Automação — todos com captura real por trás
(010, 012). Notion nem aparece no passo Serviço; quem usa Notion cai em "Outro
serviço (sem preset)", o escape já decidido em 013. **Nenhum preset entra no
bundle escrito só pela doc** — é exatamente o que 010 e 012 provaram ser errado.
O preset do Notion vira fase 7, bloqueada por 011.

### Imagens

Três, todas à mão (`Knobler --ajustes=webhooks` + `screencapture -l<id>`, corte
`802x554+55+37`), capturadas numa fase de docs única no fim:

- `settings-webhooks.png` — recapturar: a linha do perfil passa a mostrar
  estado ("Esperando primeiro envio" / "último webhook há 3 min").
- `mapping-editor.png` — recapturar: banner de mapa sugerido, fontes de payload
  como menu, botão de colar.
- `assistente-servico.png` — nova: o passo Serviço é onde preset e ressalvas
  aparecem, o coração de 004/006. O sheet sai junto na captura da janela de
  Ajustes.

### `docs/webhooks.md`

Fica num arquivo só (~90 linhas). "Como usar" passa a começar pelo assistente
como porta única (Nome → Serviço → Link → Primeiro envio → Mapa), dizendo
explicitamente o escape "Outro serviço (sem preset)". Seção nova **Presets**
(o que é, ressalvas por caminho, reaplicar é manual). Seção nova **Filtros no
template** com os três, um exemplo cada e a regra de falha suave.

### CHANGELOG e release

Uma linha em `## [Unreleased]` por fase, conforme desenvolve (regra do
`CLAUDE.md`). No fechamento das seis, um `./tools/release.sh minor`. Fase que
não sair (preset do Notion) simplesmente não tem linha.

### Rastreio

Uma fase = um ticket `wayfinder:task` = uma sessão. Criados 016..022, encadeados
por `blocked-by`. O mapa segue sendo o tracker único; nada de plano paralelo em
`docs/superpowers/specs/`.
