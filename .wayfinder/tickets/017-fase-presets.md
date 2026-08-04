# Fase 1 — presets no bundle (quatro caminhos)

- map: ../map.md
- label: wayfinder:task
- status: closed
- assignee: claude (sessão 2026-08-04)
- blocked-by: 016

## Question

`Knobler/WebhookPresets.swift`: as receitas de 006 em literal Swift, com grão de
**caminho**, não de serviço. **Quatro**, não cinco — o Notion sai só depois de
011 (ver ticket 022):

1. GHL Marketplace, 2. GHL workflow (012), 3. ClickUp API, 4. ClickUp Automação (010).

Cada uma carrega instrução, ressalva, exemplo **podado** (o payload real da
Automação do ClickUp tem ~3 KB e ~25 chaves de ruído), assinatura mínima, mapa
fixo só onde as chaves são universais, dicas de forma (semente de 005) e versão
`Int` monotônica. Origem gravada em `_origem` dentro do mapping.

Junto, extrair `Knobler/WebhookTemplate.swift` — `render` + os três filtros de
014 — de dentro de `MappingEditorView.swift` (~linha 188), sem SwiftUI.

Gates: `presetcheck` (assinatura mínima bate com o exemplo embutido; versão
monotônica; caminhos do mapa fixo existem no exemplo) e `templatecheck` (os
**mesmos casos** de `relay/test/template.test.js` — espelho explícito).

## Resolução (2026-08-04)

- `Knobler/WebhookTemplate.swift`: `JSONValue` (+ `parse`), `resolve`,
  `node(at:)`, `renderTemplate` e `TemplateFilters` (lista fechada de 014),
  extraídos de `MappingEditorView.swift`. Sem SwiftUI — o gate compila só ele.
  Espelha `relay/src/template.js` até no detalhe de `split('|')` sem limite
  (token com dois pipes usa o primeiro filtro e ignora o resto).
- `Knobler/WebhookPresets.swift`: os quatro caminhos em literal Swift
  (`ghl-marketplace`, `ghl-workflow`, `clickup-api`, `clickup-automacao`), com
  instrução, ressalva, assinatura mínima, dicas por campo, exemplo podado e
  `versao: 1`. `WebhookPresets.reconhece(_:)` devolve o primeiro cuja assinatura
  casa com o payload, ou `nil`.
- Gates novos em `tools/check.sh`: `templatecheck` (espelho explícito dos casos
  de `relay/test/template.test.js` + dois tokens no mesmo campo) e `presetcheck`
  (assinatura reconhece o próprio exemplo, caminho citado existe no exemplo,
  mapa não renderiza vazio, filtros dentro da lista fechada, assinaturas não
  colidem entre caminhos). `./tools/check.sh` = **31 checks ok** (era 29).
  Verificado que o `presetcheck` morde: mutar um caminho e uma assinatura
  produziu 4 falhas.
- `tools/snapshot.sh` ganhou os dois arquivos novos (a lista é manual e
  `MappingEditorView.swift` já estava lá). Build Debug e snapshot ok.

### Dois desvios de 006, deliberados

1. **`mapaFixo` e `dicasDeForma` viraram uma lista só** (`dicas: [DicaDeForma]`)
   mais a flag `mapaAplicavelSemPayload`. Nos quatro caminhos capturados os dois
   campos seriam idênticos — as chaves são literais. O Notion (022), cujos
   caminhos têm buraco (`properties.<sua propriedade>`), entra com a flag em
   `false` e é a razão de a flag existir. `// ponytail:` no arquivo.
2. **Assinatura do GHL de workflow**: 006 escreveu `first_name` **ou**
   `location.id`; ficou `location.id` **e** `workflow.id` (AND, como os outros
   três). `first_name` só existe em gatilho de contato, e `workflow.id` vem em
   qualquer webhook de workflow por construção. Assinatura é sempre AND agora —
   uma regra só, e o `presetcheck` garante que nenhum exemplo casa com dois
   caminhos.
