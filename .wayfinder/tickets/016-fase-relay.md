# Fase 0 — relay: campos aditivos e filtros

- map: ../map.md
- label: wayfinder:task
- status: closed
- assignee: claude (sessão 2026-08-04)
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

## Resolução (2026-08-04) — implementado e **no ar**

- `relay/src/template.js`: `FILTROS` é um objeto com a lista fechada
  (`semHifens`, `data`, `quill`); `render()` faz `expr.split('|')` e aplica o
  filtro sobre o valor **já cru-em-string**. Filtro desconhecido, valor vazio ou
  filtro que não se aplica devolvem o cru — nenhum caminho lança.
  `data` formata `DD/MM/AAAA HH:MM` na hora local (formato manual, fácil de
  espelhar em Swift depois; nada de `toLocale*`).
- `relay/src/db.js`: `last_payload_at` e `payload_count` entram por `ALTER TABLE`
  solto num `try/catch` (banco antigo em produção não é recriado). `storeLastPayload`
  carimba os dois; `payload_count` usa `COALESCE(...,0)+1`.
- `relay/src/server.js`: `GET /profiles/:id` devolve `lastPayloadAt` e
  `payloadCount` (`?? null` / `?? 0` pra linha pré-migração).
- `tools/check.sh`: laço `for t in template normalize ratelimit tokens` na seção
  de gates de integração. `./tools/check.sh` = 29 checks ok.
- Testes de `db`/`server` **não** rodaram: `better-sqlite3` não compila nesta
  máquina (node v26 local vs `engines <21`, e o npm bloqueia install scripts).
  O SQL novo foi validado à parte contra `node:sqlite` (ALTER duplicado ignorado,
  `payload_count` chega a 2 depois de dois `storeLastPayload`).
- **Deploy feito** (2026-08-04) na VPS `root@147.79.87.179`, dir
  `/opt/knobler-relay` (não é checkout git — arquivos copiados). Receita:
  backup (`cp -a src src.bak.202608041340` e `sqlite3 .backup` →
  `relay.db.bak.202608041640`), `rsync -a --delete` de `relay/src/` e
  `relay/test/`, `npm test` na VPS = **48/48** (node 18.19.1 — inclui `db` e
  `server`, que não rodam local), `pm2 restart knobler-relay`.
  Conferido: `PRAGMA table_info(profiles)` mostra `last_payload_at` e
  `payload_count`; `https://push.appzoi.com.br/health` →
  `{"ok":true,"online":2}`; nenhum log de "migração de perfis falhou".
