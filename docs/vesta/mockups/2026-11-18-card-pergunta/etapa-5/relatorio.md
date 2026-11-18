# Etapa 5 — verificação da tela (rodada 1)

Tela nativa (SwiftUI): renders de `tools/snapshot.sh` (`ask-longo`, `ask-preview-alto`) comparados ao
quadro "Texto longo" do mockup, com a altura disponível fixada em 520. Sem página servida: Playwright
e detector não se aplicam. `r1-1440.png` = `ask-longo` em 2x, `r1-375.png` reduzida.

| Item | Esperado | Resultado |
|---|---|---|
| Topo, pergunta, campo, legenda | fixos e inteiros | passou |
| Lista acima do teto | rola por dentro; a linha cortada embaixo mostra que há mais | passou |
| Altura do card | para em 60% da altura disponível | passou (312 de 520) |
| Card que cabe (`ask-simple`, `ask-multiselect`, `ask-preview`, `ask-preview-largo`) | sem área rolável, igual a antes | passou (byte-idênticos) |
| Preview alto embaixo | inteiro, com letra menor; quem cede é a lista | passou (card em 496 de 520) |
| Medida | assenta em duas contas, sem oscilar | passou |

Rodada 1 corrigiu: com mouse conectado, a barra de rolagem clássica do macOS abria uma calha de 17 pt
e as linhas da lista ficavam mais estreitas que o campo. A barra foi escondida (`.scrollIndicators(.never)`;
`.hidden` não basta com mouse conectado) e a lista voltou à largura toda.

Desvios do plano na implementação: a medida da lista é feita em `.overlay`; a chave da medida da
lista só aceita medida de verdade (com "o último valor" o rodapé zerava a medida); a conta do teto
roda quando as medidas mudam e guarda o resultado; com o preview ao lado, a lista nunca fica mais
baixa que o preview.

Pendente no app real, junto com o teste ao vivo da etapa 6: rolagem com dois dedos e com a rodinha
sobre a lista; gesto de lado sobre o card não troca de música; primeiro frame de uma pergunta longa
(a estimativa inicial não é limitada ao teto); troca de aba entre uma lista que rola e uma que não rola.
