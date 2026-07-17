# 🏁 SESSÃO 2026-07-16 (tarde) — v0.7: espelho, mic e a saga do OSD do Tahoe

## O que foi feito

- **Espelho** (`Mirror.swift`): preview da câmera no card expandido (espelhado, como
  espelho real) pra se checar antes de reunião. Gatilhos: botão no card, auto-open
  2min antes de evento com link de call (Zoom/Meet/Teams/Webex/Whereby/Jitsi),
  `POST /mirror` na API. Música cede o lugar enquanto aberto; sessão da câmera
  liga/desliga com a view. Prefere a câmera EMBUTIDA (a default era "USB Video").
- **Indicador de microfone** (`MicMonitor.swift`): pontinho laranja no notch fechado
  enquanto qualquer app captura o input padrão (CoreAudio, sem permissão nova).
- **HUD de brilho por qualquer via**: poll 0.5s do brilho da tela embutida →
  pílula aparece pra tecla, Central de Controle e brilho automático.
- **Supressão do OSD nativo do Tahoe** (`OSDSuppressor.swift`): ver lição abaixo —
  a maior descoberta da sessão.

## Lição principal: OSD do Tahoe + tecla de brilho de teclado externo

Root cause confirmada com instrumentação (ring buffer de eventos no /status, sonda
IOHIDManager, watcher CGWindowList):

1. Tecla de brilho de teclado Apple EXTERNO é consumida ABAIXO do CGEventTap —
   nenhum evento chega à sessão. Interceptação é impossível nessa camada (o
   volumeHUD e o boring.notch têm o mesmo ponto cego).
2. O balão do Tahoe é desenhado pelo **ControlCenter** (janela layer 2005), não
   pelo OSDUIHelper — matar ControlCenter não é opção.
3. Fix em duas partes: `EnableSystemBanners=false` (OSD volta ao estilo
   Sequoia/OSDUIHelper; quebra no macOS 27 beta) + congelar OSDUIHelper com
   SIGSTOP (truque do SlimHUD). Aplicado pelo app no launch; restaurado no quit.

Processo que funcionou (usar da próxima vez DESDE O INÍCIO): instrumento com ring
buffer timestampado + validar o instrumento + watcher de janelas pra achar quem
desenha um overlay + ler o fonte dos concorrentes.

## Pendências

- [ ] Commit/push desta sessão (Mirror, MicMonitor, OSDSuppressor, brilho, docs).
- [ ] Teclado EMBUTIDO não testado: teclas de brilho dele podem ainda emitir NX 2/3
      (interceptáveis). Irrelevante na prática — o OSD já está suprimido.
- [ ] macOS 27: EnableSystemBanners deixa de funcionar — reavaliar supressão lá.
- [ ] Seletor de câmera do espelho (hoje: embutida fixa), antecedência configurável.

---

# 🏁 SESSÃO 2026-07-16 — v0.1 → v0.6: do esqueleto ao produto completo

## O que foi feito

Uma sessão-maratona que levou o Knobler de casca com Now Playing a app completo:

- **Harness de validação visual** (`tools/snapshot.sh`): 20 estados renderizados em
  PNG antes de cada entrega de UI. Processo obrigatório: rodar → olhar → só então deploy.
- **Design**: glow da capa no card, HUDs com ícones dinâmicos, sombras, molas
  diferenciadas (abrir com overshoot, fechar seco), crossfade na troca de faixa,
  peek do pausado, Reduced Motion.
- **Visualizador com áudio real**: CoreAudio process tap + FFT 5 bandas, auto-gain
  por banda, cor vibrante da capa. Perf: barras por scaleEffect, 20Hz, ~11% de um
  core tocando / 0,0% parado.
- **HUDs**: som + brilho (DisplayServices) + bateria (IOKit) em TODAS as telas.
- **Apple Music** além do Spotify (MediaController), shuffle real.
- **API local 4477**: /notify, /activity (anel de progresso persistente), /status
  (diagnóstico TCC/tap). CLI `knobler` em /opt/homebrew/bin + integrado ao deploy
  do zoi-studio.
- **Countdown de calendário** (EventKit, 15min antes, anel regressivo).
- **File shelf**: arrastar arquivo pro notch, guarda até 8, arrasta de volta.
- **Gestos** de swipe, **Ajustes** com toggles + login item, **ícone**, **Release
  build**, **repo GitHub privado** (luccas-silveira/knobler).

## Validação

- Harness com 20 cenários verdes; xcodebuild Release SUCCEEDED; app rodando.
- API testada de ponta a ponta com curl (notify, activity com progresso, done).
- Pixel-diff para provar estados estáticos; `GET /status` confirmou
  `axTrusted:true, tapEnabled:true` ao final.

## Pendências e followups

- [ ] Prompts de permissão restantes pós-`tccutil reset All com.zoi.knobler`:
      Automação (Spotify/Music), Gravação de Áudio do Sistema (visualizador),
      Calendário — aprovar quando aparecerem no primeiro uso de cada recurso.
- [ ] zoi-studio-frontend: commit local `0e77a6d` (knobler no deploy.sh) — push pendente.
- [ ] Backlog deprioritizado: AirPods (bateria = BLE reverso), lock screen,
      progresso de downloads, pomodoro nativo (a API já cobre via CLI).
- [x] Shelf persiste em UserDefaults (paths simples; app não é sandboxed).

## Lições da sessão (gravadas também em MEMORY.md)

- Trocar assinatura de código INVALIDA TCC silenciosamente: o tap "nasce" mas fica
  inerte; app lançado pelo terminal HERDA as permissões do shell (falso-positivo
  clássico ao diagnosticar). Correção: health-check recria o tap na transição de
  confiança + `tccutil reset All <bundle>` força prompt limpo.
- OSD de dispositivo do macOS (fone conectou/volume no fone) NÃO é interceptável;
  a pílula só aparece para mudanças iniciadas pelas nossas teclas.
- ImageRenderer não renderiza platform views (`.onDrop`) — placeholder amarelo;
  o harness desliga drop targets.
