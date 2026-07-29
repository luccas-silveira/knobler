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
- **Notificações do sistema** interceptadas e exibidas no notch (Acessibilidade),
  com **histórico das últimas 24 h**: puxe o card pra baixo numa passada só.
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
- **Lembretes** programados (únicos, recorrentes ou por intervalo); o card adia
  5 ou 30 min sem abrir os Ajustes. → [detalhes](docs/reminders.md)
- **Prateleira de arquivos**: arraste pro notch, screenshots caem sozinhos;
  botão direito converte (imagem, PDF, vídeo, Markdown — com tabela e imagem
  embutida) e envia por AirDrop.
  → [detalhes](docs/shelf.md)
- **Nota rápida**: campo de texto efêmero no card, ligado pelo menu da barra;
  digitar segura o notch aberto e desligar copia o texto pro clipboard.
  → [detalhes](docs/nota-rapida.md)
- **Conta-gotas**: amostra qualquer cor da tela e copia em HEX.
  → [detalhes](docs/color-picker.md)
- **Mensagens** com outros Macs na rede local (texto, foto, GIF).
  → [detalhes](docs/messages.md)
- **Notificações externas** (webhooks): link próprio por perfil, qualquer
  serviço publica no notch. → [detalhes](docs/webhooks.md)
- **Bateria dos AirPods** por componente ao conectar.
  → [detalhes](docs/airpods.md)
- **Espelho de câmera** antes de reuniões. → [detalhes](docs/mirror.md)
- **Gestos**: dois dedos pra baixo abre, pra cima fecha, horizontal pula faixa;
  puxão longo na mesma passada entra no histórico de notificações.
- **Multi-monitor**: notch real no MacBook, ilha simulada nos externos.
- **API local** (`127.0.0.1:4477`) — o diferencial: qualquer script publica no notch.
  → [detalhes](docs/local-api.md)

Configuração de tudo isso numa janela de Ajustes única. → [detalhes](docs/settings.md)

## Documentação

- [Índice da documentação](docs/index.md) — mapa por objetivo: começar,
  usar, desenvolver e manter.
- [Arquitetura](docs/architecture.md) — ownership de estado, composição e
  fluxo AskUserQuestion.
- [Desenvolvimento](docs/development.md) — build, self-checks, snapshots,
  relay e release.
- [Troubleshooting](docs/troubleshooting.md) — permissões, API local, ditado,
  Ask, câmera e webhooks.
- [Segurança e privacidade](SECURITY.md) — trust boundaries, dados e reporte.
- [Contribuição](CONTRIBUTING.md) — fluxo para mudanças no repositório.

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

O `brew trust` é exigido pelo Homebrew 6+ em taps de terceiros.
Update: o app avisa sozinho quando sai versão nova (card no notch + Ajustes ›
Geral) e instala com um clique — pelo `brew upgrade` se veio do cask, baixando o
zip do release se não. Na mão: `brew upgrade knobler`.
Remover: `brew uninstall --zap knobler`.

