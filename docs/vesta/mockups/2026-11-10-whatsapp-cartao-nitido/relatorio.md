# Verificação — preview nítido no card do WhatsApp

Tela existente mudando (card de chegada), uma direção, no estilo atual. Servido em
`http://127.0.0.1:8766/index.html`; prints pela biblioteca do Playwright com o Chrome.

## Rodada 1

Sem rolagem lateral em 375 nem em 1440. Os quatro quadros (hoje, foto em pé, foto deitada, vídeo) aparecem.

| Alarme | Veredito |
|---|---|
| `tiny-text`, `undersized-ui-text` | refutado: tamanhos do notch (DESIGN.md §3, pontos de macOS em Retina 2×), igual aos mockups anteriores do WhatsApp |
| `clipped-overflow-container` em `div.midia` | refutado: o fundo desfocado passa da borda de propósito e é cortado pelo canto |
| `line-length` (~86 caracteres no parágrafo de abertura) | aceito como está: é texto da moldura da página, não do app |
