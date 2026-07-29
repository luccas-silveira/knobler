# 💡 Ideias

Backlog de features futuras do Knobler — coisas que queremos explorar "eventualmente", sem timeline. Ideias são pitches curtos; quando uma vira interessante e pronta pra spec, ganha badge e link para a spec real.

---

## Notch & UI

- **Tema claro no notch**: Modo claro automático durante o dia, escuro à noite baseado no horário ou sensor de luminosidade. Notch se adaptaria ao ambiente sem força manual.

- **Notificações com ações**: Suporte a botões de ação direta no notch — aceitar/rejeitar, delete, archive. Hoje mostram só o título; com ações seria pra valer interativo. ⚠️ Mais caro do que parece: acionar a ação exige o `AXUIElement` do banner **vivo**, e o interceptor fecha o banner justamente pra o notch substituí-lo. Ou o balão do sistema fica na tela (duplicado com o card), ou não há ação. A infra de botão no card já existe (`actionTitles`/`actionToken`) — o nó é esse.

- **Animations suave entre estados**: Transições mais fluidas quando o notch abre/fecha, especialmente a music tab entrando/saindo. Agora é um pouco abrupto.

- **Gestos customizáveis no notch**: Permitir que swipes à esquerda/direita façam coisas diferentes em cada estado (close, voltar, skip track, etc.).

- **Nota rápida no notch**: Sticky note temporário que fica no notch — abre/recolhe com mouse over, auto-delete após 15 min de inatividade (configurável). Totalmente efêmero, sem persistência.

- **Melhorar UI das perguntas do Claude**: Perguntas e respostas do Claude não aparecem inteiras no notch — truncam ou ficam cortadas. Melhorar a layout pra que conteúdo longo seja acessível (scroll, expansão, etc.).

- **Preview de links**: Arrastar URL pro notch e mostrar preview (título, favicon, descrição). Notch se expande mostrando o site navegável dentro com opção de abrir no navegador.

---

## Mídia & Spotify

- **Podcast nativo no notch**: Mostrar podcast que está tocando via Apple Podcasts ou Spotify (cover, título, controles de play/pause/skip). Hoje só cobre músicas.

- **Fila visual do Spotify**: Visualizar próximas 3-5 faixas enfileiradas no notch expandido — útil pra listar o que vem.

- **Integração com YouTube Music**: Além de Spotify, suportar YouTube Music como fonte de now-playing (mesmos controles).

---

## Ditado & Transcrição

- **Editor inline de transcrição**: Editar a transcrição diretamente no notch antes de enviar/salvar (fix typos, remover fillers, etc.).

- **Múltiplos idiomas simultâneos**: Detectar quando fala em português/inglês no meio da transcrição e processar cada parte com o modelo certo.

- **Formatação avançada via IA**: Além de pontuação, a IA poderia sugerir estrutura (listas, parágrafos) e formatar como markdown automaticamente.

---

## Pomodoro & Produtividade

- **Notificações customizáveis ao fim do pomodoro**: Além de áudio, executar webhook ou script (ex: `curl http://localhost:3000/pomodoro-end`).

- **Integração com Calendario**: Ver próximo evento/reunião no notch durante pomodoro — útil pra saber quanto tempo falta até o próximo compromisso.

- **Pomodoro com metas diárias**: Rastrear quantos pomodoros você fez hoje e mostrar progress bar visual no notch.

---

## Lembretes & Notificações

- **Persistir o adiamento**: o card do lembrete já adia 5/30 min, mas o adiamento
  mora na memória — reiniciar o Knobler antes de vencer devolve o lembrete ao
  horário original. Gravar junto do lembrete resolveria.

- **Persistência de notificações**: Salvar histórico de notificações dos últimos 24h — scroll no notch pra ver o que chegou.

- **DND inteligente**: Silenciar notificações automaticamente quando você está em reunião (detecta calendário) ou em uma call (Zoom, Teams).

---

## Mensagens LAN

- **Typings indicator**: Mostrar quando alguém está digitando uma mensagem (com animação no notch).

- **Reações às mensagens**: Emoji reactions em estilo macOS (like no iMessage) — dar like/👍 sem abrir a janela.

