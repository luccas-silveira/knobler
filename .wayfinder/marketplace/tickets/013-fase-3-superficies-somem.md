# Fase 3 — as superfícies somem

- map: ../map.md
- label: wayfinder:task
- status: open
- assignee: —
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
