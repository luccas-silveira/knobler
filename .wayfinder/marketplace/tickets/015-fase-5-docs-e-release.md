# Fase 5 — docs, imagens e release

- map: ../map.md
- label: wayfinder:task
- status: closed
- assignee: claude (sessão 2026-08-04)
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

## Resolution

**Executada** (sessão 2026-08-04).

- `docs/architecture.md` — seção nova **"O app é feito de peças"**: a peça é
  dado + uma closure, o registro é literal, o `PluginHost` sobe só quem está
  instalado, peça pergunta por peça, as superfícies somem sozinhas, desinstalar
  não apaga nada, e `Plugin.swift` é Foundation puro de propósito.
- `docs/local-api.md` — a marca `(plugin: espelho)` no título de `POST /mirror`,
  o `404` com `plugin` no corpo (e a linha correspondente em "Erros e limites")
  e o campo `plugins` no `GET /status`.
- `docs/plugins.md` — doc de usuário novo, ligado em `docs/index.md`, com duas
  capturas do painel real (`settings-plugins.png`, com ABRIR/⋯/Em breve, e
  `settings-plugins-fabrica.png`, o topo com as 4 de fábrica).
- `CHANGELOG.md` — bloco `### Changed` da API local somado às quatro entradas
  que as F1–F4 já tinham escrito; `## [Unreleased]` fechado pelo `release.sh`.

**O que o ticket não previa: o item 2 não era só doc.** O ticket 008 tinha sido
decidido mas nunca implementado — nenhuma das fases 1–4 tocou o
`NotchAPIServer`. Documentar o `404` sem o `guard` seria doc mentindo, então o
código de 008 saiu aqui: o `guard PluginHost.shared.estaInstalado(.espelho)` em
`POST /mirror`, a marca no `usage` do 404 genérico e `status["plugins"]` no
`statusProvider` do `AppDelegate`. Custo: as três linhas que 008 previa.

**Sem gate novo.** Nenhum harness compila `NotchAPIServer.swift` nem
`KnoblerApp.swift` (é a fatia que 009 já tinha constatado), e o guard depende do
singleton `PluginHost.shared` — provar isso exigiria injetar o host no servidor,
que é mais código que o próprio guard. Fica no olho.

**Validação.** `./tools/check.sh` → 35 ok; build Debug ok; captura tirada do
painel real rodando (`--ajustes=plugins`), com o app de `/Applications`
restaurado no fim.
