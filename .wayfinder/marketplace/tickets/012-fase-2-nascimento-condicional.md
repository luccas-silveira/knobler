# Fase 2 — o Pomodoro nasce condicional

- map: ../map.md
- label: wayfinder:task
- status: closed
- assignee: claude (sessão 2026-08-04)
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

## Resolução (2026-08-04)

Feito. Build OK, `./tools/check.sh` = 35 ok (o `plugincheck` foi de 6 pra 8
casos).

Os cinco pontos:

1. `private let pomodoro = Pomodoro()` virou `private let plugins = PluginHost()`
   mais `private var pomodoro: Pomodoro? { plugins.servico(.pomodoro) }`.
2. A montagem migrou pra `montarPomodoro(_:)`, em `Plugin.swift`, e o
   `AppDelegate` agora só entrega os efeitos + chama `plugins.subir()`.
3. As 6 closures do view model e (4) as 6 ações `@objc` viraram `pomodoro?.`.
4. O menu da barra: o bloco inteiro (itens + separador) entrou num
   `if let pomodoro` — peça desinstalada, menu sem linha de Pomodoro.

Como a montagem coube na ficha (o ponto que quase virou desvio): `Plugin.swift`
é `Foundation` puro de propósito — é o que deixa o `plugincheck` compilar
isolado — e a montagem original citava `AppSettings`, `NSSound`, os view models
e o `DescansoController`, tudo AppKit. A saída foi separar **ligação** de
**efeito**: a ficha ficou com as decisões (quem escuta o quê, a borda de
atividade que filtra os tiques de 1 s, o "só pausa trava a tela" e o cálculo da
duração), e o `AppDelegate` entrega um `PomodoroEfeitos` — 5 closures — dizendo
só *como* o app cumpre cada efeito. Bônus: a montagem virou testável, e o gate
novo confere de fato que ela está ligada.

Duas linhas a mais que o ticket previa, ambas pra não duplicar valor:
`Pomodoro.Config.padrao` (o default agora é um só, usado pelo engine e pelos
efeitos) e o `var timerAtivo` pedido.

Casos novos no `plugincheck`:

- `testPecaDesinstaladaNaoNasce` — fora da lista, `subir()` nem visita a ficha:
  sem serviço, sem montagem, sem seção.
- `testTimerLigaComAPecaViva` — `timerAtivo` liga no `start()`, a montagem
  publica estado, a borda de atividade avisa uma vez só, pular o foco dispara o
  gancho da pausa com a duração certa, e desinstalar apaga o timer.

Não feito de propósito: o teste manual com `defaults write` na chave real. Ele
exige fechar o Knobler do usuário e mexer nos defaults da máquina dele; os dois
casos herméticos cobrem os itens 1 e 3 do piloto (004) sem isso.
