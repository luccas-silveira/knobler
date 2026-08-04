# Fase 5 — filtros na prévia, docs, imagens e release

- map: ../map.md
- label: wayfinder:task
- status: closed
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

## Resolução

- Item (a) já estava em pé desde a Fase 1: a prévia usa `WebhookTemplate.swift`,
  os mesmos três filtros do relay, com gate `templatecheck`.
- `docs/webhooks.md` reescrito em arquivo único: "Como usar" começa pelo
  assistente (cinco passos, o escape "Outro serviço (sem preset)" nomeado no
  passo Serviço), mais a subseção do editor de mapa (árvore, Recarregar,
  sugestões automáticas), a seção **Presets** (tabela dos quatro caminhos, por
  que o mesmo serviço repete, ressalva, reaplicar é manual) e a seção
  **Filtros no template** (`semHifens`, `data`, `quill`, um exemplo cada,
  falha suave).
- Imagens à mão com a build Debug rodando: `settings-webhooks.png` e
  `mapping-editor.png` recapturadas, `assistente-servico.png` criada. Desvio de
  receita: `screencapture -l<id>` devolve a janela **reescalada** (o sheet de
  640x480 saiu com a janela-mãe em volta, e as coordenadas de clique tiradas
  dessa imagem erram o alvo). O que funcionou foi `screencapture -R x,y,w,h`
  com os bounds de `CGWindowListCopyWindowInfo` e `sips -z` pra 1x. O editor e
  o assistente ficam no tamanho do sheet (640x480), não em 802x554.
- **Fluxo validado clicando** (pendência aberta desde a Fase 2): perfil criado
  pelo assistente, preset GHL do Marketplace escolhido, POST real no link →
  o passo Primeiro envio virou "Recebido" pelo polling, o editor semeou os
  campos da receita, o mapa salvou e o POST seguinte chegou como card no notch
  ("Marina Duarte / ContactCreate · marina@exemplo.com"). Os perfis de teste
  foram apagados no relay e o toggle voltou a desligado.
- `./tools/check.sh`: 34 checks ok.
