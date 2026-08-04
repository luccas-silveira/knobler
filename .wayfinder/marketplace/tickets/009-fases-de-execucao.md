# Fases de execução do piloto

- map: ../map.md
- label: wayfinder:grilling
- status: closed
- assignee: claude (sessão 2026-08-04)
- blocked-by: — (003, 004, 005, 006, 007, 008 e 010 fechados)

## Question

Com tudo decidido, fatiar a implementação em fases que caibam numa sessão cada,
na ordem em que uma deixa pronta a peça que a próxima usa. Cada fase vira ticket
próprio (graduação da névoa), com gate em `tools/check.sh`, doc e entrada no
`CHANGELOG.md`.

Fatia provável, a confirmar:

1. A declaração da peça e o registro compilando, sem ninguém usando ainda
   (mesmo padrão da Fase 1 dos webhooks: existe, não aparece na tela).
2. O estado de instalado mais a migração de quem já usa.
3. A cobaia convertida — nascimento condicional e as superfícies saindo da lista.
4. A tela mínima de instalar/desinstalar.
5. Docs, imagens e release.

Decidir também: **o que roda no gate novo** (qual harness `tools/*check*.swift`
prova que peça desligada não nasce), e como testar isso sem XCTest e sem abrir
o app.

## Resolução (2026-08-04)

**Cinco fases**, cada uma cabendo numa sessão, e **um gate só que cresce**.

### O que o código já respondeu de graça

Três achados que fixaram a fatia antes de qualquer discussão:

1. **O gate novo nunca vai poder abrir o `AppDelegate`.** Nenhum dos 30 gates de
   `tools/check.sh` compila `Knobler/KnoblerApp.swift` (1412 linhas, arrasta
   AppKit inteiro). O harness prova a *máquina de peças*, não a fiação — e não
   é perda: hoje `KnoblerApp.swift:79` é `private let pomodoro = Pomodoro()`,
   obrigatório; virando opcional, o **compilador** força cada ponto de uso a
   tratar o "não existe". Quem prova a fiação é o `xcodebuild`.
2. **O registro compila sozinho** enquanto as outras 10 fichas tiverem `nascer`
   vazio: `Knobler/Pomodoro.swift` só importa `Foundation` (218 linhas) e já traz
   molde de self-check embutido (`-D POMODORO_SELFCHECK`, como o `reminderscheck`).
3. **O Pomodoro está mais grudado do que 004 sugeria**: cinco pontos no
   `AppDelegate` — propriedade (79), montagem (410–438), as 6 closures do view
   model (1021–1028), o menu da barra que se reconstrói por estado (1180–1238) e
   6 ações `@objc` (1353–1358). Foi isso que quebrou a fase 3 original em duas.

### As cinco fases

| # | Fase | Entrega |
|---|---|---|
| 1 | [A peça, o registro e o instalado](011-fase-1-peca-e-instalado.md) | `Knobler/Plugin.swift` + a lista de ids em `UserDefaults` + a migração. Ninguém usa ainda. |
| 2 | [O Pomodoro nasce condicional](012-fase-2-nascimento-condicional.md) | Os 5 pontos do `AppDelegate`. Itens 1 e 3 do piloto. |
| 3 | [As superfícies somem](013-fase-3-superficies-somem.md) | Seção, ordenador, painel, anel, opção do Descanso. Itens 2 e 4. |
| 4 | [A vitrine de Plugins](014-fase-4-vitrine.md) | O painel "Plugins" nos Ajustes, 15 cards. |
| 5 | [Docs, imagens e release](015-fase-5-docs-e-release.md) | `docs/`, `CHANGELOG.md`, `tools/release.sh minor`. |

A fatia proposta no corpo do ticket tinha 5 fases mas mal distribuídas: a fase 3
original juntava fiação e desenho (o dobro das outras), e a fase 2 original eram
25 linhas (abrir sessão custaria mais que o trabalho). **A 3 virou duas** — 2 é
onde o compilador trabalha por você, 3 é onde o olho trabalha (snapshot, abrir o
app, ver sumir); misturadas, um erro no fim não diz se o problema é a peça ou o
desenho. **A 1 e a 2 originais viraram uma** — mesmo arquivo, mesmo tipo de
código (só `Foundation`, sem tela), mesmo gate.

