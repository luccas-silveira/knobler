# Fase 4 — a vitrine de Plugins

- map: ../map.md
- label: wayfinder:task
- status: closed
- assignee: claude (sessão 2026-08-04)
- blocked-by: 013

## Question

Executar. O painel próprio **"Plugins"** na barra lateral de Ajustes, vitrine em
grade de 2 colunas, desenhada em 006. Protótipo compilando e renderizando PNG em
[`prototypes/006-tela-de-plugins.swift`](../prototypes/006-tela-de-plugins.swift)
— copiar, não redesenhar.

- Duas seções fixas: "Incluído no Knobler" (as 4 de fábrica, rótulo "Incluído",
  sem ação) e "Plugins" (as 11).
- Card = capa (símbolo SF sobre degradê da cor da ficha — zero arte nova), nome,
  uma frase, botão pílula. O card **não muda de lugar** ao instalar, só o botão.
- Botão em três estados lidos da lista de ids; **⋯ com "Desinstalar (seus dados
  ficam salvos)"** só em peça instalada (007); **`ABRIR` sempre vivo** — peça com
  painel abre o painel.
- **Card mudo** (009) para as 10 peças ainda não convertidas: capa, nome, frase e
  a palavra **"Em breve"** onde iria o botão. Sem `ABRIR`, sem ⋯. O estado sai de
  "essa ficha tem `nascer`?", que o registro já responde. Só o Pomodoro tem botão
  de verdade nesta fase.

**Bater o martelo em nome, frase e símbolo dos 15 cards** — inclusive os três
provisórios que 006 inventou (Preview de Link, Nota rápida, Conversão de
arquivo) e as fichas decorativas das 4 de fábrica. É decisão do dono, uma
pergunta de cada vez.

Sem gate novo: vitrine é tela. Validar por `tools/snapshot.sh` se o cenário
couber no harness, senão por screenshot do painel real
(`Knobler.app/Contents/MacOS/Knobler --ajustes=plugins`, receita em `CLAUDE.md`).

## Resolução (2026-08-04)

**Executada.** `Knobler/PluginsSettingsPane.swift` (novo) + `case plugins` no
`SettingsPane`. O desenho é cópia do protótipo 006; o que mudou é abaixo.

**O martelo do dono**, as duas perguntas que o ticket exigia:

1. O card da peça `anotacao` passou a se chamar **"Desenho"** — o nome do painel
   que o `ABRIR` dele abre. Os dois apareceriam lado a lado na vitrine com nomes
   diferentes. O `PluginID` e a seção do card seguem `anotacao`: renomear id
   desinstala a peça na máquina de quem já usa (003).
2. Os três nomes que 006 inventou (Preview de Link, Nota rápida, Conversão de
   arquivo) ficam como estão.

**Duas coisas que o desenho não previa:**

- **"Essa ficha tem `nascer`?" não é uma pergunta que dê pra fazer em runtime.**
  `nascer` é uma closure não-opcional; a vazia (`{ _ in nil }`) e a de verdade
  são indistinguíveis depois de compiladas. Virou o campo `pronta` na ficha, e o
  `plugincheck` trava a lista de quem está convertido (`[.pomodoro]` hoje) — o
  assert quebra na fase que converter a próxima peça e esquecer de virar a
  chave, que é exatamente quando se quer ser avisado.
- **O `PluginHost` teve de virar `ObservableObject`.** A barra lateral lê
  `SettingsPane.visiveis`, que consulta o host; sem `@Published` em `instalados`
  e sem `@ObservedObject` na `SettingsView`, desinstalar pela vitrine só tiraria
  o painel da lista na próxima abertura da janela.

A cor da capa mora na view (`corDaPeca`), não na ficha: `Plugin.swift` é
Foundation puro de propósito — é o que deixa o `plugincheck` compilar a máquina
de peças sem arrastar SwiftUI.

**Validação.** `plugincheck` foi a 12 casos (estado do botão nos três estados,
ida e volta do desinstalar, e "toda peça não convertida diz Em breve e não
oferece desinstalar"). `./tools/check.sh` → 35 ok; `tools/snapshot.sh` precisou
do arquivo novo na lista manual dele. Como o painel é `NavigationSplitView`, não
entra no harness — foi exercitado **clicando no app rodando**: desinstalar pelo
`⋯` tira o painel da barra lateral na hora e troca o botão sem o card mudar de
lugar, `INSTALAR` devolve tudo, `ABRIR` navega pro painel do Pomodoro.
