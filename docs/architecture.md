# Arquitetura

Este é o mapa da implementação atual do Knobler. O projeto é um app macOS
nativo em Swift/SwiftUI, com AppKit nas janelas, eventos globais e integrações
do sistema. O target de deploy é macOS 14.2; no macOS 26 o notch aberto usa o
Liquid Glass nativo com fallback compatível.

## Composição em alto nível

```text
KnoblerMain
  └─ AppDelegate (KnoblerApp.swift)
       ├─ NotchAPIServer ── API local em 127.0.0.1:4477
       ├─ AskStore ───────── estado único de perguntas
       ├─ serviços do sistema
       │    ├─ MediaController / MediaRemoteSource
       │    ├─ DictationController / FluidAudio / Deepgram
       │    ├─ NotificationInterceptor / HUDs / MicMonitor
       │    ├─ CalendarCountdown / Pomodoro / ScheduleEngine
       │    ├─ MirrorController / ScreenshotWatcher / ShelfStore
       │    ├─ LANMessaging / WebhookClient
       │    ├─ Updater ── GitHub Releases + brew/zip
       │    └─ DevAvisosController ── avisos.json no repo (24 h)
       └─ uma NotchWindow + NotchViewModel por display
             └─ NotchView e cards SwiftUI
```

`KnoblerMain` trata apenas os modos headless (`--selfcheck` e
`--download-model`) antes de subir o `NSApplication`. `AppDelegate` compõe os
serviços, conecta callbacks e cria as janelas; ele não deve virar o lugar onde
regras de domínio novas são implementadas.

**Nenhuma permissão é pedida no launch.** A abertura mostra a janela de
boas-vindas (só os passos que esta instalação ainda não viu — ver `Onboarding`)
e, quando ela fecha, o painel Ajustes › Permissões, que é quem pede
Acessibilidade e Calendário. Instalação com `Permission.installIssue` pula o
wizard e vai direto ao painel. Quem depende de Acessibilidade ou de Calendário
repolla o trust a cada 3 s e se liga sozinho quando a concessão chega — não há
relaunch no caminho.

## Ownership de estado

| Estado | Dono atual | Consumidores |
|---|---|---|
| Perguntas, fila, página e respostas | `AskStore` + `AskReducer` | `AskCardView`, `NotchView`, API |
| Pending HTTP de Ask e TTL | `NotchAPIServer` | hook, `AskStore` via efeitos |
| Preferências | `AppSettings` / `UserDefaults` | serviços e Ajustes |
| Estado visual por monitor | `NotchViewModel` | `NotchView`, `NotchWindow` |
| Música atual | `MediaController` | notch e visualizador |
| Mensagens e peers | `MessageStore` / `LANMessaging` | views e janela de entrada |
| Webhooks | `WebhookClient` + Keychain | Ajustes e notificações |
| Agenda | `CalendarCountdown`, `ScheduleEngine` | notch e Ajustes |
| Próximo evento reduzido ao que a UI usa | `CalendarAviso` (sem dependências, por isso testável isolado) | card e pílula do Pomodoro |
| Passos de boas-vindas já vistos | `Onboarding` (sem dependências, por isso testável isolado) | `OnboardingView`, `AppDelegate` |
| Versão disponível e instalação | `Updater` | card do notch e Ajustes › Geral |
| Avisos do desenvolvedor já mostrados | `DevAvisos` (sem dependências, por isso testável isolado) + `avisos.vistos` | card do notch, via `AppDelegate.publicar` |
| Notificações das últimas 24 h (em disco) | `NotificationHistory.shared` | `HistoryListView` |
| Nota rápida (texto, foco, tela dona) | `QuickNote.shared` | `NotchView`, menu da barra |
| Página do preview de link (tela dona) | `LinkPreview.shared` | `LinkPreviewView`, seção Link |
| Conversão esperando confirmação | `ShelfStore.preview` | `ShelfPreviewView` |
| Ordem-base das seções do card | `AppSettings.notchSectionOrder` | `NotchSectionOrder`, Ajustes › Notch |
| Ordem efetiva, seção em foco e trava | `NotchViewModel` (`secoes`, `focus`, `focusLocked`) | `NotchView`, gestos, `GET /status` |

O mesmo estado de Ask é injetado em todas as janelas. Não crie um store por
monitor: uma resposta ou cancelamento precisa vencer uma única vez, mesmo com
dois ou mais monitores.

`LinkPreview` entra na mesma lista por um motivo próprio: ele carrega um
`WKWebView`, e um por monitor significaria N cópias da mesma página gastando rede
e CPU. Como a nota, ele tem tela dona (`hostDisplayID`), escolhida pelo ponteiro
na hora de soltar o link.

Só o link segura o card aberto contra o hover-out (a página é navegável e o
mouse sai dela o tempo todo). A nota apenas atrasa: `atrasoDeFechar` sobe de
0,3 s pra 3 s enquanto o campo está focado, e `fecharPorHoverOut` derruba o
`editing` junto com o `expanded` — sem isso o card não sairia da tela, porque
`mode` devolve `.music` enquanto `typingNote` for true e o campo desenhado
seguraria o `editing` que sustenta o modo. As duas seções cedem o scroll
vertical ao conteúdo, como o histórico já fazia. Quem decide isso é
`NotchViewModel` (`typingNote`, `linkAberto`) e o monitor de scroll no
`AppDelegate` — que também deixa o swipe horizontal sair da nota, soltando a
digitação antes de trocar a seção.

