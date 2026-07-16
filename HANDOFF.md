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
- [ ] Shelf é em memória (zera ao fechar o app) — persistir se sentir falta.

## Lições da sessão (gravadas também em MEMORY.md)

- Trocar assinatura de código INVALIDA TCC silenciosamente: o tap "nasce" mas fica
  inerte; app lançado pelo terminal HERDA as permissões do shell (falso-positivo
  clássico ao diagnosticar). Correção: health-check recria o tap na transição de
  confiança + `tccutil reset All <bundle>` força prompt limpo.
- OSD de dispositivo do macOS (fone conectou/volume no fone) NÃO é interceptável;
  a pílula só aparece para mudanças iniciadas pelas nossas teclas.
- ImageRenderer não renderiza platform views (`.onDrop`) — placeholder amarelo;
  o harness desliga drop targets.
