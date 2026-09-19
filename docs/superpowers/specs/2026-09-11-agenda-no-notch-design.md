# Agenda no notch

Status: desenho aprovado pelo usuário em 2026-09-11.

## Experiência proposta

Adicionar uma seção **Agenda** à faixa de ícones do notch expandido. Abre em
**Hoje**, com navegação para o dia anterior/seguinte e ação para voltar a hoje.
Lista os eventos do dia em ordem de início, com horário inicial/final, título e
nome do calendário. Eventos de dia inteiro aparecem primeiro, identificados
como “Dia inteiro”; eventos em andamento recebem “Em andamento”.

A lista tem rolagem dentro da altura limitada do card. A seção segue os
controles existentes de ordenação e fixação. Atualizações de calendário não
roubam o foco da seção atual nem abrem o notch automaticamente.

Sem eventos: “Nenhum evento neste dia”. Sem permissão: explicar o acesso e
oferecer o fluxo de permissões existente. Não solicitar acesso no lançamento.

## Alternativas consideradas

- **Lista diária com navegação (recomendada):** cabe no notch e permite consultar
  compromissos futuros sem uma grade mensal.
- **Somente hoje:** menos controles, mas não permite consultar amanhã.
- **Grade mensal:** facilita escolher datas distantes, mas ocupa mais espaço
  e exige uma segunda região para os eventos.

## Integração

Reutilizar o EventKit e o serviço `CalendarCountdown`, que já observa mudanças
e consulta os calendários. Publicar a agenda separadamente do aviso do próximo
evento: a janela de 15 minutos não limita a consulta diária. Preservar countdown,
Pomodoro, espelho antes de reunião e detecção de reunião em andamento.

Transmitir dados à interface pelo ViewModel, seguindo a ligação existente em
`KnoblerApp`. Acrescentar a seção em `NotchSection`, seu conteúdo em SwiftUI e
sua altura em `NotchPresentation`. Reaproveitar os calendários já consultados.
Manter dados de eventos apenas em memória e respeitar revogação da permissão.
Datas usam limites do dia no calendário/fuso local, incluindo eventos que
atravessam a meia-noite.

## Limites desta entrega

Consulta de eventos; criação/edição, seleção de calendários e entrada em calls
ficam fora desta proposta. Preservar preto, tipografia do sistema e hierarquia
visual existentes, com rótulos e acessibilidade em pt-BR.

## Validação

Self-checks para ordenação, eventos de dia inteiro, sobreposição entre dias,
estado vazio e integração da nova seção. Executar `tools/check.sh`, gerar o
projeto e compilar. Acrescentar snapshots sintéticos de agenda preenchida,
vazia e sem permissão, gerar e inspecionar as imagens. Atualizar changelog e
documentação de calendário após implementação.

## Decisões do grill

- A1 — Agenda é seção de fábrica sempre acessível, como Anotação, mesmo vazia
  ou sem permissão. Não marca eventos de promoção nem muda o foco automaticamente.
- A2 — Cada monitor mantém sua navegação. Reabrir o notch volta a Hoje;
  a atualização periódica acompanha a virada do dia pelo calendário local.
- A3 — A preferência existente controla o countdown e seus efeitos; a consulta
  voluntária da Agenda continua disponível. Nenhum novo pedido no lançamento.
- A4 — Usar intervalo semiaberto do dia e ordenar explicitamente. Eventos de
  duração zero entram no dia do início; cancelados não aparecem.
- A5 — Reutilizar a abertura de Ajustes → Permissões via callback do ViewModel.
  As decisões técnicas foram resolvidas pelo código e mantêm o desenho aprovado.