### O gate: um só, nascendo na F1

`tools/plugincheck.swift`, compilando `Knobler/Plugin.swift Knobler/Pomodoro.swift`.
Um gate, não três, porque os 5 itens do piloto são a mesma pergunta ("a peça
obedece a lista de instalados?") vista de 5 ângulos, nos mesmos dois arquivos —
e três cabeçalhos de compilação com a mesma lista de fontes é sincronia pra
manter à toa. Nasce na F1 e não no fim porque senão as fases 1 e 2 terminariam
sem prova nenhuma.

- **F1** cria o arquivo e a linha em `tools/check.sh`. Casos: registro cobre
  todos os ids; `UserDefaults` vazio vira os 11 na migração; a migração roda uma
  vez só; id desconhecido é ignorado calado.
- **F2** acrescenta: peça desinstalada não nasce; `timerAtivo` liga com a peça e
  desliga ao desinstalar.
- **F3** acrescenta: seção e painel do Pomodoro fora das listas quando
  desinstalado; registro fabricado sem o Descanso → a opção de travar a tela
  some. **Mais dois casos no `sectionordercheck` que já existe** (encomenda de
  010) — vão no gate antigo, porque 010 decidiu que o filtro entra como
  *parâmetro* de `ordenar` justamente pra o `sectionordercheck` seguir rodando
  sem subir o app.
- **F4 e F5** não acrescentam gate: vitrine é tela, docs são texto.

**Uma linha nova em `Knobler/Pomodoro.swift`**: `var timerAtivo: Bool { timer != nil }`.
O item 3 do piloto ("o `Timer` de 1 s não existe") não tem como ser provado de
fora — `timer` é privado (`Pomodoro.swift:121-131`). Provar por dedução ("sem
objeto não há timer") custaria zero, mas seria uma asserção que **nunca pode
falhar**, e asserção que nunca falha é decoração. O caso que morde é desinstalar
**com o foco rodando** e alguém esquecer o `invalidate()` no `parar()`: o app
acorda de segundo em segundo pra sempre, com a peça desinstalada, quebrando o
`~0% CPU parado` do `PRODUCT.md` — o único dos cinco itens cujo erro é invisível
na tela.

### A vitrine mostra os 15 cards, com os 10 não-convertidos mudos

Contra a recomendação (que era mostrar só as 5 peças reais — as 4 de fábrica e o
Pomodoro — e deixar as outras entrarem conforme fossem convertidas), o dono
escolheu os 15 desde a F4: a vitrine já nasce parecendo uma loja.

O risco disso era botão que mente — desinstalar o Lembretes tiraria o card do
"instalado" e a feature continuaria funcionando igual. Resolvido no mesmo
fôlego: card de peça não convertida é **mudo** — capa, nome, frase e a palavra
**"Em breve"** onde iria o botão. Sem `ABRIR`, sem ⋯. O estado sai de "essa ficha
tem `nascer`?", que o registro já sabe responder.

Sem `ABRIR` também nos mudos porque 5 das 10 (Espelho, Nota rápida, Preview de
Link, Conversão de arquivo, Anotação) não têm painel de Ajustes: o `ABRIR` delas
teria que acender a própria feature de fora, que é a dívida parada de propósito
no mapa. Com card mudo a dívida continua parada, e botão de abrir e de
desinstalar nascem **junto com a conversão de cada peça** — uma peça converteu,
dois botões acenderam, e o progresso do trabalho aparece na própria tela.

Custo aceito: com 15 cards na tela, **todos os 15 precisam de nome, frase e
símbolo na F4** — inclusive as fichas decorativas das 4 de fábrica e os três
nomes provisórios (Preview de Link, Nota rápida, Conversão de arquivo), que o
dono bate na F4.

### Duas coisas que saem de graça

- **Como desinstalar antes da vitrine existir** (F2 e F3 precisam virar a chave
  sem tela): `defaults write` na chave `pluginsInstalados`, zero código — é o
  mesmo caminho que `CLAUDE.md` já documenta pra montar cenário de snapshot.
- **Versão**: uma release só, no fim da F5, **MINOR** (feature). As fases 1–4
  escrevem em `## [Unreleased]` do `CHANGELOG.md` conforme desenvolvem, como
  manda `VERSIONING.md`.
