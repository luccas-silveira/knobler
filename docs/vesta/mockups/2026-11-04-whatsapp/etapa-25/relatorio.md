# Etapa 25 — verificação da tela (rodadas 1 e 2)

Tela nativa (SwiftUI): renders do app (`tools/snapshot.sh`: `whatsapp-citando-reacoes`, `-gravando`,
`-ditando`, `-rascunho`) comparados aos quadros "Envio, edição e barra de reações", "Grupo: … gravando"
e "Grupo: … ditando" da Variante A. Sem página servida: Playwright e detector do impeccable não se
aplicam; os JSONs guardam as medidas. `r1-1440.png` = citando com reações em 2x, `r1-375.png` em 1x;
os outros PNGs (rodada 2) estão na pasta; `r1-antes-montagem.png` é a rodada 1.

## Rodada 1 — achados

| Item | Achado | Correção |
|---|---|---|
| Barra de reações | cobria a bolha da Marina; botões reagir/citar sobre a hora | barra em linha própria acima da bolha; botões ao lado da bolha |
| Gravando | linha "Hoje" cortada colada ao subtítulo do cabeçalho | degradê de 16 pt no topo da lista e recuo de 16 pt no conteúdo |

## Rodada 2 — conferência

| Item | Esperado (mockup) | Resultado |
|---|---|---|
| Barra de reações | seis emojis numa cápsula acima da bolha | passou |
| Citando | faixa "Respondendo a Marina Duarte" + trecho + fechar, acima do campo | passou |
| Campo | anexo, "Mensagem", microfone | passou |
| Gravando | lixeira, ponto vermelho, "Gravando 0:12", nível, enviar | passou |
| Ditando | texto no campo, pílula "Ouvindo" dentro do campo, contorno claro | passou |
| Rascunho | texto preservado no campo; "Rascunho:" na lista | passou |