Sem Homebrew: baixe o zip do [Releases](https://github.com/luccas-silveira/knobler/releases)
e rode `xattr -dr com.apple.quarantine /Applications/Knobler.app` uma vez.

### Sobre a assinatura

O Knobler **não é notarizado pela Apple**. Ele é assinado com um certificado
próprio, estável entre versões — o que mantém as permissões concedidas de uma
atualização para a outra, mas não é o mesmo que a verificação da Apple.

Na prática isso significa que o macOS não consegue confirmar quem publicou o
app, e por isso o bloqueia no primeiro launch. O cask remove essa marca de
quarentena durante o install para o app abrir. Se você não quiser que um
instalador faça isso por você, baixe o zip do Releases e remova a marca na mão,
depois de conferir o que está instalando — o código-fonte inteiro está aqui e o
build é reproduzível por `./tools/release.sh`.

### Permissões

Todas são pedidas **no primeiro uso do recurso** e podem ser recusadas — recusar
desliga aquele recurso, não o app. O estado de cada uma fica em **Ajustes ›
Permissões** (ver [`docs/settings.md`](docs/settings.md)).

| Permissão | Para quê |
|---|---|
| Acessibilidade | teclas de volume/brilho, gatilho do ditado, colar o texto transcrito |
| Microfone | gravar sua voz durante o ditado |
| Câmera | espelho no notch antes de reuniões |
| Calendários | contagem regressiva do próximo evento |
| Rede local | encontrar outros Macs com Knobler |
| Arquivos e pastas | ler as capturas de tela que vão pra prateleira |
| Gravação de áudio do sistema | visualizador reagindo ao áudio real do player |
| Bluetooth | detectar a conexão dos AirPods pra mostrar a bateria |

A Acessibilidade é a única pedida na abertura: sem ela o `CGEventTap` não existe
e o gatilho do ditado nunca chega ao app. O Bluetooth é pedido logo depois, no
registro do monitor de AirPods, se o recurso estiver ligado em Ajustes › Notch.

O Knobler **não** pede Automação (não usa Apple Events) e **não** pede Gravação
de Tela.

### O que sai da sua máquina

| Quando | Para onde | Como desligar |
|---|---|---|
| Checagem de update, 1×/dia | API do GitHub | Ajustes › Geral |
| Notificações externas | o relay que você configurar | desligado por padrão |
| Ditado em nuvem | Deepgram | desligado por padrão (o ditado roda local) |
| Formatação do transcript | o endpoint que você configurar (padrão: `localhost`) | desligado por padrão |
| Ícone de uma notificação externa | o host da imagem | Ajustes › Notificações externas |

Fora isso, tudo — áudio do ditado, capturas, calendário, mídia — fica na máquina.
A API local escuta só em `127.0.0.1`.

## Build

```bash
./tools/make-signing-cert.sh      # uma vez por máquina
xcodegen generate
xcodebuild -project Knobler.xcodeproj -scheme Knobler -configuration Release build
```

Assinatura `Knobler Local Signing` — a mesma que `tools/release.sh` usa, para que
instalar um build local por cima de um release não derrube a Acessibilidade
([por quê](docs/development.md#instalação-local-do-build)). Permissões pedidas em
runtime: Acessibilidade (teclas + notificações), Gravação de Áudio do Sistema
(visualizador), Automação (Spotify/Music), Calendário.

O passo a passo completo de desenvolvimento e validação está em
[`docs/development.md`](docs/development.md). Não edite o
`Knobler.xcodeproj` manualmente: ele é gerado pelo XcodeGen.

## Validação visual

`tools/snapshot.sh` renderiza todos os estados do notch em `Snapshots/*.png`
(offscreen, com estado fake injetado) — rodar e olhar antes de qualquer mudança de UI.

Duas ressalvas conhecidas, as duas descobertas na v0.13.0:

- **Nem toda view renderiza offscreen.** `ScrollView`, `TextField`/`TextEditor`,
  `NavigationSplitView` e `NSWorkspace.icon(forFile:)` dependem de um `NSView`
  real e saem em preto ou como ícone de "proibido". Cenário novo que use um
  desses não vira snapshot — vira screenshot manual. A lista completa está no
  `CLAUDE.md`.
- **Quatro PNGs não são determinísticos**: `closed-music`,
  `closed-music-external`, `expanded-activity-only` e `update-installing` mudam
  de hash a cada rodada mesmo sem mudança de código (visualizador animado,
  barra de progresso). Neles o snapshot serve de inspeção visual, não de
  detector de regressão — não perca tempo caçando um diff que não existe.

## Consumo

Medido em Release com 3 monitores: ~11% de um core com música tocando
(visualizador a 20Hz), 0,0% parado, ~22MB de RAM.

## Licença

[MIT](LICENSE). O `Vendor/MediaRemoteAdapter.framework` tem proveniência
própria — ver [`Vendor/PROVENANCE.md`](Vendor/PROVENANCE.md).
