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
