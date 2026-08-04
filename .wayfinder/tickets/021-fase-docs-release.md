# Fase 5 — filtros na prévia, docs, imagens e release

- map: ../map.md
- label: wayfinder:task
- status: in-progress
- assignee: claude
- blocked-by: 016, 020

## Question

- Prévia do app passa a usar os três filtros via `WebhookTemplate.swift`
  (espelho do relay já coberto por `templatecheck`).
- `docs/webhooks.md` (~90 linhas, arquivo único): "Como usar" começa pelo
  assistente como porta única, dizendo o escape "Outro serviço (sem preset)";
  seção **Presets** (o que é, ressalvas por caminho, reaplicar é manual);
  seção **Filtros no template** (os três, um exemplo cada, falha suave).
- Imagens, todas à mão via `Knobler --ajustes=webhooks` + `screencapture -l<id>`,
  corte `802x554+55+37`: recapturar `settings-webhooks.png` e
  `mapping-editor.png`, criar `assistente-servico.png`.
- `./tools/check.sh` verde, depois `./tools/release.sh minor`.
