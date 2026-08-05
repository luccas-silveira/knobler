# Fase 3 — as superfícies somem

- map: ../map.md
- label: wayfinder:task
- status: closed
- assignee: claude (sessão 2026-08-04)
- blocked-by: 012

## Question

Executar. Onde a F2 era o compilador trabalhando, esta é o olho: rodar o app e o
`tools/snapshot.sh` e **ver sumir**. Fecha os **itens 2 e 4** do piloto (004).

Com o Pomodoro desinstalado:

1. A seção não aparece no card (já sai de graça de `ordenar`, 010 — só conferir)
   nem no **editor de ordem** (linha nova: o editor esconde seção de peça
   desinstalada — 002, "a opção some, sem avisar").
2. A **fixação é ignorada, não apagada** (linha nova — 007: desinstalar não
   apaga nada; sem isso a faixa apareceria vazia, porque fixada passa por cima
   de `hasContent`).
3. O painel `SettingsPane.pomodoro` some da lista de Ajustes.
4. O anel da faixa fechada (`NotchView.swift:1010-1019`) some.
5. Sem o **Descanso** instalado, a opção de travar a tela na pausa some do painel
   do Pomodoro — sem alerta, sem item acinzentado.

O filtro de 1 e 2 entra como **parâmetro** de `ordenar`, não como consulta ao
registro lá dentro, pro `sectionordercheck` seguir rodando sem subir o app (010).

Gate:
- `tools/plugincheck.swift` ganha: seção e painel do Pomodoro fora das listas
  quando desinstalado; registro fabricado sem o Descanso → a opção some. (O item
  do Descanso é provado **só aqui** — no app real o Descanso está sempre
  presente, então esse caminho nunca roda de verdade.)
- `tools/sectionordercheck.swift` ganha **dois casos** (encomenda de 010): o
  editor esconde a seção de peça desinstalada; a fixação de peça desinstalada é
  ignorada.

Ao fim desta fase o piloto está tecnicamente concluído — os 5 itens de 004 com
gate. O que falta é tela (F4) e papel (F5).

## Resolução (2026-08-04)

Executada. As cinco superfícies somem com a peça, e nenhuma delas consulta o
registro de dentro da parte pura.

**O filtro é um parâmetro, e virou função.** `NotchSectionOrder.ordenar` ganhou
`desinstaladas: Set<NotchSection> = []`, e o corte em si virou
`NotchSectionOrder.visiveis(base:desinstaladas:)` — uma função pura usada pelos
**dois** lados: o card (dentro de `ordenar`, antes de qualquer promoção) e o
editor de ordem em Ajustes. Como o corte acontece na ordem-base, a **fixação de
peça desinstalada é ignorada de graça**: ela nem chega no `filter` que deixa a
fixada passar por cima de `hasContent`. Nada é apagado — nem a ordem salva, nem
o conjunto de fixadas (007). `NotchSectionOrder.swift` segue sem conhecer
plugin, e o `sectionordercheck` segue compilando só ele.

**O registro passou a responder o avesso.** `PluginRegistry.escondidas(_:
instalados:)` (um `KeyPath<Plugin, String?>`, um método pros dois campos) e, no
host, `secoesEscondidas` / `paineisEscondidos`. Superfície que não é de peça
nenhuma (Geral, Notch, Permissões, Música) nunca entra nessa lista, logo nunca
some — é a propriedade que o gate confere.

**Duas coisas que o desenho não previa:**

1. *As telas precisavam do host.* `SettingsPane.visiveis` e o editor de ordem são
   `View`s estáticas — costurar o `PluginHost` do `AppDelegate` até cada uma
   seria plumbing puro. Virou `PluginHost.shared`, no molde de `AppSettings.shared`
   já usado no projeto; o `AppDelegate` só trocou `PluginHost()` por
   `PluginHost.shared`. Sem observabilidade ainda: nada instala/desinstala em
   tempo de execução até a vitrine (F4), e é lá que a reatividade precisa nascer.
2. *A trava de tela na pausa era um efeito solto.* O item 5 do ticket pedia a
   opção sumindo do painel, mas sumir da tela não basta: desinstalar não apaga
   ajuste (007), então um `pomodoroLockScreen` ligado de antes travaria a tela
   com o Descanso desinstalado. A pergunta foi pra **ficha** — `montarPomodoro`
   agora recebe o `PluginDeps` inteiro e o `onPhaseBegin` guarda
   `deps.instalado(.descanso)`. A view só esconde o toggle. É a mesma separação
   ligação/efeito da F2: a ficha decide, o app cumpre.

**Editor de ordem, o detalhe do arrasto.** Escondendo linhas, os índices do
`.onMove` passam a ser da lista visível, não da salva. O move é aplicado na
visível e as escondidas voltam no fim da ordem gravada — é onde `sanear` já as
colocaria de qualquer jeito.

**Gates.** `plugincheck` 8 → 10 casos (superfícies somem e voltam; sem Descanso
a pausa não trava, e com ele volta a travar — caminho que só existe aqui, o
Descanso está sempre presente no app real). `sectionordercheck` 12 → 14 (editor
esconde a desinstalada; fixada desinstalada é ignorada, não apagada). O caso
antigo `testTimerLigaComAPecaViva` passou a instalar o Descanso junto — é ele
quem trava. `eventoscheck` e `tools/snapshot.sh` ganharam `Knobler/Plugin.swift`
na lista de arquivos (o VM e os Ajustes agora citam o host). Build OK,
`./tools/check.sh` = 35 ok, `snapshot.sh` renderizando os 55 PNGs.

**Não feito, por escolha do dono:** a conferência no olho com `defaults write` na
máquina dele. Os gates herméticos cobrem as cinco superfícies, e a F4 abre a
vitrine — onde instalar e desinstalar vira clique e dá pra ver sem mexer em
defaults.

Piloto (004) tecnicamente concluído: os cinco itens com gate. Falta tela (F4) e
papel (F5).
