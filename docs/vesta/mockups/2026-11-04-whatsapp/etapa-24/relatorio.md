# Etapa 24 — verificação da tela (rodada 1)

Tela nativa (SwiftUI): renders do app (`tools/snapshot.sh`: `whatsapp-conversa-marina`, `-conversa-entrega`,
`-grupo-midia`, `-grupo-reacao`, `-grupo-falha`) comparados às colunas direitas dos quadros da Variante A.
Sem página servida: Playwright e detector do impeccable não se aplicam; os JSONs guardam as medidas.
`r1-1440.png` = conversa da Marina em 2x, `r1-375.png` = a mesma em 1x; os outros PNGs estão na pasta.
O compositor (campo, anexo, gravação, barra de reações) é da etapa 25 e não aparece aqui.

| Item | Esperado (mockup) | Resultado |
|---|---|---|
| Cabeçalho | avatar, nome (e participantes no grupo), "Marcar como lida" com tiques | passou |
| Separador de dia | "Hoje" centrado | passou |
| Bolhas | recebida branco 10%, enviada branco 22%, hora dentro | passou |
| Tiques | lida em cápsula branca; entregue dois tiques; enviada um; enviando relógio | passou |
| Editada | "editada · 14:22" | passou |
| Citação | faixa com "Você" e o trecho dentro da bolha | passou |
| Reação | emoji embaixo da bolha (recebida à esquerda, enviada à direita) | passou |
| Foto com legenda | imagem + legenda + hora | passou (o harness usa um retângulo de cor no lugar da foto) |
| Grupo | nome do remetente acima das recebidas | passou |
| Documento | ícone, nome, "PDF · 820 KB", baixar | passou |
| Vídeo | miniatura, play, duração 0:42, legenda | passou |
| Figurinha | sem bolha, hora embaixo | passou |
| Apagada | ícone + "Mensagem apagada" em itálico | passou |
| Mídia indisponível | ícone + "mídia indisponível" | passou |
| Áudio | play, forma de onda, 0:37 | passou |
| Falha | sem bolha vermelha; "não enviada · tentar de novo" em laranja | passou |