`NotificationHistory` e `QuickNote` seguem a mesma regra e pelo mesmo motivo:
`NotchViewModel.enqueue` roda uma vez por tela com a mesma notificação, então
um histórico por monitor daria N cópias podando cada uma por conta própria
(o `record` deduplica por `id` justamente por isso — e quem constrói a
`NotchNotification` **dentro** do `forEach` das telas gera N ids diferentes e
fura o dedupe). A nota é singleton mas guarda `hostDisplayID`: uma tela dona,
escolhida pelo ponteiro na hora de ligar. Sem esse dono, ligar a nota expandia
todos os monitores sem nada recolhê-los, e as N cópias da `NotchView`
disputavam foco escrevendo no mesmo `editing`.

## Card aberto: uma seção em foco

O card do notch aberto **não empilha** conteúdo. Ele mostra uma seção de cada
vez (Música, Atividade, Pomodoro, Prateleira, Espelho, Mensagens, Histórico,
Nota rápida, Link) e resume **todas** as ativas — a em foco inclusive — numa faixa de
ícones no rodapé, cada um com um sinal vivo mínimo (anel de progresso, contagem,
ponto de "tocando"). O ícone da seção em foco fica aceso e os outros apagados,
que é o que dá noção de posição na faixa.

A ordem sai de três camadas, nesta sequência:

1. **Ordem-base** — arrastável em Ajustes › Notch (`AppSettings.notchSectionOrder`).
2. **Conteúdo** — seção sem conteúdo não entra na faixa, a não ser que esteja
   fixada em Ajustes › Notch (`AppSettings.notchSectionsFixadas`).
3. **Evento recente** — `NotchSectionOrder.ordenar` promove pro topo a seção
   cujo último evento (música trocou, atividade chegou, mensagem entrou) ainda
   está dentro da janela de promoção. Passado o prazo, a ordem volta à base.

A ordem efetiva é congelada na abertura do card (`NotchViewModel.secoes`):
recalcular a cada mudança faria o conteúdo pular debaixo do cursor e mover o
alvo de clique da faixa. Clique num ícone ou swipe horizontal chamam
`focar`/`focarVizinho`, que travam o foco (`focusLocked`) até o notch recolher.
`focoPendente` atende quem pede foco **antes** de o card abrir (clique no card
de mensagem, por exemplo). A nota rápida é modo exclusivo: com ela em foco a
faixa some.

A altura do card é derivada do foco (`NotchView.alturaDaSecao`, que o
`currentSize` consome) e publicada em `NotchViewModel.alturaAtual`, que o
monitor de scroll — fora do SwiftUI — usa pra delimitar a zona do gesto junto
com `NotchGesture.folgaDeHover` e `larguraDoCard`.

## Fluxo de AskUserQuestion

```text
Claude Code
  └─ PreToolUse hook
       └─ POST /ask ──> NotchAPIServer
                           └─ AskStore.enqueue
                                └─ AskReducer
                                     └─ AskCardView
                                          ├─ resolve -> AskStore effect
                                          │              └─ server.resolveAsk
                                          └─ cancel  -> server.cancelAsk
Claude Code <── GET /ask/<id> (polling, leitura única)
```

O reducer é síncrono e puro: não conhece SwiftUI, Network, AppKit ou
`DispatchQueue`. `AskStore` é `@MainActor`/`@Observable` e executa os efeitos
assíncronos. O servidor continua dono do protocolo HTTP, do polling, da
primeira resposta vencedora e dos TTLs.

Invariantes importantes:

- IDs duplicados não entram duas vezes na fila.
- A fila é FIFO.
- Uma resposta intermediária preserva as respostas das páginas anteriores.
- Texto livre vence os labels selecionados naquela pergunta.
- Resposta/cancelamento repetido são no-op.
- Desligar a API invalida callbacks pendentes e limpa a apresentação.

## Ciclo de vida da API local

`AppSettings.localAPI` controla o listener. Quando ligado, o servidor abre
somente `127.0.0.1:4477`; quando desligado, fecha o listener, remove atividades
e perguntas pendentes e invalida callbacks de Ask já agendados. Atividades
expiram após 30 minutos sem atualização; perguntas pendentes expiram após 15
minutos.

## Persistência e fronteiras externas

- Preferências simples ficam em `UserDefaults`.
- Chaves sensíveis (Deepgram e tokens de webhook) ficam no Keychain.
- Histórico e mídia de Mensagens ficam no Application Support local.
- O relay de webhook é um processo Node separado em `relay/`; o app mantém a
  conexão WebSocket e recebe eventos.
- O MediaRemote adapter é vendorado e executado pelo `/usr/bin/perl`; veja
  `Vendor/PROVENANCE.md` antes de atualizar a dependência.

## Regras para adicionar uma feature

1. Defina o ownership do estado antes de criar uma view.
2. Mantenha integração de sistema em um adapter/coordenador separado.
3. Faça a view consumir estado; não replique estado entre monitores.
4. Se houver transições relevantes, extraia domínio puro e deixe efeitos no
   runtime.
5. Adicione o arquivo ao `project.yml` por `xcodegen`, e ao `tools/snapshot.sh`
   se a view isolada depender dele.
6. Atualize o doc da feature, a API/referência afetada e o changelog.

Não adicionar TCA, Swift Package local ou uma abstração genérica só para uma
feature sem evidência de que a escala atual exige isso.
