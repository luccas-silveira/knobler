# Criar eventos no notch

Plano aprovado pelo usuário em 2026-09-15; implementação concluída.

## Comportamento

Formulário compacto no botão Novo evento da Agenda, com título, início/fim,
dia inteiro, calendário, local, link e observações. Padrão do macOS quando
editável; sem substituição silenciosa do destino. Hoje usa o próximo quarto
de hora e outros dias 9h, duração inicial de uma hora. Dia inteiro tem fim
inclusivo na interface e exclusivo no EventKit.

Rascunho em memória por monitor. Hover não recolhe durante edição; fechamento
manual, Escape, troca de seção e interrupções preservam o preenchimento.
Cancelar descarta; Salvar bloqueia cliques repetidos e limpa somente em sucesso.
Notificações comuns aguardam enquanto o formulário está em foco.

## Integração

- CalendarRascunho e CalendarDestino são dados puros, sem reter objetos EventKit.
- CalendarCountdown lista calendários editáveis e revalida autorização/destino
  antes de gravar um EKEvent com commit verdadeiro.
- ViewModel controla rascunho, salvamento, erro, confirmação e navegação após
  sucesso; callbacks compõem o serviço com as telas existentes.
- AgendaEditorView usa campos e seletores nativos, com teclado e rolagem própria.
  Altura até 400pt, limitada pelo espaço da tela; ações/erros fora da rolagem.
- Eventos salvos ficam no calendário do macOS e seguem sua sincronização;
  nenhum endpoint, credencial, dependência ou persistência de rascunhos nova.

## Validação e entrega

- [x] Testes puros: título, calendário, permissão, URL, datas, dias de 23/25 horas.
- [x] Checks de rascunho, fila, teclado, duplicatas, falha e nova tentativa.
- [x] Build e snapshots nativos com dados sintéticos, revisão visual.
- [x] Documentação e changelog atualizados; instalar com a assinatura existente.

Não inclui edição, exclusão, convidados, recorrência ou configuração de alertas.
Referência: https://developer.apple.com/documentation/eventkit/creating-events-and-reminders

## Resultados

- Build Debug passou; os 40 checks canônicos passaram.
- Snapshots sintéticos do formulário, dia inteiro, falha, calendário indisponível
  e tela baixa renderizaram e foram inspecionados.
- O harness usa a NotchWindow real e verifica foco/teclado, digitação no
  NSTextView atualizando o rascunho, Tab e Escape preservando o preenchimento.
- Revisão visual independente: ship, sem correções materiais.
- Testes não gravam eventos no calendário pessoal; a escrita é acionada apenas
  por Salvar no app instalado. Eventos com horário usam o fuso atual do Mac;
  dia inteiro usa datas flutuantes.
- Build instalada em `/Applications/Knobler.app` e reaberta; assinatura
  local preservada e binário instalado comparado com a build validada.
