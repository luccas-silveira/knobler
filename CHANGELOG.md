# Changelog

Formato baseado em [Keep a Changelog](https://keepachangelog.com/pt-BR/1.1.0/);
versionamento por [Semantic Versioning](https://semver.org/lang/pt-BR/).
Regras de bump em [VERSIONING.md](VERSIONING.md).

## [Unreleased]

### Fixed
- **Ditado parava de funcionar a cada release, de vez**: o `release.sh`
  re-assinava o app ad-hoc (`codesign --sign -`). Sem identidade estável o TCC
  ancora a permissão de Acessibilidade no `cdhash`, então toda versão nova
  invalidava a concessão (`tccd: Failed to match existing code requirement`) —
  o `CGEventTap` não era criado e a ⌥ direita nunca chegava ao ditado. Agora o
  release assina com um certificado local fixo, criado uma vez por
  `tools/make-signing-cert.sh`; o `csreq` gravado pelo TCC passa a casar entre
  builds. Sem o certificado, o release ainda sai (ad-hoc) mas avisa. Quem já
  acumulou concessões stale limpa com
  `tccutil reset Accessibility com.zoi.knobler` e reconcede uma última vez.

## [0.8.3] - 2026-07-22

### Added
- **Escolha da câmera do espelho**: uma setinha no canto do preview abre a lista
  das entradas de vídeo da máquina (embutida, USB, OBS Virtual Camera, Câmera de
  Continuidade, Desk View) — antes o espelho sempre pegava a FaceTime HD. A
  setinha só aparece quando há mais de uma câmera. Em "Automática" o
  comportamento é o de sempre. A escolha é guardada pelo
  `uniqueID` do device (índice quebraria quando um USB entra/sai) e cai de volta
  pra embutida se a câmera escolhida sumir. Trocar com o espelho aberto reponta
  a sessão na hora, sem fechar o notch.

## [0.8.2] - 2026-07-22

### Fixed
- **Ditado morria em silêncio depois de um update**: o release é assinado
  ad-hoc, então o TCC ancora a permissão de Acessibilidade no cdhash e a
  revoga a cada versão nova. Sem Acessibilidade o `CGEventTap` nem é criado
  e o `flagsChanged` da ⌥ direita nunca chega ao ditado — nenhuma pílula,
  nenhum log. Agora o app detecta isso no launch, dispara o prompt do sistema
  e mostra a pílula "Ditado precisa de Acessibilidade". Reconceder em Ajustes
  › Privacidade e Segurança › Acessibilidade volta a valer na hora (o
  `checkTapHealth` recria o tap sozinho, sem reiniciar o app).

### Added
- **Documentação de usuário** (`docs/*.md`): um arquivo por feature (Now
  Playing, HUDs, Notificações, Countdown de Calendário, Ditado, Ask,
  Pomodoro, Descanso, Lembretes, Shelf, Mensagens, Webhooks, API local,
  AirPods, Mirror, Ajustes), cada um com descrição, modo de uso, permissões
  e screenshot real (`docs/images/`). README linka cada feature pro doc
  correspondente.

## [0.8.0] - 2026-07-21

### Changed
- **Ajustes redesenhados no estilo do Ajustes do Sistema**: a janela deixou o
  `TabView` 400×580 e virou `NavigationSplitView` (800×520, redimensionável)
  com sidebar de 8 painéis e ícones coloridos — Geral, Notch, Ditado, Pomodoro,
  Lembretes, Descanso, Notificações externas e Mensagens. A antiga aba "Geral"
  (parede de 20+ controles) foi dividida em quatro painéis; todo toggle agora é
  switch com descrição do que faz; sub-opções dependentes ficam desabilitadas
  em vez de escondidas. O menu do Pomodoro abre os Ajustes direto no painel
  Pomodoro. (`SettingsView.swift` novo; `AppSettings.swift`, `KnoblerApp.swift`.)
- **Notificações externas**: aba refeita como Form agrupado; ações de cada
  perfil (mapear, rotacionar, apagar) num menu "…" e copiar link virou ícone.
  Ícone de perfil que era URL de imagem não quebra mais o layout da lista.
  `ProfilesListView.swift` foi fundido em `WebhookSettingsView.swift`.
- **Lembretes/Descanso**: linhas com menu de contexto (Editar/Apagar), switch
  compacto e botão rotulado "Novo lembrete"/"Novo bloqueio" no rodapé.
- **Mensagens**: botão "Remover" foto de perfil (novo
  `AppSettings.removeMyAvatar()`); avatar maior no painel.

### Added
- Flag de desenvolvimento `--ajustes[=painel]` abre a janela de Ajustes direto
  (usada pelos screenshots de UI).

### Fixed
- Perfis de webhook: falha de rede não "esvazia" mais a lista carregada
  (`listProfiles` agora distingue erro de zero perfis), reload automático ao
  reconectar, respostas atrasadas de reloads antigos são descartadas e criar
  perfil com o relay fora do ar não come mais o nome digitado.
- Remover a foto de perfil agora propaga: peer que responde o perfil sem foto
  tem o avatar limpo do cache dos outros Macs (`MessageStore.removeAvatar`).

## [0.7.0] - 2026-07-21

### Added
- **Anexo por link nas Mensagens LAN**: botão 🔗 no composer transforma o campo
  de mensagem em campo de URL; o app baixa a imagem/GIF (https, link direto,
  timeout 15 s), valida pelos bytes mágicos e anexa pelo pipeline existente —
  o fio não muda e o destinatário nunca toca a URL.
  (`MessagesView.swift`, `MessageMedia.swift`.)

## [0.6.0] - 2026-07-21

### Changed
- **Now playing universal**: o card de música agora mostra e controla qualquer
  fonte de mídia do macOS (YouTube no navegador, podcasts, IINA…), não só
  Spotify/Apple Music. Motor novo: mediaremote-adapter v0.7.6 vendorado
  (framework carregado via `/usr/bin/perl`, contornando o bloqueio do
  MediaRemote no 15.4+; ver `Vendor/PROVENANCE.md`). O AppleScript saiu; se um
  update da Apple quebrar o adapter, o card fica vazio sem derrubar o app.
  Shuffle aparece apagado quando a fonte não reporta (navegador); barra de
  progresso lida com duração desconhecida (live). A capa agora chega em base64
  pelo próprio stream (sem download da URL do Spotify).
  (`MediaRemoteSource.swift`, `MediaController.swift` reescrito por dentro.)

### Removed
- `NSAppleEventsUsageDescription` do Info.plist — nada mais usa AppleScript.

## [0.5.0] - 2026-07-21

### Changed
- **Card de música enxugado**: a barra de abas "Música | Mensagens" saiu. A troca
  de tela agora é por swipe horizontal de dois dedos sobre o card aberto, com um
  par de pontinhos discretos no rodapé como indicador (também clicáveis). Com o
  notch fechado, o mesmo gesto continua pulando faixa.
- A bateria dos AirPods saiu do card expandido: aparece só no card transitório de
  conexão e quando algum componente cai a ≤10%.
- O botão do espelho saiu de junto do título e assumiu o 5º slot dos controles,
  no lugar do atalho pros Ajustes de Som.

### Removed
- Barras de áudio do card expandido (o notch fechado já as mostra) e o botão que
  abria os Ajustes de Som.

## [0.4.0] - 2026-07-21

### Added
- **Foto e GIF nas Mensagens LAN**: botão de anexo no compositor manda uma imagem
  (JPEG/PNG/GIF) pro outro Mac; ela aparece no card que desce do notch e no balão
  da conversa, com GIF animando. Imagem grande é reamostrada pra 1600 px/JPEG antes
  de ir; GIF vai cru pra não perder a animação (teto de 6 MB). O recebedor valida
  os bytes mágicos contra o tipo declarado e grava em `media/` com nome gerado
  localmente. (`MessageMedia.swift`, `MediaKind` em `Wire.swift`.)
- GIF acima do teto é reamostrado mantendo a animação (reduz o lado maior e,
  se preciso, pula quadros somando o tempo do quadro pulado) — um GIF de 46 MB
  do Giphy vira 5,7 MB e continua girando.

### Fixed
- **Card de mensagem não sumia mais da tela**: com resposta permitida ele ficava
  para sempre. Agora some em 20 s (6 s sem resposta), com o relógio pausado
  enquanto o ponteiro está sobre o card.
- **Fechar o card fechava só num monitor**: o X (e abrir a conversa) agora vale
  para todas as telas, como a resposta rápida já fazia.
- **Pacote acima de 64 KB era descartado calado**: `NWConnection` não entrega
  mais que isso por `receive`, e pedir o corpo inteiro de uma vez fazia a leitura
  falhar sem erro — nenhuma imagem passaria. O corpo agora é lido em pedaços, e o
  tempo-limite da troca subiu de 5 s para 20 s (anexo de MBs em Wi-Fi ruim).

## [0.3.0] - 2026-07-21

### Added
- **Mensagens LAN**: descubra outros Macs com Knobler na mesma rede e mande recados
  que aparecem no notch da pessoa, com nome e foto. Aba Mensagens no notch aberto,
  recado com ou sem resposta, histórico das últimas 20 conversas por pessoa.
  Identidade (nome/foto) configurável, pré-preenchida com a da conta do macOS.
- **Webhooks configuráveis (mapeamento por perfil)**: cada fonte externa (GitHub,
  Stripe, n8n…) vira um perfil com link próprio; manda um webhook de teste e um
  editor lado-a-lado mapeia os campos da notificação a partir do payload capturado
  (texto livre + `{{ variáveis }}` do payload, aninhado). Ícone fixo por perfil
  (URL ou emoji). O relay guarda o template e aplica; o app tem a lista de perfis +
  o editor com árvore do payload clique-pra-inserir e preview ao vivo.
  (`template.js`/`profiles` no relay; `MappingEditorView`/`ProfilesListView` no app.)
- **Notificações externas via webhook**: cada dispositivo tem um link próprio
  (`https://push.appzoi.com.br/w/<token>`) que recebe título, descrição, avatar
  e ação de clique, exibidos como card no notch. Relay próprio na VPS (Node/pm2
  atrás do nginx, TLS) + WebSocket que o Mac mantém aberto (reconecta sozinho,
  fila offline). Opt-in em Ajustes › Notificações externas (link + copiar +
  rotacionar + toggle de imagens remotas). Avatar remoto com guardas
  (só https, content-type de imagem, teto de tamanho, bloqueio de IP privado);
  clique abre só http/https. (`WebhookClient.swift`, `RemoteAvatarLoader.swift`,
  `WebhookKeychainStore.swift`, `WebhookSettingsView.swift`, `relay/`.)
- **AirPods no notch**: ao conectar, card transitório (~4s) com nome + bateria
  L / R / estojo; enquanto conectado, bateria no hover (faixinha junto da música,
  card dedicado quando não há música). Aviso de bateria baixa (≤10%) e toggle
  opt-out "AirPods no notch". (`AirPodsBattery.swift`, `BluetoothMonitor.swift` via
  `IOBluetooth` event-driven + `system_profiler` off-main.)
- `NSBluetoothAlwaysUsageDescription` no Info.plist (TCC exigia para o
  `system_profiler`/`IOBluetooth`).

## [0.2.2] - 2026-07-20

### Changed
- Progresso streaming do `--download-model` no `brew install`: stdout unbuffered
  (`setvbuf _IONBF`) + progresso por fase e monotônico (% no download,
  "compilando <modelo>…" na compilação CoreML). O install não fica mais mudo.
- Cask com `print_stderr: false` para esconder o ruído `[INFO]` do FluidAudio.

## [0.2.1] - 2026-07-20

### Fixed
- Crash determinístico do ditado em devices de formato de áudio estranho
  (Bluetooth/áudio virtual): `AVAudioEngine.installTap` lançava **NSException do
  ObjC**, que o `try/catch` do Swift não captura → `abort()`. Shim ObjC
  `ObjCException` converte a NSException em `Error`; `MicRecorder.start()` trata
  gracioso ("Sem acesso ao microfone") em vez de abortar.

## [0.2.0] - 2026-07-20

### Added
- Provisionamento do modelo de ditado no install: modo headless
  `Knobler --download-model` baixa o Parakeet (~461MB) para o cache do FluidAudio
  e sai, sem subir o `NSApp` (interceptado no topo de `KnoblerMain.main()`). Modo
  `--selfcheck`. O `postflight` do cask roda `--download-model` (best-effort;
  offline não quebra o install → fallback no launch). Primeiro ditado instantâneo.

## [0.1.0] - 2026-07-20

Primeira release pública (open-source), distribuída via Homebrew tap.

### Added
- **Now Playing** (Spotify/Apple Music): capa + visualizador no notch fechado;
  hover expande com controles, progresso e shuffle.
- **Visualizador com áudio real**: CoreAudio process tap no player + FFT em 5
  bandas, tingido pela cor da capa.
- **HUDs no notch**: volume, brilho e bateria substituem o OSD nativo.
- **Notificações do sistema** interceptadas e exibidas no notch.
- **Countdown de calendário**: próximo evento entra 15min antes com anel regressivo.
- **Ditado por voz** (FluidAudio/Parakeet) com formatação IA local opcional
  (Ollama/gemma3:4b) — remove fillers e conserta pontuação/acentos.
- **Pomodoro**, **shelf de capturas** com drag, **gestos**, **multi-monitor**.
- **API HTTP local** (`127.0.0.1:4477`): `/notify` e `/activity` — qualquer script
  publica no notch. CLI `tools/knobler` incluído.
- **Distribuição**: `tools/release.sh` (build → assina ad-hoc → zip → GitHub
  Release → bump do cask) + tap `homebrew-knobler` (cask com `postflight`/`zap`).
