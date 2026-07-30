# 🛤️ Trilhas de implementação

Ordem em que o backlog do [`IDEIAS.md`](IDEIAS.md) deve ser implementado. O
critério é **substrato compartilhado**: cada feature deixa pronta a peça que a
próxima consome.

⚠️ A primeira versão deste arquivo (2026-07-29) foi escrita **sem ler o código** e
errou em quase tudo: inventou uma camada de envio de webhooks que não existe e
prometeu criar quatro substratos que já estavam escritos. Auditado contra o
código no mesmo dia; o que sobrou está abaixo. **Nada entra aqui sem passar pelo
código primeiro.**

## O que já existe (não confundir com backlog)

Peças que um roadmap ingênuo tenta "criar" e que já estão em produção:

| Peça | Onde |
|---|---|
| Interpolação de template (`{{ dot.path }}`) | `relay/src/template.js` + `MappingEditorView` |
| Backoff exponencial com jitter | `WebhookClient.scheduleReconnect()` |
| Fila offline com dedupe, TTL 24 h, cap 50 | `relay/src/db.js` (`enqueue`/`drainQueue`) |
| Persistência Codable + debounce + `arquivo: URL?` nil pra teste | `NotificationHistory`, `MessageStore` |
| Card que cresce (expandir + `ScrollView` + "Ver detalhes") | `AgentRequestCard` |
| Botões de ação no card (`actionTitles`/`actionToken`) | `NotchNotification`, usado pelos lembretes |
| Sink de destino do ditado (`.ask` / `.application`) | `DictationDestination` |
| Cliente HTTP OpenAI-compatível pro ditado | `TranscriptFormatter` + `formatEndpoint` |
| Leitura real de eventos do calendário (EventKit) | `CalendarCountdown` |
| Cache de avatar em memória (`NSCache`) | `RemoteAvatarLoader` |

Webhook **de saída** foi descartado (`IDEIAS.md`), e com ele saíram template de
payload, gzip e o webhook de fim de pomodoro.

---

## Trilha A — Canal autenticado na LAN

A única sequência real: o passo 1 é pré-requisito de segurança dos outros, e
não existe no código.

1. **Pareamento + TLS-PSK em serviço Bonjour próprio** — `LANMessaging.serve()`
   hoje não autentica ninguém. Spec:
   [`2026-07-29-sync-lan-design.md`](superpowers/specs/2026-07-29-sync-lan-design.md).
   Deixa pronto: canal autenticado, `Frame` genérico, `SyncPacket` versionado.
2. **Sync entre máquinas** (lembretes + Ajustes com allowlist + histórico com
   mídia) — LWW-Element-Set com HLC e tombstones. Consome o passo 1 inteiro.
3. **Typing indicator** — primeiro `case` leve fora da thread. Depois do canal,
   porque evento de peer não pareado é ruído injetável.
4. **Reações às mensagens** — mesmo canal do passo 3, agora persistido no
   `MessageStore`; botão no card já existe.
5. **Busca nas mensagens** (`/messages/search?q=`) — índice no `MessageStore`.
   Deixa pronto: consulta sobre o store.
6. **Lista de transmissão** — multi-seleção de peers + fan-out do send. Por
   último: aproveita a seleção e o store indexado.

## Itens soltos

Não compartilham substrato com ninguém — o "roadmap" deles é escolher um e fazer.

- **Canal de notificações do desenvolvedor** — quase de graça: é um perfil de
  entrada no relay, que já tem fila e dedupe, e o `NotificationHistory` já
  persiste. Falta read/dismiss.
- **Integração com Calendário no pomodoro** — `CalendarCountdown` já lê o
  próximo evento e a permissão já é pedida. Barato.
- **Cache de imagens em disco** — o de memória já existe; falta só disco + TTL.
- **UI das perguntas do Claude** — ajuste de layout no `AgentRequestCard`, que já
  expande e já rola.
- **Notificações com ações** — ⚠️ travado no `AXUIElement` do banner vivo (ver
  `IDEIAS.md`); a infra de botão já está pronta.
- **Apple Notes sync** — um `case` novo em `DictationDestination`.
- **Integração com Claude API** — trocar `formatEndpoint`/`formatModel`; está
  mais perto de configuração que de feature.
- **WhatsApp Web** — mais um destino de ditado.
- **Progresso do AirDrop no notch** — isolado.
- **Profiling de memória** — isolado.
- **Animações suaves entre estados** — **último de tudo**: toca todos os estados,
  feito antes é refeito a cada view nova.
