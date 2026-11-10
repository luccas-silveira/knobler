# Verificação — foto e vídeo dentro do notch

Tela existente mudando (conversa do WhatsApp no notch largo), uma direção, no estilo atual.
Servido em `http://127.0.0.1:8765/index.html`. Prints por Playwright (a sessão MCP estava
presa a outro processo; usei a biblioteca do `@playwright/cli` com o Chrome) e, na rodada 1,
pelo Chrome headless.

## Rodada 1

- O visualizador saiu transparente no print: a animação de entrada estava no meio. Print
  refeito esperando a animação.
- A foto aberta passava da área e cobria a legenda; a barra do vídeo esticava os ícones
  (a regra de tamanho da foto pegava também os SVG dos controles). Corrigido na rodada 2.

## Rodada 2

Sem rolagem lateral em 375 (scrollWidth 375) nem em 1440. Os cinco estados aparecem.

| Alarme | Veredito |
|---|---|
| `tiny-text`, `undersized-ui-text` | refutado: o notch usa os tamanhos do app (DESIGN.md §3, `.footnote` 10 pt em Retina 2×), igual ao mockup de 2026-11-04 |
| `text-overflow` em `div.p` | refutado: é a prévia da linha com reticências de propósito |
| `text-occlusion` (bolha e cabeçalho cobertos) | refutado: o visualizador cobre a conversa, é o desenho |
| `clipped-overflow-container` em `div.foto` | refutado: a barra do vídeo fica dentro do quadro da mídia de propósito |
