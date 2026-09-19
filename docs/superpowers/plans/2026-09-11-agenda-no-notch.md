# Agenda no notch — plano de implementação

**Objetivo:** consultar eventos por dia no notch, conforme desenho aprovado.
**Arquitetura:** DTO puro em CalendarAviso; consulta no CalendarCountdown; estado
por monitor no NotchViewModel; AgendaView SwiftUI no card existente.
**Tecnologias:** Swift, Foundation, EventKit, AppKit e SwiftUI; nenhuma dependência nova.

## Restrições

Texto e comentários em pt-BR; eventos apenas em memória; não solicitar permissão
no lançamento; não alterar prioridades, countdown, Pomodoro ou gestos existentes.

## Execução

- [x] Acrescentar CalendarAgenda e CalendarEvento, com filtro semiaberto do dia,
  ordenação de dia inteiro antes dos horários e marcador de andamento.
  Ampliar tools/calendariocheck.swift com eventos entre dias, empates, duração
  zero, horários locais e dias de 23/25 horas. Rodar o check isolado.
- [x] Reutilizar CalendarCountdown: consulta diária separada, callback de atualização,
  autorização verificada antes de consultar e limpeza ao revogar. Entregar
  `agenda(no: Date, agora: Date) -> CalendarAgenda` ao ViewModel.
- [x] Acrescentar navegação por deslocamento diário no ViewModel, reiniciada ao
  abrir, com `onConsultarAgenda` e `onAgendaPermissions`; ligar por monitor em
  KnoblerApp. Testar navegação e ausência de promoção em eventoscheck.
- [x] Acrescentar `.agenda` à seção, título, ícone, ordem e altura; desenhar
  AgendaView com Hoje, anterior/seguinte, lista limitada com rolagem, estados
  vazio e sem permissão. Registrar a view em tools/notchview-fontes.txt.
- [x] Acrescentar snapshots sintéticos, atualizar docs/calendar-countdown.md e
  CHANGELOG.md; gerar projeto com xcodegen, compilar com xcodebuild e executar
  tools/check.sh e tools/snapshot.sh. Inspecionar imagens e corrigir em lote.
- [x] Revisão visual independente do resultado e documentação do que foi entregue.

## Validação executada

- `xcodegen generate` e build Debug via `xcodebuild`: passaram.
- `tools/check.sh`: 40 checks passaram; `codex-integration` não solicitado
  (requer `--com-ambiente`).
- `tools/snapshot.sh`: passou. Os três cenários de Agenda usam janela nativa
  sintética porque o ImageRenderer não desenha o conteúdo de ScrollView.
- Capturas inspecionadas: `Snapshots/agenda-hoje.png`, `agenda-vazia.png` e
  `agenda-sem-permissao.png`; nenhuma consulta a eventos pessoais no harness.
- Conferência visual de regressão: música pausada, aviso de calendário no
  Pomodoro, atividade e histórico vazio mantêm a composição existente.
- Revisão visual independente: `ship`, sem correções materiais. Capturas
  estáticas validam aparência; o comportamento é coberto pelos self-checks,
  sem simular concessão/revogação real do TCC no calendário do usuário.
