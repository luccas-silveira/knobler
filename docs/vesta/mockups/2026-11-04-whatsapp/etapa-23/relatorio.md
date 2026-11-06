# Etapa 23 — verificação da tela (rodadas 1 e 2)

Tela nativa (SwiftUI): renders do app (`tools/snapshot.sh`, nove cenários `whatsapp-*` de estado)
comparados à aba "Estados de conexão" e ao quadro "Conta desconectada" da Variante A. Sem página
servida: Playwright e detector do impeccable não se aplicam; os JSONs guardam as medidas.
`r1-1440.png` = QR em 2x, `r1-375.png` = o mesmo em 1x; os outros PNGs (rodada 2) estão na pasta;
`r1-antes-montagem.png` é a rodada 1.

## Rodada 1 — achados

| Item | Achado | Correção |
|---|---|---|
| Chave ausente, incompatível, carregando | coluna esquerda vazia com um fio solto no topo | sem conta conhecida o estado ocupa o card inteiro; o fio só aparece com seletor |
| Carregando | esqueletos na coluna direita; mockup os põe no lugar da lista | esqueletos e "Carregando conversas…" na coluna esquerda |
| QR expirado | caixa escura sem o código apagado | código antigo em branco 15% sob o véu |

## Rodada 2 — conferência

| Item | Esperado (mockup) | Resultado |
|---|---|---|
| Ponte fora | ícone, título, apoio, comando `servico.sh` com Copiar, linha sobre o WhatsApp Desktop | passou |
| Chave não confere / ausente | ícone de chave, título, apoio, "Tentar de novo" | passou |
| Incompatível (sem quadro) | desenho do de chave | passou |
| QR | código de 128 pt em fundo claro, texto à direita, seletor com "desconectada" | passou |
| QR expirado | código apagado, véu, "QR expirado", "Gerar outro" | passou |
| Carregando | quatro esqueletos de 28 pt + spinner com texto | passou |
| Lista vazia | ícone, "Nenhuma conversa ainda", apoio | passou |
| Ícone da ponte fora | mockup usa tomada desconectada; app usa o símbolo de tomada do sistema | passou (variação de símbolo) |
