# Etapa 4 — verificação da tela (rodada 1)

Tela nativa (SwiftUI): renders de `tools/snapshot.sh` (`ask-preview`, `ask-preview-largo`) comparados
aos quadros "Opções com preview: sempre inteiro" e "Preview largo demais para ficar ao lado" do
mockup. Sem página servida: Playwright e detector não se aplicam. `r1-1440.png` = `ask-preview` em
2x, `r1-375.png` reduzida.

| Item | Esperado (mockup) | Resultado |
|---|---|---|
| Preview de 44 colunas | ao lado das opções, inteiro, moldura fechando nos quatro cantos | passou |
| Letra do preview | 11 pt (era 9) | passou |
| Preview mostrado | o da opção em destaque (segunda) | passou |
| Largura do card | cresce até caber a linha mais comprida | passou (619 pt) |
| Preview de ~100 colunas | embaixo das opções, na largura toda, tabela inteira | passou (card de 754 pt) |
| Campo e legenda | abaixo do preview, inteiros | passou |
| Card sem preview (`ask-simple`) | igual ao da etapa 3 | passou |
| Contorno no destaque e legenda de teclas | estado com teclado | fora desta etapa: entra na etapa 6 |

Diferença aceita: a entrelinha do preview ficou em ~15 pt, contra ~16 no mockup; é a altura de linha
real da fonte do sistema mais 2 pt, a mesma conta que dimensiona o quadro.

Desvios do plano na implementação: o preview é desenhado uma linha por `Text`, porque num `Text` só
o sistema arredonda a altura de linha e o texto passaria do quadro em previews altos; com rolagem
(preview descomunal), a altura do quadro é limitada ao espaço disponível.

Sem prova automática, conferidos por leitura do código e por medição isolada: destaque numa opção sem
preview deixa o quadro vazio do mesmo tamanho; sem destaque aparece o primeiro preview.

Pendência levada para a etapa 5: com o preview embaixo, a altura reservada para ele não desconta a
lista de opções; um preview muito alto somado à lista pode passar da tela.
