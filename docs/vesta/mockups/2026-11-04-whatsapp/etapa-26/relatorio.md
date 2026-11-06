# Etapa 26 — verificação da tela (rodada 1)

Tela nativa (SwiftUI): renders do app (`tools/snapshot.sh`: `whatsapp-cartao-texto`, `-grupo`, `-foto`,
`-agrupado`, `-respondendo`) comparados aos quadros da aba "Card de chegada". Sem página servida:
Playwright e detector do impeccable não se aplicam; os JSONs guardam as medidas. `r1-1440.png` = card de
texto em 2x, `r1-375.png` em 1x; os outros PNGs estão na pasta.

| Item | Esperado (mockup) | Resultado |
|---|---|---|
| Largura | 360 pt como o card de Mensagens (corpo 332) | passou (corpo medido no JSON) |
| Cabeçalho | ícone, "Conta · final", "agora" à direita | passou |
| Individual | avatar, nome, prévia, fechar, "Responder…", enviar | passou |
| Grupo | grupo no título, "Remetente:" em negrito na prévia | passou |
| Foto | miniatura acima do campo | passou (o harness usa um retângulo de cor no lugar da foto) |
| Agrupado | "3 mensagens novas · última" | passou |
| Campo em uso | contorno claro com o texto digitado | passou |
| Fila espera com o campo em uso | comportamento, não desenho | coberto por `whatsappintegracaocheck` |
