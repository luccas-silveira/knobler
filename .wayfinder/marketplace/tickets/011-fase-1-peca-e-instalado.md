# Fase 1 — a peça, o registro e o instalado

- map: ../map.md
- label: wayfinder:task
- status: closed
- assignee: claude (sessão 2026-08-04)
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

## Resolução (2026-08-04)

Executado. O app compila, `./tools/check.sh` dá **35 ok** (era 34) e **nada
mudou na tela** — ninguém consulta o `PluginHost` ainda.

### O que entrou

- **`Knobler/Plugin.swift`** (só `Foundation`, como o `Onboarding`): `PluginID`
  com os 11 ids de 002, `struct Plugin` (id, nome, descrição, símbolo, seção,
  painel, rotas, permissão, `nascer`), `protocol PluginServico`,
  `struct PluginDeps`, `PluginRegistry` (array literal + gate `completo`),
  `PluginsInstalados` e o `PluginHost`. Cópia do protótipo 003, com três
  diferenças: `PluginDeps` só tem `instalado(_:)` (o `publicar` do protótipo era
  dublê; o de verdade entra na F2), `struct PluginDeFabrica` pras 4 fichas
  decorativas, e o host lê/grava o `UserDefaults` sozinho.
- **As 15 fichas.** Nome, frase e símbolo vieram do protótipo da vitrine (006) —
  a F4 bate o martelo. Só o Pomodoro tem `nascer` de verdade (`{ _ in Pomodoro() }`);
  as outras 10 têm `nascer` vazio. `extension Pomodoro: PluginServico` com
  `parar() { reset() }` — o `reset()` que já existia invalida o `Timer` de 1 s e
  publica idle, então "morrer" saiu sem código novo.
- **O instalado**: chave `pluginsInstalados` (lista de ids) + migração na chave
  `plugins.migracao` com o truque de versão do `Onboarding`. Id órfão é ignorado
  na leitura **e preservado na gravação** — `gravar` recolhe os ids que este
  build não conhece e regrava junto, senão a primeira desinstalação apagaria a
  peça de outra versão.
- **`tools/plugincheck.swift`** + linha em `tools/check.sh`. Seis casos: registro
  cobre todos os ids; seção citada na ficha existe no `NotchSection`; defaults
  vazio vira os 11; a migração roda uma vez só; id desconhecido é ignorado calado
  e não é apagado; peça desligada não nasce (e desinstalar mata o serviço e
  persiste).
- Linha em `## [Unreleased]` do `CHANGELOG.md`. Sem release — é a F5.

### Desvio do ticket

O gate compila **três** arquivos, não dois: entrou `Knobler/NotchSectionOrder.swift`
junto de `Plugin.swift` e `Pomodoro.swift`. Custo zero (é Foundation puro) e paga
o assert que 003 pediu — a ficha cita a seção por string, e erro de digitação aí
só apareceria na tela.
