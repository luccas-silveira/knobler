# Etapa 7 — verificação da tela (rodada 1)

Tela nativa (SwiftUI): renders de `tools/snapshot.sh` (`ask-espera-nota`, `ask-espera-liberada`) comparados
ao quadro "Pergunta que chega enquanto você digita" do mockup. Sem página servida: Playwright e detector
não se aplicam. `r1-1440.png` = `ask-espera-nota` em 2x, `r1-375.png` reduzida.

| Item | Esperado | Resultado |
|---|---|---|
| Nota em edição com pergunta chegando | nota continua na tela, texto intacto | passou |
| Selo | faixa no topo, `◐ Claude perguntou` + origem, à direita | passou |
| Card de pergunta escondido | não aparece enquanto a nota está em edição | passou |
| Liberada pelo selo | o card de pergunta aparece, sem teclado (legenda do atalho) | passou |
| Outra tela sem edição | mostra a pergunta na hora | passou (conferência da janela no harness) |
| Pergunta dispensada | selo some, card encolhe 28 pt, nota com o mesmo texto | passou |

Desvio do mockup: no mockup o selo divide a linha com um título "Nota rápida"; a seção de nota do app não
tem título, então o selo ganhou faixa própria, como o plano descreve.

Teste ao vivo pulado por decisão do usuário em 2026-11-18 (as teclas sintéticas vão para o app da frente
e o Mac estava em uso). Pendente para o primeiro uso real.
