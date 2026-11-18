# Etapa 3 — verificação da tela (rodada 1)

Tela nativa (SwiftUI): renders de `tools/snapshot.sh` (`ask-simple`, `ask-multi-vazio`,
`ask-multiselect`, `ask-paged`, `ask-revisita`), agora na janela real do harness, comparados aos
quadros "Uma pergunta: em repouso", "Múltipla escolha" e "Várias perguntas: abas" do mockup. Sem
página servida: Playwright e detector não se aplicam. `r1-1440.png` = `ask-simple` em 2x,
`r1-375.png` reduzida.

| Item | Esperado (mockup) | Resultado |
|---|---|---|
| Faixa de topo | chip do cabeçalho à esquerda, `◐ origem` e ✕ à direita | passou |
| Pergunta | linha própria, inteira, maior que o resto | passou |
| Opção | selo do número, rótulo, descrição inteira | passou |
| Recomendada | selo no lugar do "(Recomendado)" do rótulo | passou |
| Campo de texto | desenhado, placeholder "Outra resposta…" | passou; a faixa amarela de "proibido" sumiu |
| Legenda em repouso | `⌃⌥K responder pelo teclado` | passou |
| Múltipla, nada marcado | caixas vazias à direita, Confirmar apagado | passou |
| Múltipla, duas marcadas | linhas mais claras, caixa preenchida com visto, "Confirmar 2 ⏎" | passou |
| Abas | respondida com visto e resposta resumida; atual preenchida; pendente com ponto vazado | passou |
| Aba revisitada | opção respondida mais clara com visto; "2 marcadas" na segunda aba | passou |
| Estado com teclado nos quadros de múltipla e abas | contorno no destaque, selos acesos, legenda de teclas | fora desta etapa: entra na etapa 6 |

Diferenças aceitas: o macOS evita palavra sozinha na última linha, então a pergunta quebra em
"…quando o / Claude perguntar?"; a margem de topo do card é a do `NotchView` (40 pt, contra 32 no
mockup), a mesma dos outros cards; visto e ✕ são SF Symbols, um pouco mais grossos.

Dois desvios do plano na implementação: a medida de altura do card é feita em `.overlay` (em
`.background`, com a chave que aceita encolher, chegava 0); o placeholder é um `Text` atrás do
campo, porque o `prompt:` do `TextField` ignora a cor no macOS.

Pendente no app real: a transição de troca de aba (o harness desliga animações).
