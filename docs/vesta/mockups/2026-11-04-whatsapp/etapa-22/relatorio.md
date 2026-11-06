# Etapa 22 — verificação da tela (rodada 1)

Tela nativa (SwiftUI): renders do app (`tools/snapshot.sh`: `whatsapp-lista-4143`, `whatsapp-lista-8292`,
`whatsapp-faixa`) comparados à coluna esquerda do quadro "Lista e conversa individual" (Variante A),
à lista do Pessoal · 8292 e ao quadro "Faixa de atalhos" da Vitrine. Sem página servida: Playwright e
detector do impeccable não se aplicam; os JSONs guardam as medidas. `r1-1440.png` = lista do 4143 em 2x,
`r1-375.png` = a mesma em 1x; os outros dois PNGs estão na pasta.

| Item | Esperado (mockup) | Medido | Resultado |
|---|---|---|---|
| Coluna esquerda | 260 pt | 260 pt (x 124–643 px em 2x) | passou |
| Seletor de conta | duas linhas, ícone (maleta / pessoa), rótulo "Nome · final", contagem; a selecionada mais clara | igual | passou |
| Lista 4143 | Operacional ZOI 14:41 "Diego: Áudio · 0:37" 3; Marina 14:32 2; Carlos 11:47 "Rascunho:" | igual | passou |
| Lista 8292 | figurinha em grupo, vídeo com duração, "Mensagem apagada" em itálico com ícone | igual | passou |
| Fio entre colunas | 1 pt | presente | passou |
| Coluna direita | encaixe só (a conversa entra na etapa 24) | nome da conversa aberta centralizado | passou |
| Sinal na faixa | contagem 7 pt sobre `phone.bubble.fill` | presente, "4" | passou — o número difere do mockup (7) por decisão do plano: a faixa soma conversas com não lidas (2 + 2), não mensagens (5 + 2) |
