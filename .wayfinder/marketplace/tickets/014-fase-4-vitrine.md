# Fase 4 — a vitrine de Plugins

- map: ../map.md
- label: wayfinder:task
- status: open
- assignee: —
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
