# Operação do relay

O relay (`relay/`) é o único componente do Knobler que roda **fora** da máquina do
usuário: um processo Node que recebe POST de serviços externos e empurra a
notificação pro app por WebSocket. O uso está em [Webhooks](webhooks.md); aqui
está como manter o serviço de pé.

## O que é

| Item | Valor |
|---|---|
| Processo | `knobler-relay` (pm2, `relay/ecosystem.config.js`) |
| Entrypoint | `relay/src/index.js` (`npm start`) |
| Porta | `8477` (`PORT`), escutando **só em `127.0.0.1`** |
| Node | `>=18 <21` (`engines` do `package.json`) |
| Banco | SQLite em WAL — `relay.db` ao lado de `relay/`, ou `RELAY_DB` |
| Modo pm2 | `fork`, 1 instância, `max_memory_restart: 200M`, `kill_timeout: 10s` |
| Dependências | `better-sqlite3`, `ws` (nada além disso) |

⚠️ O processo escuta em loopback. O endereço público
(`https://push.appzoi.com.br`) chega por um **proxy TLS na frente que não está
neste repo** — trocar de host exige recriar essa camada, e a configuração dela
não está versionada aqui. Vale documentar no host quando alguém mexer.

## Subir, reiniciar, ver log

```bash
cd relay
npm ci
npm test            # node --test, sem framework

pm2 start ecosystem.config.js   # primeira vez
pm2 restart knobler-relay
pm2 logs knobler-relay
pm2 save                        # persistir a lista entre reboots
```

Sanidade, do próprio host (é loopback):

```bash
curl -s 127.0.0.1:8477/health   # {"ok":true,"online":<sockets vivos>}
```

Boot falha limpo de propósito: porta ocupada emitiria `error` sem listener no
`httpServer` e viraria crash mudo em loop no pm2. O `index.js` loga e sai com 1.

Shutdown é gracioso em `SIGINT`/`SIGTERM`: para os timers, fecha o servidor,
roda `wal_checkpoint(RESTART)` e fecha o banco. Rede de segurança de 9 s, abaixo
do `kill_timeout` de 10 s — não reduza o `kill_timeout` sem mexer nesse número,
ou o checkpoint é interrompido.

## O que o banco guarda (e o que se perde)

Três tabelas em `relay.db`:

- **`devices`** — pareamento: `device_id` + **hashes** do `deviceSecret` e do
  `publishToken`. Os segredos em claro só existem no Keychain do Mac.
- **`profiles`** — um por link (`/w/<token>`): nome, `mapping`, ícone e o
  `last_payload` (o último JSON recebido, usado pelo editor de mapeamento).
- **`queued`** — fila offline: até **50** por device, TTL de **24 h**, dedupe por
  `dedupe_id`. Drenada quando o app reconecta.

Perder o arquivo **desfaz o pareamento de todos os apps**: os hashes vão embora,
então cada Mac precisa re-registrar — e isso **troca o `publishToken`**, ou seja,
todo link já colado em serviço externo para de funcionar. É o dado que merece
backup; a fila, não (é volátil por natureza).

Backup a quente, com WAL, é `sqlite3 relay.db ".backup destino.db"` — copiar o
arquivo cru sem checkpoint pode capturar estado inconsistente.

Timers em memória: heartbeat dos sockets a cada 30 s, poda da fila a cada 5 min.

## Migração automática de token → perfil

`openDB()` roda, na subida e de forma idempotente, uma migração que cria um
perfil "Padrão" para todo device cujo `publish_token_h` ainda não tem perfil
(legado de antes dos perfis). Ela está dentro de `try/catch` **de propósito**:
uma exceção ali não pode abortar o `openDB` e derrubar o relay — degrada e
segue, logando `migração de perfis falhou (seguindo)`. Se esse log aparecer,
perfis podem estar faltando, mas o serviço sobe.

## Limites e respostas

| Limite | Valor | Onde |
|---|---|---|
| Corpo do POST | 64 KB | `readBody` |
| Rate limit por perfil | 20/min, burst 5 | `ratelimit.js` (token bucket em memória) |
| Perfis por device | 50 | `POST /profiles` → 429 |
| Mensagem do WebSocket | 1 MB | `maximumMessageSize` no app |

O rate limit é **em memória**: reiniciar o processo zera os buckets. Aceitável
para o volume atual; se um dia importar, precisa sair para o banco.

Rotas: `GET /health`, `POST /register`, `POST /rotate`, `POST /w/<token>`,
e `/profiles[/<id>[/rotate]]` (autenticadas por `Bearer <deviceSecret>`).
Respostas do `POST /w/<token>`: `202 delivered: push` (app online),
`202 delivered: queued` (enfileirado), `202 delivered: captured` (perfil sem
mapeamento — só guarda o payload pro editor), `404` token desconhecido,
`429` rate limit, `400` JSON inválido.

## Ao mexer no relay

`npm test` cobre `db`, `hub`, `normalize`, `ratelimit`, `server`, `template` e
`tokens` — rode antes de subir. O `tools/check.sh` do repo **não** executa os
testes do relay; é um gate separado, citado em
[`development.md`](development.md).
