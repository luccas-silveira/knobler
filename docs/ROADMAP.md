# 🛤️ Trilhas de implementação

Ordem em que o backlog do [`IDEIAS.md`](IDEIAS.md) deve ser implementado. O
critério é **substrato compartilhado**: cada feature deixa pronta a peça que a
próxima consome.

⚠️ Com a Trilha A descartada (2026-08-03), o que sobra é a lista de itens soltos
— não há mais sequência obrigatória: escolha um e faça.

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

## Trilha A — descartada

O canal autenticado na LAN e o **sync entre máquinas** foram implementados em
2026-08-03 e **revertidos no mesmo dia**, a pedido do dono do projeto. Não foi
falha técnica: o handshake TLS-PSK barrava a chave errada, o merge convergia e os
gates passavam. Foi decisão de produto — pareamento por chave é burocracia demais
pra este app, e Mensagens LAN sem chave é o comportamento desejado, não uma
brecha a fechar.

Cai junto tudo o que dependia do canal pareado: typing indicator, reações às
mensagens, busca nas mensagens e lista de transmissão. Se alguma delas voltar,
volta **sem** exigir pareamento — ou não volta.

A spec do desenho segue em
[`2026-07-29-sync-lan-design.md`](superpowers/specs/2026-07-29-sync-lan-design.md)
como registro do que foi pensado e por quê; não é mais um plano.

## Itens soltos

Não compartilham substrato com ninguém — o "roadmap" deles é escolher um e fazer.

- **Canal de notificações do desenvolvedor** — quase de graça: é um perfil de
  entrada no relay, que já tem fila e dedupe, e o `NotificationHistory` já
  persiste. Falta read/dismiss.
- **Integração com Calendário no pomodoro** — `CalendarCountdown` já lê o
  próximo evento e a permissão já é pedida. Barato.
- **Cache de imagens em disco** — o de memória já existe; falta só disco + TTL.
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
