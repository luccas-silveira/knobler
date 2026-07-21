# Knobler

Dynamic Island para o notch do Mac — nativo, Swift/SwiftUI, macOS 14.2+.

![ícone](Knobler/AppIcon.icns)

## O que faz

- **Now Playing** (Spotify e Apple Music): capa + visualizador no notch fechado;
  hover expande com controles, progresso e shuffle. Música pausada se esconde;
  hover "espia" antes de abrir. → [detalhes](docs/now-playing.md)
- **Visualizador com áudio real**: CoreAudio process tap no player + FFT em 5
  bandas — as barras dançam com a música de verdade, tingidas pela cor da capa.
- **HUDs no notch**: volume, brilho e bateria (carregador/20%) substituem o OSD
  nativo. → [detalhes](docs/huds.md)
- **Notificações do sistema** interceptadas e exibidas no notch (Acessibilidade).
  → [detalhes](docs/notifications.md)
- **Countdown de calendário**: próximo evento entra 15min antes com anel regressivo.
  → [detalhes](docs/calendar-countdown.md)
- **Ditado** estilo Superwhisper com limpeza opcional por IA local.
  → [detalhes](docs/dictation.md)
- **Perguntas do Claude Code** (`AskUserQuestion`) viram card interativo no notch.
  → [detalhes](docs/ask.md)
- **Pomodoro**. → [detalhes](docs/pomodoro.md)
- **Descanso**: bloqueio de tela programado (ex.: hora do almoço).
  → [detalhes](docs/descanso.md)
- **Lembretes** programados (únicos, recorrentes ou por intervalo).
  → [detalhes](docs/reminders.md)
- **Prateleira de arquivos**: arraste pro notch, screenshots caem sozinhos.
  → [detalhes](docs/shelf.md)
- **Mensagens** com outros Macs na rede local (texto, foto, GIF).
  → [detalhes](docs/messages.md)
- **Notificações externas** (webhooks): link próprio por perfil, qualquer
  serviço publica no notch. → [detalhes](docs/webhooks.md)
- **Bateria dos AirPods** por componente ao conectar.
  → [detalhes](docs/airpods.md)
- **Espelho de câmera** antes de reuniões. → [detalhes](docs/mirror.md)
- **Gestos**: dois dedos pra baixo abre, pra cima fecha, horizontal pula faixa.
- **Multi-monitor**: notch real no MacBook, ilha simulada nos externos.
- **API local** (`127.0.0.1:4477`) — o diferencial: qualquer script publica no notch.
  → [detalhes](docs/local-api.md)

Configuração de tudo isso numa janela de Ajustes única. → [detalhes](docs/settings.md)

## API local

```bash
# notificação (card temporário)
curl -X POST localhost:4477/notify \
  -d '{"title":"Deploy finalizado","body":"em produção","app":"Terminal"}'

# live activity persistente (anel de progresso na asinha)
curl -X POST localhost:4477/activity \
  -d '{"id":"deploy","title":"Deploy","detail":"rsync","progress":0.4}'
curl -X POST localhost:4477/activity -d '{"id":"deploy","done":true}'
```

CLI incluído (`tools/knobler`, instalar no PATH):

```bash
knobler notify "Título" ["corpo"] ["app"]
knobler activity <id> <0-100|-> "Título" ["detalhe"]
knobler done <id>
```

## Instalação

```bash
brew tap luccas-silveira/knobler && brew trust luccas-silveira/knobler && brew install knobler
```

App assinado ad-hoc (sem Developer ID). O `brew trust` é exigido pelo Homebrew 6+
em taps de terceiros; o cask tira a quarentena no install, então abre limpo.
Update: `brew upgrade knobler` · Remover: `brew uninstall --zap knobler`.

Sem Homebrew: baixe o zip do [Releases](https://github.com/luccas-silveira/knobler/releases)
e rode `xattr -dr com.apple.quarantine /Applications/Knobler.app` uma vez.

Permissões pedidas em runtime: Acessibilidade, Gravação de Áudio do Sistema,
Automação (Spotify/Music), Calendário, Mic, Bluetooth.

## Build

```bash
xcodegen generate
xcodebuild -project Knobler.xcodeproj -scheme Knobler -configuration Release build
```

Assinatura Apple Development (ajuste `CODE_SIGN_IDENTITY`/`DEVELOPMENT_TEAM` no
`project.yml`). Permissões pedidas em runtime: Acessibilidade (teclas + notificações),
Gravação de Áudio do Sistema (visualizador), Automação (Spotify/Music), Calendário.

## Validação visual

`tools/snapshot.sh` renderiza todos os estados do notch em `Snapshots/*.png`
(offscreen, com estado fake injetado) — rodar e olhar antes de qualquer mudança de UI.

## Consumo

Medido em Release com 3 monitores: ~11% de um core com música tocando
(visualizador a 20Hz), 0,0% parado, ~22MB de RAM.
