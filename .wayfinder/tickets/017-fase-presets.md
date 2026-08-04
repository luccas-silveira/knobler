# Fase 1 — presets no bundle (quatro caminhos)

- map: ../map.md
- label: wayfinder:task
- status: in-progress
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
