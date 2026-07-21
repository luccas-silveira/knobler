# Changelog

Formato baseado em [Keep a Changelog](https://keepachangelog.com/pt-BR/1.1.0/);
versionamento por [Semantic Versioning](https://semver.org/lang/pt-BR/).
Regras de bump em [VERSIONING.md](VERSIONING.md).

## [Unreleased]

### Added
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
