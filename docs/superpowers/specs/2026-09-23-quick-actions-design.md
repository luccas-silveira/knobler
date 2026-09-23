# Quick Actions + seção Cor — design

Data: 2026-09-23

## Objetivo

Dar acesso rápido a funções do app sem ocupar a barra inferior do card. Quem
não quer, por exemplo, o brilho (Monitores) ou o seletor de cor na barra, ainda
os alcança em dois toques.

## Quick Actions

- Nova `NotchSection` `acoesRapidas` ("Ações rápidas", ícone de grade
  `square.grid.2x2`). Entra na barra como qualquer seção: ordenável e ocultável
  pelos controles existentes.
- Conteúdo: grade de atalhos (ícone + `titulo` da seção) na ordem escolhida.
- Tocar num atalho troca o card para a seção alvo, **mesmo se ela estiver
  oculta** da barra. A barra não ganha o ícone da seção oculta.
- Lista de atalhos é independente da barra: uma seção pode estar nas duas.
- `acoesRapidas` não pode ser atalho de si mesma. Seções desinstaladas
  (plugin removido) não aparecem na grade.
- Persistência: array ordenado de `rawValue` no UserDefaults. `rawValue`
  desconhecido é ignorado na leitura.
- Lista começa vazia; grade vazia mostra aviso com botão que abre os Ajustes
  no painel de seções.

## Visita a seção oculta

- Atalho pra seção fora da barra abre uma "visita": o foco vai pra seção sem
  ela entrar em `secoes`, e o recálculo não o devolve à primeira seção.
- Nenhum ícone da barra fica aceso durante a visita.
- Deslizar em qualquer direção durante a visita volta ao Quick Actions.
- Fechar o card encerra a visita; reabrir cai no Quick Actions (o foco salvo
  grava `acoesRapidas`, nunca a seção oculta).
- Registrar a regra em `docs/architecture.md` (seção de foco).

## Ajustes

No painel de seções, bloco "Ações rápidas": marcar/desmarcar seções e
reordenar. Aceita seções ocultas.

## Seção Cor

- Nova `NotchSection` `cor` ("Cor", ícone `eyedropper`). Nasce **oculta** na
  barra.
- Botão do conta-gotas (reusa `ColorPicker.pick`) e as últimas 8 cores.
- Tocar numa cor recopia o HEX.
- O fluxo atual do conta-gotas (atalho/menu com card "copiado") continua e
  também alimenta o histórico, assim como a cor da caneta da Anotação — o
  registro fica em `ColorPicker.pick`, ponto único dos dois fluxos.
- Histórico persistido (8 HEX, mais recente primeiro, sem duplicata — repetir
  uma cor a move pro topo). Store singleton, injetado em todas as janelas
  (regra do projeto).

## Testes

- `sectionordercheck` (ou check novo em `tools/check.sh`): lista de atalhos
  filtra desinstaladas, ignora desconhecidas, exclui `acoesRapidas`; seção
  oculta continua alcançável via atalho.
- Check do histórico de cores: limite 8, dedupe move pro topo.
- Snapshots: grade com atalhos, grade vazia, seção Cor com histórico.

## Decisões do grill

- **A1** — criada a "visita" a seção oculta. Motivo: `focar` recusa seção fora
  da faixa (`NotchViewModel.swift:408`) e o recálculo devolve o foco (`:401`).
- **A2** — deslizar na visita volta ao Quick Actions. Motivo: a seção não tem
  vizinhas na faixa (`NotchViewModel.swift:430`).
- **A3** — reabrir cai no Quick Actions. Motivo: foco salvo de seção oculta
  viraria `focoPendente` eterno (`NotchViewModel.swift:362`).
- **A4** — descartado: `acoesRapidas` entra com `hasContent: true` fixo, como
  `.anotacao` (`NotchViewModel.swift:297`).
- **A5** — cor da Anotação entra no histórico. Motivo: `ColorPicker.pick` é o
  ponto único; registrar lá cobre tudo.
