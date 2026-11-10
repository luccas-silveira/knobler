# Etapa 1 — verificação da tela (rodada 1)

Tela nativa (SwiftUI): renders de `tools/snapshot.sh` (`whatsapp-cartao-foto-empe`, `-foto-deitada`,
`-video`) comparados aos quadros "Depois" do mockup. Sem página servida: Playwright e detector não se
aplicam. `r1-1440.png` = foto em pé em 2x, `r1-375.png` = os três lado a lado reduzidos.

| Item | Esperado (mockup) | Resultado |
|---|---|---|
| Foto em pé | inteira, quadro de 200 pt, fundo com a própria foto | passou; o desfoque do fundo não sai na captura `cacheDisplay` (o escurecimento sai) |
| Foto deitada | largura toda, altura pela proporção | passou (180 pt) |
| Vídeo | miniatura sem corte, play no centro, "0:42" embaixo à esquerda | passou |
| Card | cresce com o quadro, campo inteiro, sem corte | passou (334 pt com a foto em pé) |

Pendente no app real: desfoque do fundo e a troca da miniatura pela foto inteira quando ela baixa.
