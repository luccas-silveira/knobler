# Fase 1 — a peça, o registro e o instalado

- map: ../map.md
- label: wayfinder:task
- status: open
- assignee: —
- blocked-by: — (009 fechado)

## Question

Executar. Nada a decidir: 003 fixou a forma, 005 fixou onde vive o instalado,
009 fixou o gate. Fase de execução — ao fim, o app compila e **nada muda na
tela**, igual à Fase 1 dos webhooks.

Entregar:

1. `Knobler/Plugin.swift` — só `Foundation`. `enum PluginID` com os 11 ids de
   002, `struct Plugin` (id, nome, descrição, símbolo, seção, painel, rotas,
   permissão, `nascer`), `protocol PluginServico`, `struct PluginDeps`,
   `enum PluginRegistry` com o array literal e o gate `completo`, e o
   `PluginHost`. Molde compilando em
   [`prototypes/003-forma-da-peca.swift`](../prototypes/003-forma-da-peca.swift)
   — copiar, não redesenhar.
2. As 15 fichas: as 11 de plugin (só o Pomodoro com `nascer` de verdade; as
   outras 10 com `nascer` vazio, ainda não convertidas) e as 4 de fábrica como
   ficha decorativa (sem `nascer`, sem `PluginID`). Nome, frase e símbolo podem
   ficar provisórios aqui — a F4 é que bate o martelo.
3. O instalado: lista de ids na chave `pluginsInstalados` do `UserDefaults`, e a
   migração que dá os 11 pra todo mundo uma vez, com o truque de versão do
   `Onboarding` (`Knobler/Onboarding.swift:47-69`) na chave `plugins.migracao`.
   Id órfão é ignorado calado, não apagado.
4. `tools/plugincheck.swift` + a linha em `tools/check.sh`, compilando
   `Knobler/Plugin.swift Knobler/Pomodoro.swift`. Casos desta fase: registro
   cobre todos os ids; `UserDefaults` vazio vira os 11 na migração; a migração
   roda uma vez só; id desconhecido é ignorado calado.
5. Linha em `## [Unreleased]` do `CHANGELOG.md`. Sem release.

`xcodegen generate` depois de criar o arquivo novo. Ninguém consulta o
`PluginHost` ainda — isso é a F2.
