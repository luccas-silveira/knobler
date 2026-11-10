# Etapa 1 — verificação da tela (rodada 1)

Tela nativa (SwiftUI): renders de `tools/snapshot.sh` (`whatsapp-visualizador-foto`, `-carregando`,
`-video`, `-indisponivel`) comparados aos quadros 2 a 5 do mockup. Sem página servida: Playwright e
detector não se aplicam. `r1-1440.png` = foto aberta em 2x, `r1-375.png` reduzida.

| Item | Esperado (mockup) | Resultado |
|---|---|---|
| Cobertura | só a coluna da conversa; a lista fica | passou |
| Topo | inicial, remetente, "Operacional ZOI · hoje, 14:41", três botões | passou |
| Foto | maior tamanho sem cortar, legenda embaixo | passou |
| Carregando | miniatura, spinner, "Buscando a foto no celular…" | passou; o desfoque não aparece na captura offscreen |
| Vídeo | quadro com controles por cima | parcial: o player não desenha offscreen, o render mostra o quadro parado; controles só no app |
| Indisponível | triângulo, título, "Peça para Diego mandar de novo." | passou; o laranja do ícone não sai na captura (igual ao `whatsapp-grupo-falha`) |
| Botões em carregando/indisponível | — | abrir e Finder ficam apagados sem arquivo (não estava no mockup; coerente) |

Pendente no app real: desfoque, cor do alerta, player tocando e pausando ao fechar.
