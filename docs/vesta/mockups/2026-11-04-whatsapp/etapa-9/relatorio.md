# Etapa 9 — verificação da tela (rodada 1)

Tela nativa (SwiftUI): a verificação compara o render do app (`tools/snapshot.sh`, cenário
`whatsapp-moldura`) com as medidas do `relatorio.md` do mockup. Não há página servida, então
Playwright e o detector do impeccable não se aplicam; os JSONs do detector guardam as medidas.
`r1-1440.png` é o render em 2x; `r1-375.png` é o mesmo render em 1x (o notch não muda de
layout com a largura da tela).

| Item | Esperado (mockup) | Medido | Resultado |
|---|---|---|---|
| Largura com as abas da NotchShape | 780 pt | 771 pt na linha 0 (antisserrilhado da curva); 780 no código (`whatsappLargura`) | passou |
| Largura do corpo | 752 pt (780 − 28, item 2 do relatório) | 752 pt | passou |
| Altura | 452 pt (32 + 360 + 60) | 452 pt | passou |
| Faixa de ícones no rodapé | ícone da seção centralizado | presente | passou |
| Conteúdo | vazio padrão nesta etapa (conteúdo real entra nas etapas 22–25) | ícone `phone.bubble.fill` + "WhatsApp" | passou |
| Sem ponte, nada muda | seção e peça escondidas | coberto pelos gates `whatsappescondidacheck` e `plugincheck` | passou |
