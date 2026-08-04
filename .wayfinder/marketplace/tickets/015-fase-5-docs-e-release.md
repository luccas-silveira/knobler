# Fase 5 — docs, imagens e release

- map: ../map.md
- label: wayfinder:task
- status: open
- assignee: —
- blocked-by: 014

## Question

Executar. Fecha o mapa.

1. `docs/architecture.md` — a seção nova: o app é feito de peças, o `AppDelegate`
   pergunta ao `PluginHost` quem está ligado, peça desligada não nasce.
2. `docs/local-api.md` — a marca `(plugin: X)` no título de `POST /mirror`, o
   `404` com `plugin` no corpo, e o campo `plugins` no `GET /status` (008). Três
   linhas.
3. Doc de usuário do painel Plugins + `docs/images/` (screenshot do painel real,
   receita em `CLAUDE.md`).
4. `CHANGELOG.md`: fechar o `## [Unreleased]` que as fases 1–4 foram escrevendo.
5. `./tools/release.sh minor` — feature nova, pré-1.0 (`VERSIONING.md`). Uma
   release só pro piloto inteiro. Nunca editar `MARKETING_VERSION` à mão.

Antes: `./tools/check.sh` verde, incluindo o `plugincheck` com os oito casos e o
`sectionordercheck` com os dois novos.
