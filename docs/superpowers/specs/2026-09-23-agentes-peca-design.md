# Agentes como peça do marketplace

Data: 2026-09-23. Base: seção Agentes (`docs/superpowers/specs/2026-09-23-agentes-uso-design.md`).

## Objetivo

A seção Agentes (sessões + anéis de limite de Claude/Codex) vira uma peça do
marketplace, instalável e desinstalável na vitrine, no modelo de Monitores.

## Decisões do usuário

- Começa **instalada para todos**: instalação nova e quem já usa o Knobler.
- Liga/desliga = instalar/desinstalar. Sem chave própria além disso.
- O anel do Claude segue como ajuste interno opt-in (`agentesClaudeUso`).

## Design

**Ficha.** `PluginID.agentes` + `Plugin(id: .agentes, nome: "Agentes", secao:
"agentes", painel: nil, rotas: [], permissao: nil, pronta: true, nascer: {
$0.agentes.nascer() })`, com `AgentesEfeitos { nascer }` em `PluginDeps` e
`PluginHost.agentesEfeitos`, igual a `MonitoresEfeitos`.

**Ciclo de vida.** `AgentesUso` passa a conformar `PluginServico`. `iniciar()`
continua idempotente. `parar()` novo: `coordinator.stop()`, `timer` invalidado
e zerado, `bag` esvaziado, `claudeUso(false)` (para o refresher, solta o
provider), `sessoes`/`uso`/`lidoEm`/`porFonte` limpos e o watcher recriado, pra
que reinstalar não anuncie de novo sessões antigas. Desinstalada = nenhum
monitor, timer, subprocesso ou leitura de Keychain.

**Launch.** `configureAgentes` para de chamar `iniciar()`: registra o `onEvento`
e empresta `AgentesEfeitos(nascer: { AgentesUso.shared.iniciar(); return
AgentesUso.shared })` antes do `plugins.subir()`.

**Instalada para todos.** A migração atual (`versaoMigracao = 1`) já instala
tudo menos Monitores em instalação nova. Para quem já migrou, um passo único
com chave própria (`plugins.agentes.migrado`) acrescenta `.agentes` à lista uma
vez. Rodou uma vez, não roda mais: desinstalar depois é respeitado. Não sobe
`versaoMigracao` (isso reinstalaria tudo em todo mundo).

**Superfícies.** A seção sai da ordem pelo `NotchSection.desinstaladas()`
existente. O toggle do anel do Claude em Ajustes › Notch só aparece com a peça
instalada. Cor da vitrine em `PluginsSettingsPane`.

**Checks.** `plugincheck`: peça registrada e pronta; migração nova inclui
`.agentes`; passo único acrescenta a quem já migrou; não reacrescenta depois de
desinstalada. `agentescheck` segue verde.

## Fora do escopo

Travamento de cliques relatado uma vez; verificação ao vivo com dois monitores;
merge do branch.

## Decisões do grill

Pesquisa só interna, por pedido do usuário. Dossiê:
`docs/superpowers/research/2026-09-23-agentes-peca-research.md`.

- **A2** — Renovação do token do Claude já em curso ao desinstalar termina
  sozinha (limitada pelo timeout do refresher); `parar()` só impede novas. Motivo:
  matar exige mexer no vendor e pode cortar a gravação do token no meio. A
  leitura de uso em curso também não é cancelada; o resultado cai num store já
  limpo e é descartado (`atualizarUso` checa `claude === self.claude`; o `uso` do
  Codex é zerado de novo no `parar()` se preciso).
- **A1** — ABRIR na vitrine abre o notch focado na seção Agentes, como o
  `.previewLink` (`PluginsSettingsPane.swift:211`).
- **A3** — O passo único marca `plugins.agentes.migrado` também em instalação
  nova (quando `migrarSePreciso` acabou de rodar), senão Agentes desinstalada
  voltaria no launch seguinte. Roda no `PluginHost.init`, depois de
  `migrarSePreciso` e antes do `ler()`.
- **A4** — Toggle do anel do Claude condicionado a
  `PluginHost.shared.estaInstalado(.agentes)`, no padrão de
  `SettingsView.swift:606-612`; confirmar que o painel observa o host.
- **A5** — Atualizar a lista literal de prontas do `plugincheck`
  (`:335-341`), o comentário "os 11" (`Plugin.swift:385`), `docs/plugins.md`
  (`:5,25,35`), `docs/architecture.md` (`:56,78,102`), CHANGELOG [Unreleased] e
  `Novidades/0.33.0.html` dizendo que Agentes é peça, instalada por padrão.
- **A6** — Conformidade `AgentesUso: PluginServico` numa extensão fora de
  `Plugin.swift` (em `AgentesUso.swift`), como `LinkPreview`.
- **A7** — Sem mudança: a seção some sozinha pelo campo `secao`, e os efeitos
  são atribuídos antes do `subir()`.
