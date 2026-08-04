# Fase 0 — relay: campos aditivos e filtros

- map: ../map.md
- label: wayfinder:task
- status: open
- assignee: —
- blocked-by: — (015 fechado)

## Question

Implementar no `relay/` tudo que o app vai precisar, antes de tocar no app.

- `GET /profiles/:id` devolve `lastPayloadAt` e `payloadCount` (007). Aditivo:
  cliente antigo ignora.
- `render()` (`relay/src/template.js`) ganha os três filtros de 014:
  `{{caminho | semHifens}}`, `| data`, `| quill`. Um filtro por token, sem
  encadeamento nem argumentos. Filtro desconhecido ou inaplicável devolve o
  valor cru (falha suave).
- Testes em `relay/test/template.test.js` (e `db`/`server` onde couber).
- **Gates node novos em `tools/check.sh`** — só os herméticos, que hoje não
  rodam na CI nenhuma vez:
  `run relay-template node --test relay/test/template.test.js`, idem
  `normalize`, `ratelimit`, `tokens`. `db`/`hub`/`server` ficam de fora
  (exigem `better-sqlite3`/`ws`).
- Uma linha em `## [Unreleased]` do `CHANGELOG.md`.

Fecha quando `./tools/check.sh` passa com os gates novos e o relay está no ar
com os campos aditivos.
