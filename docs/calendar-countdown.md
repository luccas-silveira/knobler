# Agenda e countdown de calendário

![Anel de atividade no notch (mesma UI usada pelo countdown)](images/expanded-activity-only.png)

*O countdown usa o mesmo anel de "live activity" genérico do Knobler — não
tem uma UI própria separada.*

## Agenda no notch

Abra o notch e selecione o ícone de calendário na faixa de seções. A Agenda
mostra os eventos de **Hoje** com horários, título e calendário de origem.
Eventos de dia inteiro aparecem primeiro; os que estão acontecendo recebem
“Em andamento”. Use as setas para consultar outros dias e **Hoje** para voltar.
A lista tem rolagem vertical; o gesto horizontal continua trocando de seção.

Reabrir o notch volta a Hoje. Cada monitor mantém sua navegação enquanto o
card fica aberto. A seção aparece mesmo em dias vazios e pode ser ordenada ou
fixada nos ajustes existentes. Mudanças nos eventos atualizam a lista sem abrir
o notch ou trocar o foco. Eventos cancelados ficam fora da lista.

Sem acesso ao calendário, **Abrir permissões** leva a Ajustes → Permissões.
A agenda permite consultar e criar eventos. Os rascunhos ficam apenas em memória;
a gravação no calendário ocorre somente ao clicar em Salvar. A conta configurada
no macOS cuida da sincronização dos eventos salvos. O acesso usa a mesma permissão
de calendário já exigida pelo countdown e respeita sua revogação.

**Contagem do calendário** em Ajustes → Notch controla os avisos automáticos;
desligá-la mantém a consulta voluntária pela Agenda. Para impedir qualquer leitura,
revogue o acesso a Calendários nos Ajustes do Sistema.

## Criar um evento

Clique em **+ (Novo evento)**. Preencha título, início e fim, calendário e,
se desejar, dia inteiro, local, link HTTP/HTTPS e observações. O calendário
padrão do macOS vem selecionado quando permite gravação; você pode trocar.
Somente calendários editáveis aparecem. Sem um padrão disponível, escolha um.

A data inicial acompanha o dia consultado. Hoje usa o próximo quarto de hora;
outros dias começam às 9h, com duração inicial de uma hora. Em dia inteiro,
a data final é inclusiva: datas iguais criam um evento de um dia.

O formulário mantém o notch aberto mesmo sem o mouse em cima. Tab percorre os
campos; Escape recolhe sem apagar. Trocar de seção ou receber uma interrupção
também preserva o rascunho. Cada monitor mantém o seu enquanto o app está aberto.
**Cancelar** descarta; **Salvar** cria o evento e volta à agenda na data dele.

Se faltar permissão, o calendário deixar de aceitar eventos ou a gravação
falhar, o rascunho permanece para correção e nova tentativa. Durante a gravação,
o botão fica bloqueado para evitar duplicatas. Não há edição, exclusão,
convidados, recorrência ou configuração de alertas neste formulário.

## Countdown

### O que faz

O próximo evento do seu calendário vira uma "live activity" no notch: entra
15 minutos antes com um anel que esvazia até a hora do evento, mostra "agora"
no início e some 1 minuto depois. Usa o mesmo mecanismo de atividade que a
API local usa pra deploys/builds — visualmente é o anel de progresso genérico
do Knobler.

## Como usar

- Não exige ação: com a permissão concedida, o próximo evento aparece
  sozinho 15 minutos antes.
- Pode ser desligado em Ajustes → Notch.

## Durante o Pomodoro

O Pomodoro toma o lugar da atividade no notch, então o countdown apareceria só
depois do foco acabar. Pra evitar isso, o evento entra no próprio card do
Pomodoro (linha abaixo do timer) e toma a pílula fechada nos últimos 5 minutos.
Detalhes em [pomodoro.md](pomodoro.md).

## Permissões

- **Calendário (acesso completo)** — *"Knobler mostra sua agenda, cria eventos quando você salva e avisa sobre o próximo compromisso no notch."* Pedido pelo painel **Ajustes → Permissões**
  (botão *Permitir*), não na abertura do app — o balão do EventKit no launch
  caía por cima da [página de novidades](novidades.md). Enquanto não vem, a
  contagem fica quieta e a Agenda mostra o acesso necessário. A integração liga em
  segundos quando a permissão chega, sem reabrir o app. Se negada, fica quieta
  pra sempre até você mudar no Ajustes do Sistema.
