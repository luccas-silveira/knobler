# Pesquisa — Agentes como peça

Spec: `docs/superpowers/specs/2026-09-23-agentes-peca-design.md`

Só frente interna, por pedido do usuário.

## Achados

### A1 — Botão ABRIR não faz nada em peça sem painel
- Fonte: `Knobler/PluginsSettingsPane.swift:~205-233` (`default: break`); precedente `.previewLink` em `:211`
- Contradiz a spec: parcial (omissão)
- Pergunta: ABRIR abre o notch já na seção Agentes?

### A2 — `parar()` não interrompe um subprocesso do Claude já lançado nem a leitura em curso
- Fonte: `Vendor/Codenotch/Providers/ClaudeTokenRefresher.swift:109-112`, `:223-260`; `Knobler/AgentesUso.swift:109-116`
- Contradiz a spec: parcial ("nenhum subprocesso")
- Pergunta: aceitar que uma renovação em curso termine sozinha (limitada pelo timeout), ou matar na hora?

### A3 — Passo único precisa marcar a chave também em instalação nova
- Fonte: `Knobler/Plugin.swift:380-391`, `:456`
- Contradiz a spec: parcial
- Pergunta: nenhuma para o usuário; sem isso, quem instala do zero e desinstala Agentes a vê voltar no próximo launch.

### A4 — Toggle do Claude some na hora só se o painel observar o host
- Fonte: precedente `Knobler/SettingsView.swift:606-612`, `@ObservedObject host` em `:95`
- Contradiz a spec: não

### A5 — `plugincheck` tem lista literal das prontas; docs falam em "onze peças"
- Fonte: `tools/plugincheck.swift:335-341`; `docs/plugins.md:5,25,35`; `docs/architecture.md:56,78,102`; `Knobler/Plugin.swift:385`
- Contradiz a spec: parcial (omissão de docs)

### A6 — Conformar `AgentesUso` (`@MainActor`) a `PluginServico` é seguro
- Fonte: `LinkPreview.swift:17,182-184` faz o mesmo; extensão fora de `Plugin.swift` (compile isolado do `plugincheck`)
- Contradiz a spec: não

### A7 — Seção some sozinha via `secao: "agentes"`; efeitos atribuídos antes do `subir()`
- Fonte: `Knobler/Plugin.swift:361-363,538-540`; `Knobler/KnoblerApp.swift:231,632`
- Contradiz a spec: não

## Fila do grill

1. A2 — renovação do Claude em curso ao desinstalar
2. A1 — o que ABRIR faz
3. A3, A5 — sem pergunta; entram direto na spec
