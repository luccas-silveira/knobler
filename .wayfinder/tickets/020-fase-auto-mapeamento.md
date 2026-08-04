# Fase 4 — auto-mapeamento

- map: ../map.md
- label: wayfinder:task
- status: in-progress
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
