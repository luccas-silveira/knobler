# 💡 Ideias

Backlog de features futuras do Knobler — coisas que queremos explorar "eventualmente", sem timeline. Ideias são pitches curtos; quando uma vira interessante e pronta pra spec, ganha badge e link para a spec real.

A **ordem** de implementação (agrupada por infra compartilhada) mora em
[`ROADMAP.md`](ROADMAP.md).

---

## Notch & UI

- **Notificações com ações**: Suporte a botões de ação direta no notch — aceitar/rejeitar, delete, archive. Hoje mostram só o título; com ações seria pra valer interativo. ⚠️ Mais caro do que parece: acionar a ação exige o `AXUIElement` do banner **vivo**, e o interceptor fecha o banner justamente pra o notch substituí-lo. Ou o balão do sistema fica na tela (duplicado com o card), ou não há ação. A infra de botão no card já existe (`actionTitles`/`actionToken`) — o nó é esse.

- **Animations suave entre estados**: Transições mais fluidas quando o notch abre/fecha, especialmente a music tab entrando/saindo. Agora é um pouco abrupto.

---

## Pomodoro & Produtividade

- **Notificações customizáveis ao fim do pomodoro**: Além de áudio, executar webhook ou script (ex: `curl http://localhost:3000/pomodoro-end`).

- **Integração com Calendario**: Ver próximo evento/reunião no notch durante pomodoro — útil pra saber quanto tempo falta até o próximo compromisso.

---

## Mensagens LAN

- **Typings indicator**: Mostrar quando alguém está digitando uma mensagem (com animação no notch).

- **Reações às mensagens**: Emoji reactions em estilo macOS (like no iMessage) — dar like/👍 sem abrir a janela.

- **Busca nas mensagens**: Endpoint `/messages/search?q=texto` pra encontrar conversa antiga.

- **Lista de transmissão**: Selecionar múltiplas pessoas e enviar a mesma mensagem pra todas de uma vez (tipo broadcast/group message).

---

## Webhooks & Automação

- **Template de webhook**: Permitir templates customizáveis (`{artist}`, `{track}`, `{status}`) nas payloads mandadas.

- **Retry automático**: Se um webhook falhar, retentar com backoff exponencial (1s, 2s, 4s, 8s).

---

## Backend & API

- **Persistência de estado**: Salvar estado do notch (se tava aberto, qual tab) entre restarts — restaura o contexto.

- **Canal de notificações do desenvolvedor**: Rota endpoint que permite o time enviar notificações pro usuário (novas features, updates críticos, avisos). Notificação aparece no notch e fica persistida; user pode marcar como read/dismiss.

---

## Integrações Externas

- **Apple Notes sync**: Enviar nota criada via ditado direto pro Apple Notes (em vez de só local).

- **Integração com Claude API**: Ditado vai pro Claude, resposta vem no notch — QA rápido sem abrir browser.

- **WhatsApp Web**: Enviar mensagens via WhatsApp direto do notch (parse da URL, login headless).

- **Progresso do AirDrop no notch**: o app já não atrapalha mais o AirDrop (o alerta do sistema fica de pé) e mostra um card de espelho, mas sem barra de progresso da transferência nem ponto de envio fora do shelf (ex.: item na barra de menus com seletor de arquivo).

---

## Performance & Infra

- **Cache agressivo de imagens**: Cachear covers do Spotify, avatares das msgs, etc. por 1 semana — menos hits à rede.

- **Compressão de dados dos webhooks**: Usar gzip na serialização de payloads grandes (histórico de msgs, stats).

- **Profiling de memória**: Dashboard interno mostrando memory footprint do notch, GC stats, thread count — útil pra otimizar.

---

## Experiência & Onboarding

- **Wizard de primeira execução**: Perguntar minimal setup (Spotify login?, ativar ditado?, ativar mensagens?) e ir automatizando.

- **Dicas de hotkeys**: Mostrar dicas inline quando o user abre notch pela primeira vez (⌥ direita pra ditado, etc.).

- **Modo tutorial**: Guiar o user pelos principais recursos com tooltips e highlights — educacional pra novos.

---

## Descartadas

- **Tema claro no notch**: descartada em 2026-07-29 pelo dono do projeto.
- **Gestos customizáveis no notch**: descartada em 2026-07-29 pelo dono do projeto.
- **Podcast nativo no notch**: descartada em 2026-07-29 pelo dono do projeto.
- **Fila visual do Spotify**: descartada em 2026-07-29 pelo dono do projeto.
- **Integração com YouTube Music**: descartada em 2026-07-29 pelo dono do projeto.
- **Editor inline de transcrição**: descartada em 2026-07-29 pelo dono do projeto.
- **Múltiplos idiomas simultâneos**: descartada em 2026-07-29 pelo dono do projeto.
- **Formatação avançada via IA**: descartada em 2026-07-29 pelo dono do projeto.
- **Filtros no mirror**: descartada em 2026-07-29 pelo dono do projeto.
- **Sync entre máquinas** (e o pareamento por chave que ela exigia): descartada
  em 2026-08-03 pelo dono do projeto, depois de implementada e revertida. O
  motivo não foi técnico — funcionou, com o canal TLS-PSK e o merge convergindo.
  Foi de produto: pareamento por chave é burocracia pra um app que se usa sem
  configurar nada, e as Mensagens LAN abertas (sem chave) são um recurso, não um
  defeito a ser corrigido. Com ela caem também: typing indicator, reações, busca
  nas mensagens e lista de transmissão enquanto dependerem de canal pareado.
- **Layout PiP do mirror**: descartada em 2026-07-29 pelo dono do projeto.
- **Controle de luz virtual**: descartada em 2026-07-29 pelo dono do projeto.
- **Dark mode forçado**: descartada em 2026-07-29 pelo dono do projeto.
- **Teclado só**: descartada em 2026-07-29 pelo dono do projeto.
- **Suporte a Windows**: Considerado mas descartado — foco é macOS nativo só.
- **VoiceOver / acessibilidade**: descartado pelo dono do projeto em 2026-07-29.
- **Pomodoro com metas diárias**, **webhook de saída** e **endpoint `/stats`**:
  descartados em 2026-07-29.

## Entregues

- **Melhorar UI das perguntas do Claude** → resumo e detalhes num bloco rolável
  ao expandir o card, sem truncar (`docs/agent-requests.md`).
- **Preview de links** → virou a seção Link do card (`docs/link-preview.md`).
- **Preview da conversão** → `docs/shelf.md`.
- **DND inteligente** → "silenciar durante reuniões" (`docs/notifications.md`).
- **Progresso do AirDrop** → estado do envio no notch, sem percentual (a API do
  sistema não expõe bytes transferidos).
