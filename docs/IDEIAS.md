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

---

## Integrações Externas

- **WhatsApp Web**: Enviar mensagens via WhatsApp direto do notch (parse da URL, login headless).

- **Progresso do AirDrop no notch**: o app já não atrapalha mais o AirDrop (o alerta do sistema fica de pé) e mostra um card de espelho, mas sem barra de progresso da transferência nem ponto de envio fora do shelf (ex.: item na barra de menus com seletor de arquivo).

---

## Performance & Infra

- **Compressão de dados dos webhooks**: Usar gzip na serialização de payloads grandes (histórico de msgs, stats).

- **Profiling de memória**: Dashboard interno mostrando memory footprint do notch, GC stats, thread count — útil pra otimizar.

---

## Experiência & Onboarding

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
- **Cache agressivo de imagens (em disco)**: descartada em 2026-08-03 depois de
  auditar o código. A premissa estava errada: só existe **um** consumidor de
  imagem de rede — o ícone de notificação de webhook (`RemoteAvatarLoader`, teto
  de 512 KB, `NSCache` em memória já pronto). A capa do Spotify **não** vem da
  rede (chega em base64 pelo MediaRemote) e as mídias das mensagens são locais.
  Cache em disco só pouparia o redownload de um ícone pequeno após reiniciar o
  app.
- **Apple Notes sync** e **Integração com Claude API**: descartadas em 2026-08-03
  pelo dono do projeto. As duas eram destino novo de ditado, e a regra é: o
  ditado só escreve no **campo de texto que a pessoa tem selecionado** — nunca
  num app terceiro, num arquivo ou numa API. Qualquer pitch futuro que crie um
  `case` novo em `DictationDestination` bate nessa regra antes de qualquer coisa.
- **Layout PiP do mirror**: descartada em 2026-07-29 pelo dono do projeto.
- **Controle de luz virtual**: descartada em 2026-07-29 pelo dono do projeto.
- **Dark mode forçado**: descartada em 2026-07-29 pelo dono do projeto.
- **Teclado só**: descartada em 2026-07-29 pelo dono do projeto.
- **Suporte a Windows**: Considerado mas descartado — foco é macOS nativo só.
- **VoiceOver / acessibilidade**: descartado pelo dono do projeto em 2026-07-29.
- **Pomodoro com metas diárias**, **webhook de saída** e **endpoint `/stats`**:
  descartados em 2026-07-29.

- **Foco do macOS como sinal de silêncio**: descartado em 2026-08-03 por custo de
  permissão. O banco de estado (`~/Library/DoNotDisturb/DB/Assertions.json`) é
  protegido por TCC — exigiria Acesso Total ao Disco — e a API oficial
  (`INFocusStatusCenter`) exige a capability restrita *Communication
  Notifications*, com provisioning profile da Apple, enquanto o app assina com
  identidade local. Virou "silenciar durante chamadas", pelo microfone.

## Entregues

- **Silenciar durante chamadas** → o gate de silêncio passou a aceitar um segundo
  gatilho: microfone em uso há mais de 20 s (`docs/notifications.md`). O limiar é
  o que separa call de teste de microfone — e é o que derruba a objeção antiga
  ("o ditado acende o mic"), já que o ditado dura menos que isso.

- **Canal de notificações do desenvolvedor** → virou os avisos do
  desenvolvedor (`docs/avisos.md`), mas **não** pelo relay: `webhookNotifications`
  é opt-in e nasce desligado, então um broadcast só alcançaria quem já pareou.
  Virou polling de um JSON público do repo, que alcança 100% da base sem infra
  nova. O "read/dismiss" do pitch original colapsou em um: o aviso aparece uma
  vez e o id fica registrado. Um estado "não lido" separado pediria badge e
  contador no histórico — não se paga num canal que emite uma vez por mês.
- **Wizard de primeira execução** + **Dicas de hotkeys** → viraram um só: a
  janela de boas-vindas, com o passo do que é o app e o dos dois atalhos
  globais, versionada por passo (`docs/onboarding.md`). O "minimal setup" do
  pedido original foi cortado: não há o que perguntar — ditado e API já nascem
  ligados, Mensagens não tem toggle e Spotify não tem login.
- **Integração com Calendário** → durante o Pomodoro, o próximo evento aparece
  numa linha do card de foco e toma a pílula fechada nos últimos 5 min
  (`docs/pomodoro.md`).
- **Melhorar UI das perguntas do Claude** → resumo e detalhes num bloco rolável
  ao expandir o card, sem truncar (`docs/agent-requests.md`).
- **Preview de links** → virou a seção Link do card (`docs/link-preview.md`).
- **Preview da conversão** → `docs/shelf.md`.
- **DND inteligente** → "silenciar durante reuniões" e, desde a v0.21.0, também
  durante chamadas — microfone aceso há mais de 20 s conta como call
  (`docs/notifications.md`).
- **Progresso do AirDrop** → estado do envio no notch, sem percentual (a API do
  sistema não expõe bytes transferidos).