- **Busca nas mensagens**: Endpoint `/messages/search?q=texto` pra encontrar conversa antiga.

- **Lista de transmissão**: Selecionar múltiplas pessoas e enviar a mesma mensagem pra todas de uma vez (tipo broadcast/group message).

---

## Webhooks & Automação

- **Webhook para eventos do Knobler**: Dispara payload quando notch abre/fecha, quando música muda, quando você termina um pomodoro, etc. Hoje só recebe; seria legal também enviar.

- **Template de webhook**: Permitir templates customizáveis (`{artist}`, `{track}`, `{status}`) nas payloads mandadas.

- **Retry automático**: Se um webhook falhar, retentar com backoff exponencial (1s, 2s, 4s, 8s).

---

## Backend & API

- **Persistência de estado**: Salvar estado do notch (se tava aberto, qual tab) entre restarts — restaura o contexto.

- **Sync entre máquinas**: Se você tiver Knobler em múltiplos Macs, sincronizar Ajustes, reminders, histórico de mensagens via endpoint central.

- **Estatísticas e analytics**: Endpoint `/stats` que retorna minutos dictados, pomodoros completados, msgs enviadas — useful pra dashboard pessoal.

- **Canal de notificações do desenvolvedor**: Rota endpoint que permite o time enviar notificações pro usuário (novas features, updates críticos, avisos). Notificação aparece no notch e fica persistida; user pode marcar como read/dismiss.

---

## Integrações Externas

- **Apple Notes sync**: Enviar nota criada via ditado direto pro Apple Notes (em vez de só local).

- **Integração com Claude API**: Ditado vai pro Claude, resposta vem no notch — QA rápido sem abrir browser.

- **WhatsApp Web**: Enviar mensagens via WhatsApp direto do notch (parse da URL, login headless).

- **Progresso do AirDrop no notch**: o app já não atrapalha mais o AirDrop (o alerta do sistema fica de pé) e mostra um card de espelho, mas sem barra de progresso da transferência nem ponto de envio fora do shelf (ex.: item na barra de menus com seletor de arquivo).

---

## Câmera & Mirror

- **Filtros no mirror**: Aplicar filtros visuais (blur background, efeitos, B&W) durante transmissão — útil pra conteúdo.

- **Layout PiP do mirror**: Mostrar preview do mirror num canto pequeno do notch enquanto faz outras coisas (não full-screen).

- **Controle de luz virtual**: Simular fotómetro do environment — aumentar/diminuir luz da câmera automaticamente baseado no ambiente.

---

## Performance & Infra

- **Cache agressivo de imagens**: Cachear covers do Spotify, avatares das msgs, etc. por 1 semana — menos hits à rede.

- **Compressão de dados dos webhooks**: Usar gzip na serialização de payloads grandes (histórico de msgs, stats).

- **Profiling de memória**: Dashboard interno mostrando memory footprint do notch, GC stats, thread count — útil pra otimizar.

---

## Utilidades & Conversão

- **Preview da conversão**: o shelf já converte imagem, PDF, vídeo e Markdown pelo menu de contexto, mas às cegas — mostrar o resultado antes de confirmar (e deixar escolher qualidade/resolução) seria o próximo passo. Faltam também tabela e imagem embutida no Markdown → PDF.

---

## Acessibilidade & UX

- **VoiceOver support**: Fazer o notch acessível com Voice Over — descrições, interações por keystroke.

- **Dark mode forçado**: Opção de forçar dark mode mesmo que macOS teja em light mode global.

- **Teclado só**: Navegar o notch via arrow keys, Enter, Esc — useful se mouse falhar.

---

## Experiência & Onboarding

- **Wizard de primeira execução**: Perguntar minimal setup (Spotify login?, ativar ditado?, ativar mensagens?) e ir automatizando.

- **Dicas de hotkeys**: Mostrar dicas inline quando o user abre notch pela primeira vez (⌥ direita pra ditado, etc.).

- **Modo tutorial**: Guiar o user pelos principais recursos com tooltips e highlights — educacional pra novos.

---

## Descartadas

- **Suporte a Windows**: Considerado mas descartado — foco é macOS nativo só.
