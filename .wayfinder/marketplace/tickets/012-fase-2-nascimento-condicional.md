# Fase 2 — o Pomodoro nasce condicional

- map: ../map.md
- label: wayfinder:task
- status: open
- assignee: —
- blocked-by: 011

## Question

Executar. O `AppDelegate` passa a perguntar "quem está ligado?" em vez de criar
o Pomodoro na mão. Ao fim, com a peça desinstalada o objeto `Pomodoro` não
existe e o `Timer` de 1 s não roda — **itens 1 e 3** do piloto (004).

Os cinco pontos de `Knobler/KnoblerApp.swift` (conferir as linhas: são da
v0.22.0):

1. `:79` — `private let pomodoro = Pomodoro()` vira opcional, vindo do
   `PluginHost`. É esta linha que faz o compilador apontar as outras quatro.
2. `:410-438` — a montagem (`configProvider`, `onState`, `onPhaseEnd`,
   `onPhaseBegin`) migra pro `nascer` da ficha.
3. `:1021-1028` — as 6 closures do view model.
4. `:1180-1238` — o menu da barra, que se reconstrói por estado do Pomodoro.
5. `:1353-1358` — as 6 ações `@objc`.

Mais uma linha em `Knobler/Pomodoro.swift`: `var timerAtivo: Bool { timer != nil }`
(leitura só, pro gate).

Gate: acrescentar ao `tools/plugincheck.swift` — peça desinstalada não nasce;
`timerAtivo` liga com a peça viva e o foco rodando, e desliga ao desinstalar.

Testar sem tela: `defaults write` na chave `pluginsInstalados`.

A tela ainda **não** muda: sem o Pomodoro, a seção some sozinha porque `ordenar`
já esconde quem não tem conteúdo (010), mas o painel de Ajustes e o anel da
faixa continuam lá. Isso é a F3.
