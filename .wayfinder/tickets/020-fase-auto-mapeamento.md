# Fase 4 — auto-mapeamento

- map: ../map.md
- label: wayfinder:task
- status: closed
- assignee: sessão 2026-08-04 (020)
- blocked-by: 017, 019

## Question

`Knobler/WebhookAutoMap.swift` com as regras de 005: preset primeiro
(dica de forma de 006 casa contra a árvore e entrega o template inteiro, com o
filtro de 014), heurística de fallback campo a campo (lista fechada de nomes de
chave, busca por largura, só folhas, array pelo índice 0, profundidade máxima 4,
ícone nunca chutado). Campo preenchido **nunca** é sobrescrito. Roda uma vez por
`lastPayloadAt` novo — e uma vez por JSON colado (019). Banner não-bloqueante
com "Limpar sugestões"; nada casou = campos vazios + convite a clicar na árvore.

Gate `automapcheck` (arrasta `WebhookPresets.swift`).

## Resolução (2026-08-04)

`Knobler/WebhookAutoMap.swift` (puro, sem SwiftUI) + gate `automapcheck` em
`tools/check.sh` (34 checks) + ligação no `MappingEditorView`.

- `AutoMap.sugerir(arvore:preset:vazios:)` é a porta única: só devolve campo que
  está em `vazios`, então "campo preenchido nunca é sobrescrito" é invariante da
  assinatura, não disciplina do chamador.
- Preset primeiro: `casa(_:_:)` exige que **todos** os `{{caminho}}` da dica
  existam na árvore como folha — cobre a URL do GHL de workflow, que tem dois
  tokens no mesmo campo. Dica que não casa cai na heurística, não bloqueia.
- Heurística: `folhas()` varre em largura, só string/número (bool e null saem
  junto com objeto/array), array só pelo índice 0 (a folha herda a chave do pai,
  senão `history_items.0.comment.text_content` não teria nome pra comparar),
  profundidade máxima 4. Desempate = (profundidade, posição na lista); as listas
  já entram com as entradas das capturas 010/012 (`fullname`, `firstname`,
  `textcontent` **antes** de `content`, `contactid`). URL exige valor `http`.
  `TemplateField` não tem ícone, então "ícone nunca é chutado" também é do tipo.
- Roda em `load()`, em `aplicar()` (chaveado pelo `lastPayloadAt`, ou seja uma
  vez por payload novo) e em `colarExemplo()` — onde estava o `// ponytail:` de
  019.
- Banner no topo do editor: some ao primeiro toque em campo sugerido;
  "Limpar sugestões" esvazia só o que o chute escreveu e ninguém editou; nada
  casou vira o convite a clicar na árvore.

### Desvio de 005 (um)

O casamento de forma é **literal**, não com buraco. As únicas dicas com buraco
(`properties.<sua propriedade>.title[0].plain_text`) são do preset do Notion, que
está travado em 011/022 e fora do primeiro release — nenhum dos quatro presets
existentes tem buraco. Marcado com `// ponytail:` em `casa(_:_:)`, apontando o
lugar exato onde a forma passa a andar a árvore.
