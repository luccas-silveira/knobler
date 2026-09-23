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

## Ajustes

No painel de seções, bloco "Ações rápidas": marcar/desmarcar seções e
reordenar. Aceita seções ocultas.

## Seção Cor

- Nova `NotchSection` `cor` ("Cor", ícone `eyedropper`). Nasce **oculta** na
  barra.
- Botão do conta-gotas (reusa `ColorPicker.pick`) e as últimas 8 cores.
- Tocar numa cor recopia o HEX.
- O fluxo atual do conta-gotas (atalho/menu com card "copiado") continua e
  também alimenta o histórico.
- Histórico persistido (8 HEX, mais recente primeiro, sem duplicata — repetir
  uma cor a move pro topo). Store singleton, injetado em todas as janelas
  (regra do projeto).

## Testes

- `sectionordercheck` (ou check novo em `tools/check.sh`): lista de atalhos
  filtra desinstaladas, ignora desconhecidas, exclui `acoesRapidas`; seção
  oculta continua alcançável via atalho.
- Check do histórico de cores: limite 8, dedupe move pro topo.
- Snapshots: grade com atalhos, grade vazia, seção Cor com histórico.
