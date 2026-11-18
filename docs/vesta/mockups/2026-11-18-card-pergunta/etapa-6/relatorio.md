# Etapa 6 — verificação da tela (rodada 1)

Tela nativa (SwiftUI): renders de `tools/snapshot.sh` (`ask-teclado`, `ask-texto`) comparados aos quadros
"Com o teclado no card" e "Escrevendo" do mockup. Sem página servida: Playwright e detector não se aplicam.
`r1-1440.png` = `ask-teclado` em 2x, `r1-375.png` reduzida.

| Item | Esperado | Resultado |
|---|---|---|
| Destaque com teclado | segunda opção com contorno | passou |
| Selos dos números | acesos com o teclado no card | passou |
| Selo `⇥` | no fim do campo quando há teclado e o cursor não está nele | passou (some em `ask-texto`) |
| Legenda na lista | `↑ ↓ escolher · ⏎ responder · esc soltar` | passou |
| Legenda no campo | `⏎ enviar · esc voltar à lista · ⌥ direita dita` | passou |
| Sem teclado (app real) | legenda `⌃⌥K responder pelo teclado`, sem contorno | passou (print do build de teste, primeiro passo do teste ao vivo) |

Teste ao vivo: só o passo 1 rodou (a pergunta chegou no build de teste com a legenda do atalho e sem
contorno). O resto foi pulado por decisão do usuário em 2026-11-18: as teclas sintéticas vão para o app
da frente e o Mac estava em uso. Ficam pendentes, para o primeiro uso real: passos 2 a 7 da etapa 6 e
os itens de rolagem herdados da etapa 5.

Regras de teclado cobertas pelo gate hermético `tools/asktecladocheck.swift` (todas as teclas da etapa)
e pelas `precondition` dos cenários `ask-teclado`/`ask-texto` em `tools/main.swift` (atalho dá e solta a
posse, avisa o painel uma vez só e não arma o card de música por trás).
