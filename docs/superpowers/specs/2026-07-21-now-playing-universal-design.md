# Now playing universal — design

**Data:** 2026-07-21 · **Status:** aprovado em conversa, aguardando revisão do spec

## Problema

O card de música do notch só enxerga Spotify e Apple Music (AppleScript +
`DistributedNotificationCenter`). YouTube no navegador, podcasts, IINA e
qualquer outra fonte que aparece no Control Center ficam invisíveis pro
Knobler.

## Decisão

Substituir o motor inteiro do `MediaController` pelo
[mediaremote-adapter](https://github.com/ungive/mediaremote-adapter)
(BSD 3-Clause) como **fonte única** de now playing. O adapter contorna o
bloqueio do MediaRemote no macOS 15.4+ carregando um framework auxiliar via
`/usr/bin/perl` (binário da Apple com o entitlement necessário) e emite o
estado em JSON no stdout, em tempo real.

Alternativas descartadas:

- **Híbrido** (AppleScript pra Spotify/Music + adapter pro resto): dois
  caminhos de código pra manter; o usuário preferiu um só.
- **Só exibição universal** (sem controles fora de Spotify/Music): card
  "morto" pra YouTube.

## Arquitetura

### Vendoring

- `mediaremote-adapter.pl` + `MediaRemoteAdapter.framework` entram nos
  **Resources** do bundle, declarados no `project.yml`.
- O framework **não é linkado** pelo app — quem o carrega é o perl. Sem
  embed/sign phase.

### `MediaRemoteSource.swift` (novo)

- Envolve um `Process`: `/usr/bin/perl <adapter.pl> <framework> stream`.
- Lê o stdout linha a linha; cada linha é um JSON com o estado
  (`bundleIdentifier`, `playing`, `title`, `artist`, `album`, `duration`,
  `elapsedTime`, `timestamp`, `playbackRate`, `shuffleMode`,
  `artworkData`/`artworkMimeType` em base64…).
- Processo morreu → relança com backoff. Exit code ≠ 0 persistente
  (adapter quebrado por update do macOS) → para de tentar, loga, card fica
  vazio. **Sem crash, degradação silenciosa.**
- Comandos (play/pause/next/prev/shuffle) são invocações one-shot:
  `/usr/bin/perl <adapter.pl> <framework> <comando>`.

### `MediaController` (reescrito por dentro, mesma casca)

- `PlaybackState` mantém os campos atuais (`isPlaying`, `title`, `artist`,
  `album`, `duration`, `position`, `shuffling`) → `NotchView` e o harness de
  snapshot (`injectPreview`) **não mudam**.
- Sai: todo AppleScript, `DistributedNotificationCenter`, download de
  `artworkURL` do Spotify.
- Artwork: base64 do stream → `NSImage`; tint vibrante continua igual.
- `activeBundleID` (usado pelo tap de áudio) vem do `bundleIdentifier`.
- Posição extrapolada localmente com `elapsedTime + timestamp +
  playbackRate` (mesmo papel do `fetchedAt` de hoje).
- Disputa entre players deixa de existir: o MediaRemote reporta o mesmo
  "now playing" do Control Center.

### UI

- Nenhuma mudança de layout.
- Botão de shuffle: fonte sem `shuffleMode` (ex.: YouTube) → botão apagado
  (disabled), não some — layout estável.

## Risco assumido

Framework privado da Apple. Um update do macOS pode quebrar o now playing
inteiro de uma vez (não há fallback AppleScript — decisão consciente do
usuário). Mitigação: monitoramento do exit code + card vazio + log.

## Validação

- `./tools/snapshot.sh` — layout inalterado, snapshots continuam válidos
  (adicionar `MediaRemoteSource.swift` à lista manual do script se a
  `NotchView` passar a referenciá-lo).
- Teste real 1: YouTube no Safari → card com título/capa, play/pause/next
  funcionam, shuffle apagado.
- Teste real 2: Spotify → nada regrediu, incluindo shuffle e tint da capa.
- Teste real 3: matar o processo perl à mão → relança sozinho.
