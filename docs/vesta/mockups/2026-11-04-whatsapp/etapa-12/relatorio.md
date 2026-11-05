# Etapa 12 — verificação da tela (rodada 1)

Tela nativa (SwiftUI): render do app (`tools/snapshot.sh`, `whatsapp-vitrine`) comparado ao quadro
"Ajustes › Plugins" da aba Vitrine do mockup. Sem página servida: Playwright e detector do
impeccable não se aplicam; os JSONs guardam as medidas. `r1-1440.png` em 2x, `r1-375.png` em 1x.

| Item | Esperado (mockup) | Medido | Resultado |
|---|---|---|---|
| Cor do tile | `.indigo` do sistema (#5E5CE6) com gradiente branco 16% no topo | base (94,85,236), topo (130,120,255) | passou |
| Ícone | `phone.bubble.fill` | `phone.bubble.fill` | passou |
| Texto | "WhatsApp" / "Suas duas contas no notch, pela ponte local." | idêntico | passou |
| Pílula | INSTALAR cheia | INSTALAR cheia, azul de destaque | passou |
| Vizinho | ao lado de Mensagens (verde, ABRIR) | ao lado de Mensagens | passou |
| Aparência | o harness renderiza em claro; o mockup mostra a janela escura | o card segue o modo do sistema, como os outros `CardPeca` | passou (diferença só de modo) |
| Sem ponte identificada | card fora da vitrine | coberto por `whatsapppecacheck` | passou |
