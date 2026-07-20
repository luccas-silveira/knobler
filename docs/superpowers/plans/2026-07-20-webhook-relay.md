# Relay de notificações webhook — Plano de Implementação (Plano 1/2)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Construir e implantar o relay HTTP+WebSocket que dá a cada dispositivo um link próprio (`https://push.appzoi.com.br/w/<token>`), recebe webhooks e os empurra pro app do Knobler no Mac (ou enfileira se offline).

**Architecture:** Um processo Node 18 (sem framework web pesado — `http` nativo + `ws`) rodando sob pm2 na VPS, atrás do nginx (TLS via certbot). Estado pequeno em SQLite (`better-sqlite3@11`, WAL). Autenticação por dois segredos por device: `deviceSecret` (autentica o WebSocket, via header) e `publishToken` (vai no path da URL pública). Guardados só como hash SHA-256. Rate limit em memória por device.

**Tech Stack:** Node.js 18.19 · `ws@^8` · `better-sqlite3@^11` · `node:test` (runner nativo, zero deps de teste) · pm2 (fork mode) · nginx + certbot.

**Este é o Plano 1 de 2.** Ele entrega o relay funcionando e implantado, testável de ponta a ponta com `curl` + `wscat`, **sem tocar no app Swift**. O Plano 2 (integração no app: `WebhookClient`, render no notch, aba de config) é escrito depois, contra o relay já no ar.

## Global Constraints

- **Node 18.19.1** na VPS (v18.19). **Não** usar APIs de Node 20+/22+ (ex.: `node:sqlite` não existe; `structuredClone` existe em 18, ok).
- **`better-sqlite3@11`** — fixar major 11 (v12+ dropa Node 18).
- **`ws@8`** — compatível com Node 18.
- **Zero dependências de teste** — usar `node:test` + `node:assert` nativos.
- **Segredos:** `deviceSecret` e `publishToken` = **256 bits** aleatórios (`crypto.randomBytes(32)`), codificados base64url. Guardar **só o SHA-256** (hex). Nunca logar o segredo em claro (truncar `abcd…wxyz`).
- **Auth do WebSocket:** header `Authorization: Bearer <deviceSecret>` — **nunca** na query string (vaza no access log do nginx).
- **Rate limit:** 20 req/min, burst 5, por device, **em memória** (sem Redis). Estouro → HTTP `429` + `Retry-After`.
- **Fila offline:** máx **50** mensagens por device, TTL **24h**. Replace por `id` (mesmo `id` substitui).
- **Payload aceito:** JSON, form-encoded e query string. Campos: `title` (obrigatório, ≤200), `body` (≤1000), `icon` (https), `url` (http/https), `sound` (bool), `id` (≤200). Sanitizar (tirar caracteres de controle, truncar).
- **Escuta só em `127.0.0.1`** na porta do relay (nginx faz o proxy). Porta escolhida: **`8477`** (confirmar livre no deploy).
- **Domínio:** `push.appzoi.com.br` → `147.79.87.179`.
- **Comentários e strings em pt-BR** (convenção do projeto).
- **Diretório do relay:** `relay/` na raiz do repo Knobler.

---

## File Structure

Tudo novo, sob `relay/`:

- `relay/package.json` — deps (`ws`, `better-sqlite3`), engines Node ≥18, scripts (`start`, `test`).
- `relay/.gitignore` — `node_modules/`, `*.db`, `*.db-wal`, `*.db-shm`.
- `relay/src/tokens.js` — geração de token (256 bits base64url) e `sha256`. **Puro.**
- `relay/src/normalize.js` — parse + sanitização + validação do payload do webhook (JSON/form/query). **Puro.**
- `relay/src/db.js` — abre SQLite (WAL + schema), operações de device e da fila offline.
- `relay/src/ratelimit.js` — token-bucket em memória por chave. **Puro (clock injetável).**
- `relay/src/hub.js` — `Map<deviceId, ws>`: registrar/substituir/remover, enviar, heartbeat.
- `relay/src/server.js` — monta o `http.createServer` (rotas) + upgrade do WebSocket (auth) + heartbeat + graceful shutdown. Fia tudo.
- `relay/src/index.js` — entrypoint: abre DB, cria hub/ratelimiter/server, `.start()`, trata sinais.
- `relay/ecosystem.config.js` — config do pm2 (fork mode, kill_timeout).
- `relay/test/*.test.js` — testes por módulo (`node --test`).
- `relay/README.md` — passos de deploy (nginx, certbot, pm2) + exemplos de uso.

Ordem das tasks: módulos puros/testáveis primeiro (tokens → normalize → db → ratelimit → hub), depois a integração (server), depois deploy.

---

### Task 1: Scaffold do subprojeto + `tokens.js`

**Files:**
- Create: `relay/package.json`
- Create: `relay/.gitignore`
- Create: `relay/src/tokens.js`
- Test: `relay/test/tokens.test.js`

**Interfaces:**
- Consumes: nada.
- Produces:
  - `genToken(): string` — 43 chars base64url (256 bits), sem padding.
  - `sha256(input: string): string` — hex de 64 chars.

- [ ] **Step 1: Criar `relay/package.json`**

```json
{
  "name": "knobler-relay",
  "version": "0.1.0",
  "private": true,
  "description": "Relay de notificações webhook do Knobler",
  "type": "commonjs",
  "engines": { "node": ">=18 <21" },
  "scripts": {
    "start": "node src/index.js",
    "test": "node --test"
  },
  "dependencies": {
    "better-sqlite3": "^11.0.0",
    "ws": "^8.16.0"
  }
}
```

- [ ] **Step 2: Criar `relay/.gitignore`**

```gitignore
node_modules/
*.db
*.db-wal
*.db-shm
```

- [ ] **Step 3: Escrever o teste que falha — `relay/test/tokens.test.js`**

```js
const { test } = require('node:test');
const assert = require('node:assert');
const { genToken, sha256 } = require('../src/tokens');

test('genToken gera 43 chars base64url e é único', () => {
  const a = genToken();
  const b = genToken();
  assert.match(a, /^[A-Za-z0-9_-]{43}$/, 'formato base64url sem padding');
  assert.notStrictEqual(a, b, 'dois tokens não colidem');
});

test('sha256 é hex de 64 chars e determinístico', () => {
  const h1 = sha256('abc');
  const h2 = sha256('abc');
  assert.match(h1, /^[0-9a-f]{64}$/);
  assert.strictEqual(h1, h2);
  assert.notStrictEqual(sha256('abc'), sha256('abd'));
});
```

- [ ] **Step 4: Rodar o teste e ver falhar**

Run: `cd relay && npm install && node --test test/tokens.test.js`
Expected: FAIL — `Cannot find module '../src/tokens'`.

- [ ] **Step 5: Implementar `relay/src/tokens.js`**

```js
// Geração e hashing dos segredos do relay.
const crypto = require('crypto');

/** Token de 256 bits (32 bytes) em base64url sem padding → 43 chars. */
function genToken() {
  return crypto.randomBytes(32).toString('base64url');
}

/** SHA-256 hex — guardamos só o hash dos segredos, nunca o valor cru. */
function sha256(input) {
  return crypto.createHash('sha256').update(input, 'utf8').digest('hex');
}

module.exports = { genToken, sha256 };
```

- [ ] **Step 6: Rodar o teste e ver passar**

Run: `cd relay && node --test test/tokens.test.js`
Expected: PASS (2 testes).

- [ ] **Step 7: Commit**

```bash
git add relay/package.json relay/.gitignore relay/src/tokens.js relay/test/tokens.test.js relay/package-lock.json
git commit -m "feat(relay): scaffold + geração de token 256 bits e sha256"
```

---

### Task 2: `normalize.js` — parse e sanitização do payload

**Files:**
- Create: `relay/src/normalize.js`
- Test: `relay/test/normalize.test.js`

**Interfaces:**
- Consumes: nada.
- Produces:
  - `class ValidationError extends Error` — com `.statusCode = 400`.
  - `normalizePayload({ contentType, rawBody, query }): { title, body, iconURL, url, sound, id }` — `contentType: string`, `rawBody: string`, `query: object` (pares da query string já parseados). Lança `ValidationError` se faltar `title`. Campos ausentes/ inválidos viram `''`/`null`/`false` sem derrubar o resto: `iconURL`/`url` inválidos viram `null`; `body` default `''`; `sound` default `false`; `id` default `null`.

- [ ] **Step 1: Escrever o teste que falha — `relay/test/normalize.test.js`**

```js
const { test } = require('node:test');
const assert = require('node:assert');
const { normalizePayload, ValidationError } = require('../src/normalize');

test('JSON completo é normalizado', () => {
  const out = normalizePayload({
    contentType: 'application/json',
    rawBody: JSON.stringify({
      title: 'Deploy ok', body: 'produção', icon: 'https://x/i.png',
      url: 'https://x/deploy/1', sound: true, id: 'dep-1',
    }),
    query: {},
  });
  assert.deepStrictEqual(out, {
    title: 'Deploy ok', body: 'produção', iconURL: 'https://x/i.png',
    url: 'https://x/deploy/1', sound: true, id: 'dep-1',
  });
});

test('form-encoded funciona', () => {
  const out = normalizePayload({
    contentType: 'application/x-www-form-urlencoded',
    rawBody: 'title=Oi&body=Tudo+bem',
    query: {},
  });
  assert.strictEqual(out.title, 'Oi');
  assert.strictEqual(out.body, 'Tudo bem');
});

test('query string funciona quando não há corpo', () => {
  const out = normalizePayload({ contentType: '', rawBody: '',
    query: { title: 'Q', body: 'via query' } });
  assert.strictEqual(out.title, 'Q');
  assert.strictEqual(out.body, 'via query');
});

test('sem title → ValidationError 400', () => {
  assert.throws(
    () => normalizePayload({ contentType: 'application/json', rawBody: '{"body":"x"}', query: {} }),
    (e) => e instanceof ValidationError && e.statusCode === 400,
  );
});

test('icon/url com esquema inválido viram null; title/body são truncados e limpos', () => {
  const out = normalizePayload({
    contentType: 'application/json',
    rawBody: JSON.stringify({
      title: '\x01' + 'a'.repeat(300), body: 'b'.repeat(2000),
      icon: 'ftp://x/i.png', url: 'file:///etc/passwd',
    }),
    query: {},
  });
  assert.strictEqual(out.title.length, 200, 'title truncado a 200');
  assert.ok(!out.title.includes('\x01'), 'caractere de controle removido');
  assert.strictEqual(out.body.length, 1000, 'body truncado a 1000');
  assert.strictEqual(out.iconURL, null, 'icon não-https → null');
  assert.strictEqual(out.url, null, 'url não-http(s) → null');
});

test('sound aceita "true"/"1" de form/query como booleano', () => {
  const out = normalizePayload({ contentType: '', rawBody: '', query: { title: 'x', sound: 'true' } });
  assert.strictEqual(out.sound, true);
});
```

- [ ] **Step 2: Rodar e ver falhar**

Run: `cd relay && node --test test/normalize.test.js`
Expected: FAIL — `Cannot find module '../src/normalize'`.

- [ ] **Step 3: Implementar `relay/src/normalize.js`**

```js
// Parse + sanitização + validação do payload do webhook.
// Aceita JSON, form-encoded e query string; devolve um objeto normalizado.

class ValidationError extends Error {
  constructor(message) { super(message); this.name = 'ValidationError'; this.statusCode = 400; }
}

const TITLE_MAX = 200;
const BODY_MAX = 1000;
const ID_MAX = 200;

/** Remove caracteres de controle (C0/C1) e apara; depois trunca. */
function clean(value, max) {
  if (typeof value !== 'string') return '';
  const stripped = value.replace(/[\x00-\x1f\x7f-\x9f]/g, ' ').trim();
  return stripped.slice(0, max);
}

/** Só aceita os esquemas dados; senão null. */
function safeURL(value, schemes) {
  if (typeof value !== 'string' || value === '') return null;
  try {
    const u = new URL(value);
    return schemes.includes(u.protocol) ? value : null;
  } catch { return null; }
}

function toBool(value) {
  if (value === true) return true;
  if (typeof value === 'string') return value === 'true' || value === '1';
  return false;
}

/** contentType: string; rawBody: string; query: objeto (chaves→valores string). */
function normalizePayload({ contentType = '', rawBody = '', query = {} }) {
  let raw = {};
  const ct = contentType.toLowerCase();
  if (ct.includes('application/json')) {
    try { raw = JSON.parse(rawBody || '{}'); }
    catch { throw new ValidationError('JSON inválido'); }
    if (raw === null || typeof raw !== 'object') throw new ValidationError('JSON não é objeto');
  } else if (ct.includes('application/x-www-form-urlencoded')) {
    raw = Object.fromEntries(new URLSearchParams(rawBody));
  }
  // query string sempre pode preencher o que faltar (corpo tem prioridade)
  raw = { ...query, ...raw };

  const title = clean(raw.title, TITLE_MAX);
  if (!title) throw new ValidationError('title é obrigatório');

  return {
    title,
    body: clean(raw.body, BODY_MAX),
    iconURL: safeURL(raw.icon, ['https:']),
    url: safeURL(raw.url, ['http:', 'https:']),
    sound: toBool(raw.sound),
    id: raw.id != null ? clean(String(raw.id), ID_MAX) || null : null,
  };
}

module.exports = { normalizePayload, ValidationError };
```

- [ ] **Step 4: Rodar e ver passar**

Run: `cd relay && node --test test/normalize.test.js`
Expected: PASS (6 testes).

- [ ] **Step 5: Commit**

```bash
git add relay/src/normalize.js relay/test/normalize.test.js
git commit -m "feat(relay): normalização e sanitização do payload (JSON/form/query)"
```

---

### Task 3: `db.js` — SQLite (devices + fila offline)

**Files:**
- Create: `relay/src/db.js`
- Test: `relay/test/db.test.js`

**Interfaces:**
- Consumes: nada (recebe strings já hasheadas de quem chama).
- Produces: `openDB(path: string): DB` onde `DB` tem:
  - `createDevice({ deviceId, deviceSecretHash, publishTokenHash, now }): void`
  - `findByPublishTokenHash(hash): row | undefined` — row: `{ device_id, device_secret_h, publish_token_h, created_at, last_seen_at }`
  - `findBySecretHash(hash): row | undefined`
  - `rotatePublishToken({ deviceId, publishTokenHash }): void`
  - `touchDevice({ deviceId, now }): void`
  - `enqueue({ deviceId, payload, dedupeId, now }): void` — `payload: object`. Se `dedupeId` não-nulo, remove enfileirados do mesmo device com mesmo `dedupe_id` antes de inserir (replace). Depois **poda**: mantém no máx 50 mais recentes por device e descarta > 24h.
  - `drainQueue({ deviceId, now }): object[]` — devolve os payloads (ordenados por `created_at` asc, ≤24h) e **remove** todos os enfileirados daquele device.
  - `prune({ now }): void` — remove > 24h e excedente de 50/device (varredura periódica).
  - `close(): void`
  - `_db` (o handle bruto, só pra testes).

- [ ] **Step 1: Escrever o teste que falha — `relay/test/db.test.js`**

```js
const { test } = require('node:test');
const assert = require('node:assert');
const { openDB } = require('../src/db');

const HOUR = 3600_000;

function freshDevice(db, now = 1_000_000) {
  db.createDevice({ deviceId: 'd1', deviceSecretHash: 'sh', publishTokenHash: 'ph', now });
}

test('createDevice + lookups por hash', () => {
  const db = openDB(':memory:');
  freshDevice(db);
  assert.strictEqual(db.findByPublishTokenHash('ph').device_id, 'd1');
  assert.strictEqual(db.findBySecretHash('sh').device_id, 'd1');
  assert.strictEqual(db.findByPublishTokenHash('nope'), undefined);
  db.close();
});

test('rotatePublishToken troca o hash e o antigo não resolve', () => {
  const db = openDB(':memory:');
  freshDevice(db);
  db.rotatePublishToken({ deviceId: 'd1', publishTokenHash: 'ph2' });
  assert.strictEqual(db.findByPublishTokenHash('ph'), undefined);
  assert.strictEqual(db.findByPublishTokenHash('ph2').device_id, 'd1');
  db.close();
});

test('enqueue/drain devolve na ordem e esvazia', () => {
  const db = openDB(':memory:');
  freshDevice(db);
  db.enqueue({ deviceId: 'd1', payload: { title: 'a' }, dedupeId: null, now: 1 });
  db.enqueue({ deviceId: 'd1', payload: { title: 'b' }, dedupeId: null, now: 2 });
  const drained = db.drainQueue({ deviceId: 'd1', now: 3 });
  assert.deepStrictEqual(drained.map((p) => p.title), ['a', 'b']);
  assert.deepStrictEqual(db.drainQueue({ deviceId: 'd1', now: 4 }), [], 'esvaziou');
  db.close();
});

test('replace por dedupeId: mesmo id substitui', () => {
  const db = openDB(':memory:');
  freshDevice(db);
  db.enqueue({ deviceId: 'd1', payload: { title: '0%' }, dedupeId: 'job', now: 1 });
  db.enqueue({ deviceId: 'd1', payload: { title: '50%' }, dedupeId: 'job', now: 2 });
  const drained = db.drainQueue({ deviceId: 'd1', now: 3 });
  assert.deepStrictEqual(drained.map((p) => p.title), ['50%'], 'só a última versão');
  db.close();
});

test('cap de 50 por device: guarda os mais novos', () => {
  const db = openDB(':memory:');
  freshDevice(db);
  for (let i = 0; i < 60; i++) db.enqueue({ deviceId: 'd1', payload: { n: i }, dedupeId: null, now: i + 1 });
  const drained = db.drainQueue({ deviceId: 'd1', now: 999 });
  assert.strictEqual(drained.length, 50);
  assert.strictEqual(drained[0].n, 10, 'descartou os 10 mais antigos');
  assert.strictEqual(drained[49].n, 59);
  db.close();
});

test('TTL 24h: prune remove antigos', () => {
  const db = openDB(':memory:');
  freshDevice(db);
  db.enqueue({ deviceId: 'd1', payload: { title: 'velho' }, dedupeId: null, now: 0 });
  db.enqueue({ deviceId: 'd1', payload: { title: 'novo' }, dedupeId: null, now: 25 * HOUR });
  db.prune({ now: 25 * HOUR });
  const drained = db.drainQueue({ deviceId: 'd1', now: 25 * HOUR });
  assert.deepStrictEqual(drained.map((p) => p.title), ['novo']);
  db.close();
});
```

- [ ] **Step 2: Rodar e ver falhar**

Run: `cd relay && node --test test/db.test.js`
Expected: FAIL — `Cannot find module '../src/db'`.

- [ ] **Step 3: Implementar `relay/src/db.js`**

```js
// Estado do relay em SQLite (better-sqlite3, WAL). Devices + fila offline.
const Database = require('better-sqlite3');

const QUEUE_CAP = 50;
const QUEUE_TTL_MS = 24 * 3600 * 1000;

function openDB(path) {
  const db = new Database(path, { timeout: 5000 });
  db.pragma('journal_mode = WAL');
  db.pragma('synchronous = NORMAL');
  db.exec(`
    CREATE TABLE IF NOT EXISTS devices (
      device_id        TEXT PRIMARY KEY,
      device_secret_h  TEXT NOT NULL,
      publish_token_h  TEXT NOT NULL,
      created_at       INTEGER NOT NULL,
      last_seen_at     INTEGER
    );
    CREATE INDEX IF NOT EXISTS idx_dev_pub ON devices(publish_token_h);
    CREATE INDEX IF NOT EXISTS idx_dev_sec ON devices(device_secret_h);
    CREATE TABLE IF NOT EXISTS queued (
      id         INTEGER PRIMARY KEY AUTOINCREMENT,
      device_id  TEXT NOT NULL,
      payload    TEXT NOT NULL,
      dedupe_id  TEXT,
      created_at INTEGER NOT NULL
    );
    CREATE INDEX IF NOT EXISTS idx_q_dev ON queued(device_id, created_at);
  `);

  const stmts = {
    create: db.prepare(`INSERT INTO devices (device_id, device_secret_h, publish_token_h, created_at)
                        VALUES (@deviceId, @deviceSecretHash, @publishTokenHash, @now)`),
    byPub: db.prepare('SELECT * FROM devices WHERE publish_token_h = ?'),
    bySec: db.prepare('SELECT * FROM devices WHERE device_secret_h = ?'),
    rotate: db.prepare('UPDATE devices SET publish_token_h = @publishTokenHash WHERE device_id = @deviceId'),
    touch: db.prepare('UPDATE devices SET last_seen_at = @now WHERE device_id = @deviceId'),
    delDedupe: db.prepare('DELETE FROM queued WHERE device_id = ? AND dedupe_id = ?'),
    ins: db.prepare(`INSERT INTO queued (device_id, payload, dedupe_id, created_at)
                     VALUES (@deviceId, @payload, @dedupeId, @now)`),
    listFresh: db.prepare(`SELECT id, payload FROM queued
                           WHERE device_id = ? AND created_at > ? ORDER BY created_at ASC, id ASC`),
    delForDevice: db.prepare('DELETE FROM queued WHERE device_id = ?'),
    // poda: mantém os QUEUE_CAP mais recentes por device
    trim: db.prepare(`DELETE FROM queued WHERE device_id = ? AND id NOT IN
                      (SELECT id FROM queued WHERE device_id = ? ORDER BY created_at DESC, id DESC LIMIT ${QUEUE_CAP})`),
    pruneOld: db.prepare('DELETE FROM queued WHERE created_at <= ?'),
    allDevices: db.prepare('SELECT device_id FROM queued GROUP BY device_id'),
  };

  return {
    _db: db,
    createDevice: (a) => stmts.create.run(a),
    findByPublishTokenHash: (h) => stmts.byPub.get(h),
    findBySecretHash: (h) => stmts.bySec.get(h),
    rotatePublishToken: (a) => stmts.rotate.run(a),
    touchDevice: (a) => stmts.touch.run(a),

    enqueue: ({ deviceId, payload, dedupeId, now }) => {
      const tx = db.transaction(() => {
        if (dedupeId) stmts.delDedupe.run(deviceId, dedupeId);
        stmts.ins.run({ deviceId, payload: JSON.stringify(payload), dedupeId: dedupeId ?? null, now });
        stmts.pruneOld.run(now - QUEUE_TTL_MS);
        stmts.trim.run(deviceId, deviceId);
      });
      tx();
    },

    drainQueue: ({ deviceId, now }) => {
      const rows = stmts.listFresh.all(deviceId, now - QUEUE_TTL_MS);
      stmts.delForDevice.run(deviceId);
      return rows.map((r) => JSON.parse(r.payload));
    },

    prune: ({ now }) => {
      const tx = db.transaction(() => {
        stmts.pruneOld.run(now - QUEUE_TTL_MS);
        for (const { device_id } of stmts.allDevices.all()) stmts.trim.run(device_id, device_id);
      });
      tx();
    },

    close: () => db.close(),
  };
}

module.exports = { openDB, QUEUE_CAP, QUEUE_TTL_MS };
```

- [ ] **Step 4: Rodar e ver passar**

Run: `cd relay && node --test test/db.test.js`
Expected: PASS (6 testes).

- [ ] **Step 5: Commit**

```bash
git add relay/src/db.js relay/test/db.test.js
git commit -m "feat(relay): storage SQLite de devices e fila offline (cap 50/24h, replace por id)"
```

---

### Task 4: `ratelimit.js` — token bucket em memória

**Files:**
- Create: `relay/src/ratelimit.js`
- Test: `relay/test/ratelimit.test.js`

**Interfaces:**
- Consumes: nada.
- Produces: `createRateLimiter({ ratePerMin = 20, burst = 5, now = Date.now }): { allow(key): { ok: boolean, retryAfter: number } }`. `now` é uma função (ms) injetável pra teste. `retryAfter` em segundos (arredondado pra cima) quando `ok` for false.

- [ ] **Step 1: Escrever o teste que falha — `relay/test/ratelimit.test.js`**

```js
const { test } = require('node:test');
const assert = require('node:assert');
const { createRateLimiter } = require('../src/ratelimit');

test('burst de 5 passa, o 6º é bloqueado', () => {
  let t = 0;
  const rl = createRateLimiter({ ratePerMin: 20, burst: 5, now: () => t });
  for (let i = 0; i < 5; i++) assert.strictEqual(rl.allow('k').ok, true, `req ${i}`);
  const sixth = rl.allow('k');
  assert.strictEqual(sixth.ok, false);
  assert.ok(sixth.retryAfter >= 1, 'retryAfter em segundos');
});

test('reabastece com o tempo (20/min = 1 token a cada 3s)', () => {
  let t = 0;
  const rl = createRateLimiter({ ratePerMin: 20, burst: 5, now: () => t });
  for (let i = 0; i < 5; i++) rl.allow('k');   // esvazia o balde
  assert.strictEqual(rl.allow('k').ok, false);
  t = 3000;                                     // +3s → +1 token
  assert.strictEqual(rl.allow('k').ok, true);
  assert.strictEqual(rl.allow('k').ok, false);
});

test('chaves diferentes têm baldes independentes', () => {
  let t = 0;
  const rl = createRateLimiter({ ratePerMin: 20, burst: 5, now: () => t });
  for (let i = 0; i < 5; i++) rl.allow('a');
  assert.strictEqual(rl.allow('a').ok, false);
  assert.strictEqual(rl.allow('b').ok, true, 'b não é afetado por a');
});
```

- [ ] **Step 2: Rodar e ver falhar**

Run: `cd relay && node --test test/ratelimit.test.js`
Expected: FAIL — `Cannot find module '../src/ratelimit'`.

- [ ] **Step 3: Implementar `relay/src/ratelimit.js`**

```js
// Token bucket em memória por chave (deviceId). Sem dependências externas.
function createRateLimiter({ ratePerMin = 20, burst = 5, now = Date.now } = {}) {
  const refillPerMs = ratePerMin / 60000; // tokens por ms
  const buckets = new Map(); // key -> { tokens, ts }

  return {
    allow(key) {
      const t = now();
      let b = buckets.get(key);
      if (!b) { b = { tokens: burst, ts: t }; buckets.set(key, b); }
      // reabastece proporcional ao tempo passado, com teto no burst
      b.tokens = Math.min(burst, b.tokens + (t - b.ts) * refillPerMs);
      b.ts = t;
      if (b.tokens >= 1) { b.tokens -= 1; return { ok: true, retryAfter: 0 }; }
      const needed = 1 - b.tokens;
      const retryAfter = Math.ceil(needed / refillPerMs / 1000);
      return { ok: false, retryAfter: Math.max(1, retryAfter) };
    },
  };
}

module.exports = { createRateLimiter };
```

- [ ] **Step 4: Rodar e ver passar**

Run: `cd relay && node --test test/ratelimit.test.js`
Expected: PASS (3 testes).

- [ ] **Step 5: Commit**

```bash
git add relay/src/ratelimit.js relay/test/ratelimit.test.js
git commit -m "feat(relay): rate limit token-bucket em memória por device"
```

---

### Task 5: `hub.js` — conexões vivas + heartbeat

**Files:**
- Create: `relay/src/hub.js`
- Test: `relay/test/hub.test.js`

**Interfaces:**
- Consumes: objetos "ws-like" com `readyState`, `OPEN` (const), `send(str)`, `ping()`, `terminate()`, `close(code, reason)`. (Os sockets reais do `ws` têm tudo isso.)
- Produces: `createHub(): Hub` com:
  - `add(deviceId, ws): void` — se já existe socket pro device, fecha o antigo (`close(1000,'replaced')`) antes de registrar o novo; seta `ws.isAlive = true`.
  - `remove(deviceId, ws): void` — só remove se o socket atual for esse (evita remover a conexão nova quando a antiga fecha).
  - `isOnline(deviceId): boolean`
  - `send(deviceId, obj): boolean` — `JSON.stringify` + `send` se `readyState === OPEN`; retorna true se enviou.
  - `markAlive(deviceId): void` — seta `isAlive = true` no socket atual (chamado no `pong`).
  - `heartbeat(): void` — pra cada socket: se `isAlive === false` → `terminate()` + remove; senão `isAlive = false` + `ping()`.
  - `closeAll(code = 1001): void`
  - `size(): number`

- [ ] **Step 1: Escrever o teste que falha — `relay/test/hub.test.js`**

```js
const { test } = require('node:test');
const assert = require('node:assert');
const { createHub } = require('../src/hub');

function fakeWs() {
  return {
    OPEN: 1, readyState: 1, sent: [], pinged: 0, terminated: false, closedWith: null,
    send(s) { this.sent.push(s); },
    ping() { this.pinged++; },
    terminate() { this.terminated = true; this.readyState = 3; },
    close(code, reason) { this.closedWith = { code, reason }; this.readyState = 3; },
  };
}

test('add/isOnline/send serializa e entrega', () => {
  const hub = createHub();
  const ws = fakeWs();
  hub.add('d1', ws);
  assert.strictEqual(hub.isOnline('d1'), true);
  assert.strictEqual(hub.send('d1', { type: 'notify', title: 'oi' }), true);
  assert.deepStrictEqual(JSON.parse(ws.sent[0]), { type: 'notify', title: 'oi' });
  assert.strictEqual(hub.isOnline('outro'), false);
  assert.strictEqual(hub.send('outro', {}), false);
});

test('reconexão do mesmo device fecha o socket antigo', () => {
  const hub = createHub();
  const oldWs = fakeWs(); const newWs = fakeWs();
  hub.add('d1', oldWs);
  hub.add('d1', newWs);
  assert.deepStrictEqual(oldWs.closedWith, { code: 1000, reason: 'replaced' });
  assert.strictEqual(hub.size(), 1);
  assert.strictEqual(hub.send('d1', { x: 1 }), true);
  assert.strictEqual(newWs.sent.length, 1, 'só o novo recebe');
});

test('remove só remove o socket atual', () => {
  const hub = createHub();
  const oldWs = fakeWs(); const newWs = fakeWs();
  hub.add('d1', oldWs);
  hub.add('d1', newWs);            // oldWs foi substituído
  hub.remove('d1', oldWs);         // close tardio do antigo não deve derrubar o novo
  assert.strictEqual(hub.isOnline('d1'), true);
  hub.remove('d1', newWs);
  assert.strictEqual(hub.isOnline('d1'), false);
});

test('heartbeat termina quem não respondeu e faz ping em quem respondeu', () => {
  const hub = createHub();
  const ws = fakeWs();
  hub.add('d1', ws);              // isAlive = true
  hub.heartbeat();               // marca isAlive=false, ping
  assert.strictEqual(ws.pinged, 1);
  assert.strictEqual(ws.terminated, false);
  hub.heartbeat();               // não houve pong → termina
  assert.strictEqual(ws.terminated, true);
  assert.strictEqual(hub.isOnline('d1'), false);
});

test('markAlive impede o terminate no próximo heartbeat', () => {
  const hub = createHub();
  const ws = fakeWs();
  hub.add('d1', ws);
  hub.heartbeat();               // isAlive=false, ping
  hub.markAlive('d1');           // chegou pong
  hub.heartbeat();               // deve pingar de novo, não terminar
  assert.strictEqual(ws.terminated, false);
  assert.strictEqual(ws.pinged, 2);
});
```

- [ ] **Step 2: Rodar e ver falhar**

Run: `cd relay && node --test test/hub.test.js`
Expected: FAIL — `Cannot find module '../src/hub'`.

- [ ] **Step 3: Implementar `relay/src/hub.js`**

```js
// Hub de conexões vivas: 1 socket por device + heartbeat.
function createHub() {
  const conns = new Map(); // deviceId -> ws

  function add(deviceId, ws) {
    const old = conns.get(deviceId);
    if (old && old !== ws) old.close(1000, 'replaced');
    ws.isAlive = true;
    conns.set(deviceId, ws);
  }

  function remove(deviceId, ws) {
    if (conns.get(deviceId) === ws) conns.delete(deviceId);
  }

  function isOnline(deviceId) {
    const ws = conns.get(deviceId);
    return !!ws && ws.readyState === ws.OPEN;
  }

  function send(deviceId, obj) {
    const ws = conns.get(deviceId);
    if (!ws || ws.readyState !== ws.OPEN) return false;
    ws.send(JSON.stringify(obj));
    return true;
  }

  function markAlive(deviceId) {
    const ws = conns.get(deviceId);
    if (ws) ws.isAlive = true;
  }

  function heartbeat() {
    for (const [deviceId, ws] of conns) {
      if (ws.isAlive === false) { ws.terminate(); conns.delete(deviceId); continue; }
      ws.isAlive = false;
      ws.ping();
    }
  }

  function closeAll(code = 1001) {
    for (const ws of conns.values()) ws.close(code, 'shutdown');
    conns.clear();
  }

  return { add, remove, isOnline, send, markAlive, heartbeat, closeAll, size: () => conns.size };
}

module.exports = { createHub };
```

- [ ] **Step 4: Rodar e ver passar**

Run: `cd relay && node --test test/hub.test.js`
Expected: PASS (5 testes).

- [ ] **Step 5: Commit**

```bash
git add relay/src/hub.js relay/test/hub.test.js
git commit -m "feat(relay): hub de conexões vivas com heartbeat e replace por device"
```

---

### Task 6: `server.js` — integração HTTP + WebSocket (+ teste E2E in-process)

**Files:**
- Create: `relay/src/server.js`
- Test: `relay/test/server.test.js`

**Interfaces:**
- Consumes: `openDB`, `createHub`, `createRateLimiter`, `normalizePayload`/`ValidationError`, `genToken`/`sha256`.
- Produces: `createServer({ db, hub, rateLimiter }): { httpServer, wss, heartbeat, start(port, host, cb), stop(cb) }`. As rotas:
  - `POST /register` → 200 `{ deviceId, deviceSecret, publishToken }` (segredos só aqui em claro).
  - `POST /rotate` (auth `Authorization: Bearer <deviceSecret>`) → 200 `{ publishToken }`.
  - `POST /w/<publishToken>` → 202 `{ ok:true, delivered:'push'|'queued' }` | 400 | 404 | 429.
  - `GET /health` → 200 `{ ok:true, online: <n> }`.
  - `GET /ws` (upgrade, auth por header) → conexão viva; ao abrir, drena a fila.

- [ ] **Step 1: Escrever o teste E2E que falha — `relay/test/server.test.js`**

```js
const { test } = require('node:test');
const assert = require('node:assert');
const WebSocket = require('ws');
const { openDB } = require('../src/db');
const { createHub } = require('../src/hub');
const { createRateLimiter } = require('../src/ratelimit');
const { createServer } = require('../src/server');

function boot() {
  const db = openDB(':memory:');
  const hub = createHub();
  const rateLimiter = createRateLimiter({ ratePerMin: 20, burst: 5 });
  const srv = createServer({ db, hub, rateLimiter });
  return new Promise((resolve) => {
    srv.start(0, '127.0.0.1', () => {
      const port = srv.httpServer.address().port;
      resolve({ srv, db, port, base: `http://127.0.0.1:${port}` });
    });
  });
}

async function post(base, path, { body, headers } = {}) {
  const res = await fetch(base + path, { method: 'POST', body, headers });
  const text = await res.text();
  return { status: res.status, json: text ? JSON.parse(text) : null };
}

test('register → webhook ao vivo chega pelo WebSocket', async () => {
  const { srv, port, base } = await boot();
  const reg = await post(base, '/register');
  assert.strictEqual(reg.status, 200);
  const { deviceSecret, publishToken } = reg.json;

  const ws = new WebSocket(`ws://127.0.0.1:${port}/ws`, {
    headers: { Authorization: `Bearer ${deviceSecret}` },
  });
  const opened = new Promise((r) => ws.on('open', r));
  const gotMsg = new Promise((r) => ws.on('message', (d) => r(JSON.parse(d.toString()))));
  await opened;

  const pub = await post(base, `/w/${publishToken}`, {
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ title: 'Oi', body: 'ao vivo' }),
  });
  assert.strictEqual(pub.status, 202);
  assert.strictEqual(pub.json.delivered, 'push');

  const msg = await gotMsg;
  assert.strictEqual(msg.type, 'notify');
  assert.strictEqual(msg.title, 'Oi');
  ws.close();
  await new Promise((r) => srv.stop(r));
});

test('webhook com device offline enfileira e drena no connect', async () => {
  const { srv, port, base } = await boot();
  const { deviceSecret, publishToken } = (await post(base, '/register')).json;

  // device offline: publica antes de conectar
  const pub = await post(base, `/w/${publishToken}`, {
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ title: 'guardado' }),
  });
  assert.strictEqual(pub.json.delivered, 'queued');

  const ws = new WebSocket(`ws://127.0.0.1:${port}/ws`, {
    headers: { Authorization: `Bearer ${deviceSecret}` },
  });
  const gotMsg = new Promise((r) => ws.on('message', (d) => r(JSON.parse(d.toString()))));
  const msg = await gotMsg;
  assert.strictEqual(msg.title, 'guardado');
  ws.close();
  await new Promise((r) => srv.stop(r));
});

test('token desconhecido → 404; sem title → 400', async () => {
  const { srv, base } = await boot();
  assert.strictEqual((await post(base, '/w/naoexiste', {
    headers: { 'Content-Type': 'application/json' }, body: '{"title":"x"}' })).status, 404);
  const { publishToken } = (await post(base, '/register')).json;
  assert.strictEqual((await post(base, `/w/${publishToken}`, {
    headers: { 'Content-Type': 'application/json' }, body: '{"body":"sem titulo"}' })).status, 400);
  await new Promise((r) => srv.stop(r));
});

test('WebSocket sem/errado deviceSecret → recusado', async () => {
  const { srv, port } = await boot();
  const ws = new WebSocket(`ws://127.0.0.1:${port}/ws`, { headers: { Authorization: 'Bearer errado' } });
  const failed = await new Promise((r) => { ws.on('error', () => r(true)); ws.on('open', () => r(false)); });
  assert.strictEqual(failed, true);
  await new Promise((r) => srv.stop(r));
});

test('rate limit: o 6º POST rápido no mesmo token → 429', async () => {
  const { srv, base } = await boot();
  const { publishToken } = (await post(base, '/register')).json;
  const h = { 'Content-Type': 'application/json' };
  const body = '{"title":"x"}';
  let last;
  for (let i = 0; i < 6; i++) last = await post(base, `/w/${publishToken}`, { headers: h, body });
  assert.strictEqual(last.status, 429);
  await new Promise((r) => srv.stop(r));
});
```

- [ ] **Step 2: Rodar e ver falhar**

Run: `cd relay && node --test test/server.test.js`
Expected: FAIL — `Cannot find module '../src/server'`.

- [ ] **Step 3: Implementar `relay/src/server.js`**

```js
// Monta o servidor HTTP + WebSocket e fia as peças.
const http = require('http');
const { WebSocketServer } = require('ws');
const { genToken, sha256 } = require('./tokens');
const { normalizePayload, ValidationError } = require('./normalize');

function readBody(req, limitBytes = 64 * 1024) {
  return new Promise((resolve, reject) => {
    let size = 0; const chunks = [];
    req.on('data', (c) => {
      size += c.length;
      if (size > limitBytes) { reject(new ValidationError('payload grande demais')); req.destroy(); return; }
      chunks.push(c);
    });
    req.on('end', () => resolve(Buffer.concat(chunks).toString('utf8')));
    req.on('error', reject);
  });
}

function json(res, status, obj) {
  const body = JSON.stringify(obj);
  res.writeHead(status, { 'Content-Type': 'application/json', 'Content-Length': Buffer.byteLength(body) });
  res.end(body);
}

/** Segredo truncado pra log: nunca logar o valor cru. */
function redact(s) { return s && s.length > 8 ? `${s.slice(0, 4)}…${s.slice(-4)}` : '****'; }

function createServer({ db, hub, rateLimiter }) {
  const httpServer = http.createServer(handle);
  const wss = new WebSocketServer({ noServer: true });

  async function handle(req, res) {
    try {
      const url = new URL(req.url, 'http://localhost');
      const path = url.pathname;

      if (req.method === 'GET' && path === '/health') {
        return json(res, 200, { ok: true, online: hub.size() });
      }

      if (req.method === 'POST' && path === '/register') {
        const deviceId = genToken();          // uuid-like opaco; reusa gerador
        const deviceSecret = genToken();
        const publishToken = genToken();
        db.createDevice({
          deviceId,
          deviceSecretHash: sha256(deviceSecret),
          publishTokenHash: sha256(publishToken),
          now: Date.now(),
        });
        return json(res, 200, { deviceId, deviceSecret, publishToken });
      }

      if (req.method === 'POST' && path === '/rotate') {
        const auth = req.headers['authorization'] || '';
        const secret = auth.startsWith('Bearer ') ? auth.slice(7) : '';
        const dev = secret && db.findBySecretHash(sha256(secret));
        if (!dev) return json(res, 401, { ok: false, error: 'deviceSecret inválido' });
        const publishToken = genToken();
        db.rotatePublishToken({ deviceId: dev.device_id, publishTokenHash: sha256(publishToken) });
        return json(res, 200, { ok: true, publishToken });
      }

      if (req.method === 'POST' && path.startsWith('/w/')) {
        const publishToken = decodeURIComponent(path.slice('/w/'.length));
        const dev = db.findByPublishTokenHash(sha256(publishToken));
        if (!dev) return json(res, 404, { ok: false, error: 'token desconhecido' });

        const gate = rateLimiter.allow(dev.device_id);
        if (!gate.ok) {
          res.setHeader('Retry-After', String(gate.retryAfter));
          return json(res, 429, { ok: false, error: 'rate limit' });
        }

        const rawBody = await readBody(req);
        const msg = { type: 'notify',
          ...normalizePayload({ contentType: req.headers['content-type'] || '', rawBody,
            query: Object.fromEntries(url.searchParams) }),
          ts: Date.now() };

        if (hub.send(dev.device_id, msg)) {
          return json(res, 202, { ok: true, delivered: 'push' });
        }
        db.enqueue({ deviceId: dev.device_id, payload: msg, dedupeId: msg.id, now: Date.now() });
        return json(res, 202, { ok: true, delivered: 'queued' });
      }

      return json(res, 404, { ok: false, error: 'rota desconhecida' });
    } catch (err) {
      if (err instanceof ValidationError) return json(res, err.statusCode, { ok: false, error: err.message });
      console.error('erro no handler:', err);
      return json(res, 500, { ok: false, error: 'erro interno' });
    }
  }

  httpServer.on('upgrade', (req, socket, head) => {
    const url = new URL(req.url, 'http://localhost');
    const auth = req.headers['authorization'] || '';
    const secret = auth.startsWith('Bearer ') ? auth.slice(7) : '';
    const dev = secret && db.findBySecretHash(sha256(secret));
    if (url.pathname !== '/ws' || !dev) {
      socket.write('HTTP/1.1 401 Unauthorized\r\n\r\n'); socket.destroy(); return;
    }
    wss.handleUpgrade(req, socket, head, (ws) => {
      hub.add(dev.device_id, ws);
      db.touchDevice({ deviceId: dev.device_id, now: Date.now() });
      ws.on('pong', () => hub.markAlive(dev.device_id));
      ws.on('close', () => hub.remove(dev.device_id, ws));
      ws.on('error', () => hub.remove(dev.device_id, ws));
      // drena a fila offline acumulada
      for (const payload of db.drainQueue({ deviceId: dev.device_id, now: Date.now() })) {
        ws.send(JSON.stringify(payload));
      }
      console.log(`ws conectado device=${redact(dev.device_id)}`);
    });
  });

  const heartbeat = () => hub.heartbeat();

  return {
    httpServer, wss, heartbeat,
    start: (port, host, cb) => httpServer.listen(port, host, cb),
    stop: (cb) => { hub.closeAll(); wss.close(() => httpServer.close(cb)); },
  };
}

module.exports = { createServer };
```

- [ ] **Step 4: Rodar e ver passar**

Run: `cd relay && node --test test/server.test.js`
Expected: PASS (5 testes). (Usa `fetch` e `WebSocket` — `fetch` é global no Node 18; `ws` como cliente.)

- [ ] **Step 5: Rodar a suíte inteira**

Run: `cd relay && node --test`
Expected: PASS — todos os arquivos de teste (tokens, normalize, db, ratelimit, hub, server).

- [ ] **Step 6: Commit**

```bash
git add relay/src/server.js relay/test/server.test.js
git commit -m "feat(relay): servidor HTTP+WebSocket integrado (register/rotate/ingress/ws) + E2E"
```

---

### Task 7: Entrypoint + pm2 + graceful shutdown

**Files:**
- Create: `relay/src/index.js`
- Create: `relay/ecosystem.config.js`

**Interfaces:**
- Consumes: `openDB`, `createHub`, `createRateLimiter`, `createServer`.
- Produces: um processo que escuta em `127.0.0.1:PORT` (env `PORT`, default 8477), com heartbeat a cada 30s, prune da fila a cada 5min, e shutdown limpo em SIGINT/SIGTERM.

- [ ] **Step 1: Implementar `relay/src/index.js`**

```js
// Entrypoint do relay: abre DB, fia tudo, timers e graceful shutdown.
const path = require('path');
const { openDB } = require('./db');
const { createHub } = require('./hub');
const { createRateLimiter } = require('./ratelimit');
const { createServer } = require('./server');

const PORT = Number(process.env.PORT || 8477);
const HOST = '127.0.0.1';
const DB_PATH = process.env.RELAY_DB || path.join(__dirname, '..', 'relay.db');

const db = openDB(DB_PATH);
const hub = createHub();
const rateLimiter = createRateLimiter({ ratePerMin: 20, burst: 5 });
const srv = createServer({ db, hub, rateLimiter });

const heartbeatTimer = setInterval(() => srv.heartbeat(), 30_000);
const pruneTimer = setInterval(() => db.prune({ now: Date.now() }), 5 * 60_000);
heartbeatTimer.unref(); pruneTimer.unref();

srv.start(PORT, HOST, () => console.log(`knobler-relay escutando em ${HOST}:${PORT}`));

let shuttingDown = false;
function shutdown(sig) {
  if (shuttingDown) return;
  shuttingDown = true;
  console.log(`recebido ${sig}, encerrando…`);
  clearInterval(heartbeatTimer); clearInterval(pruneTimer);
  srv.stop(() => {
    try { db._db.pragma('wal_checkpoint(RESTART)'); db.close(); } catch (e) { console.error(e); }
    process.exit(0);
  });
  setTimeout(() => process.exit(1), 9000).unref(); // rede de segurança < kill_timeout
}
process.on('SIGINT', () => shutdown('SIGINT'));
process.on('SIGTERM', () => shutdown('SIGTERM'));
```

- [ ] **Step 2: Implementar `relay/ecosystem.config.js`**

```js
module.exports = {
  apps: [{
    name: 'knobler-relay',
    script: './src/index.js',
    cwd: __dirname,
    instances: 1,
    exec_mode: 'fork',
    kill_timeout: 10000,
    max_memory_restart: '200M',
    env: { NODE_ENV: 'production', PORT: 8477 },
  }],
};
```

- [ ] **Step 3: Fumaça local (manual)**

Run:
```bash
cd relay && PORT=8477 RELAY_DB=/tmp/knobler-relay-smoke.db node src/index.js &
sleep 1
curl -s localhost:8477/health
TOKENS=$(curl -s -X POST localhost:8477/register)
echo "$TOKENS"
PUB=$(echo "$TOKENS" | node -e 'process.stdin.on("data",d=>console.log(JSON.parse(d).publishToken))')
curl -s -X POST "localhost:8477/w/$PUB" -H 'Content-Type: application/json' -d '{"title":"Oi","body":"fumaça"}'
kill %1
rm -f /tmp/knobler-relay-smoke.db*
```
Expected: `/health` → `{"ok":true,"online":0}`; `/register` → JSON com 3 campos; o POST no `/w/` com device offline → `{"ok":true,"delivered":"queued"}`.

- [ ] **Step 4: Commit**

```bash
git add relay/src/index.js relay/ecosystem.config.js
git commit -m "feat(relay): entrypoint com heartbeat, prune, graceful shutdown e config pm2"
```

---

### Task 8: Deploy na VPS (nginx + certbot + pm2) + README

**Files:**
- Create: `relay/README.md`

> **Pré-requisito do usuário (fora do controle do agente):** criar o registro **DNS A**
> `push.appzoi.com.br → 147.79.87.179` no provedor de DNS do `appzoi.com.br` e esperar
> propagar (`dig +short push.appzoi.com.br` deve retornar o IP) **antes** do certbot.

- [ ] **Step 1: Escrever `relay/README.md`**

````markdown
# knobler-relay

Relay HTTP+WebSocket das notificações externas do Knobler.

## Deploy (VPS Ubuntu 24.04, nginx + pm2)

Pré-requisito: DNS A `push.appzoi.com.br → 147.79.87.179` propagado.

```bash
# 1. código na VPS
cd /opt && git clone <repo> knobler && cd knobler/relay   # ou rsync do subdir relay/
apt-get install -y build-essential python3                # node-gyp do better-sqlite3
npm ci --omit=dev

# 2. subir sob pm2 (porta 127.0.0.1:8477)
pm2 start ecosystem.config.js && pm2 save

# 3. vhost nginx (ver bloco abaixo) → /etc/nginx/sites-available/push.appzoi.com.br.conf
ln -s /etc/nginx/sites-available/push.appzoi.com.br.conf /etc/nginx/sites-enabled/
nginx -t && systemctl reload nginx

# 4. TLS
certbot --nginx -d push.appzoi.com.br
certbot renew --dry-run

# 5. fumaça
curl -s https://push.appzoi.com.br/health
```

### vhost nginx

Endurecido conforme o review amplo do branch: **`access_log off` na ingestão** (o
`publishToken` está no path — não pode ir pro log) e **`limit_req` de borda** em
`/register`, `/rotate` e `/w/` (o token-bucket da app é por-device e só roda após o
lookup, então **não** cobre criação de device nem token desconhecido — vetor de exaustão).

```nginx
# no bloco http {} (uma vez cada; se já houver um `map $http_upgrade` global, não duplicar):
map $http_upgrade $connection_upgrade { default upgrade; '' close; }
limit_req_zone $binary_remote_addr zone=push_ip:10m rate=120r/m;

server {
  server_name push.appzoi.com.br;
  listen 80;
  client_max_body_size 64k;

  # WebSocket (conexão longa do Mac)
  location /ws {
    proxy_pass http://127.0.0.1:8477;
    proxy_http_version 1.1;
    proxy_set_header Upgrade $http_upgrade;
    proxy_set_header Connection $connection_upgrade;
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;
    proxy_read_timeout 3600s;
    proxy_send_timeout 3600s;
    proxy_buffering off;
  }

  # Ingestão do webhook: NÃO logar (publishToken no path) + rate limit de borda
  location /w/ {
    access_log off;
    limit_req zone=push_ip burst=20 nodelay;
    proxy_pass http://127.0.0.1:8477;
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;
    proxy_read_timeout 120s;
  }

  # Criar/rotacionar device: vetor de exaustão → limite mais apertado
  location = /register {
    limit_req zone=push_ip burst=5 nodelay;
    proxy_pass http://127.0.0.1:8477;
    proxy_set_header Host $host; proxy_set_header X-Forwarded-Proto $scheme;
  }
  location = /rotate {
    limit_req zone=push_ip burst=5 nodelay;
    proxy_pass http://127.0.0.1:8477;
    proxy_set_header Host $host; proxy_set_header X-Forwarded-Proto $scheme;
  }

  # /health e resto
  location / {
    proxy_pass http://127.0.0.1:8477;
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;
    proxy_read_timeout 120s;
  }
}
```
(`/ws` e `/w/` não colidem: `/ws` não começa com `/w/`. certbot converte o `listen 80`
em 443+redirect.)

### Checklist do review (antes/durante o deploy)
- **`npm ci --omit=dev` roda sob Node 18 na VPS** → baixa o prebuilt do `better-sqlite3@11`
  pra linux-x64 ABI 108 (Node 18). Se não houver prebuilt, `apt-get install -y build-essential python3` e `npm rebuild better-sqlite3`.
- **`relay/` (onde `relay.db` é ancorado via `__dirname`) precisa ser gravável** pelo usuário do pm2.
- **NUNCA `instances > 1`** no pm2 (o hub e o rate limiter são em memória por processo — `fork`/`instances:1` é carga load-bearing; cluster quebraria o WebSocket).

## API

- `POST /register` → `{ deviceId, deviceSecret, publishToken }`
- `POST /rotate` (header `Authorization: Bearer <deviceSecret>`) → `{ publishToken }`
- `POST /w/<publishToken>` — `{title, body?, icon?, url?, sound?, id?}` (JSON/form/query)
- `GET /health`
- `GET /ws` (upgrade, header `Authorization: Bearer <deviceSecret>`)
````

- [ ] **Step 2: Confirmar porta livre na VPS**

Run: `ssh root@147.79.87.179 "ss -tlnp | grep -w 8477 || echo LIVRE"`
Expected: `LIVRE`. (Se ocupada, escolher outra e ajustar `ecosystem.config.js` + `index.js` default + nginx.)

- [ ] **Step 3: Verificar DNS antes do certbot**

Run: `dig +short push.appzoi.com.br`
Expected: `147.79.87.179`. (Se vazio, o usuário precisa criar o registro A antes de continuar.)

- [ ] **Step 4: Deploy conforme o README** (rsync do `relay/`, `npm ci --omit=dev`, `pm2 start`, vhost, `certbot`).

- [ ] **Step 5: Fumaça remota E2E**

Run:
```bash
curl -s https://push.appzoi.com.br/health
TOK=$(curl -s -X POST https://push.appzoi.com.br/register)
echo "$TOK"
# WebSocket: em outra aba, wscat conectando com o deviceSecret no header, e um POST no /w/<publishToken>
# npx wscat -c wss://push.appzoi.com.br/ws -H "Authorization: Bearer <deviceSecret>"
```
Expected: `/health` responde via HTTPS; `wscat` conecta; um `POST /w/<publishToken>` faz a mensagem `{"type":"notify",...}` aparecer no `wscat`.

- [ ] **Step 6: Commit**

```bash
git add relay/README.md
git commit -m "docs(relay): README de deploy (nginx, certbot, pm2) + fumaça E2E"
```

---

## Self-Review

**Cobertura da spec (Peça 1 — Relay):**
- Endpoints `/register`, `/rotate`, `/w/<token>`, `/ws`, `/health` → Tasks 6/7. ✅
- Token 256 bits + storage hasheado → Tasks 1, 6. ✅
- Auth do WS por header `Authorization` → Task 6 (upgrade). ✅
- Fila offline 50/24h + replace por `id` → Task 3. ✅
- Rate limit 20/min burst 5 → 429 → Tasks 4, 6. ✅
- Payload JSON/form/query + sanitização → Task 2. ✅
- Heartbeat + graceful shutdown + pm2 fork → Tasks 5, 7. ✅
- `better-sqlite3@11` WAL → Tasks 1, 3. ✅
- nginx (WS upgrade) + certbot + DNS → Task 8. ✅
- **Fora deste plano (vai pro Plano 2):** `WebhookClient.swift`, render no notch, aba de config, Keychain, imagem remota. Correto — é o outro subsistema.

**Placeholders:** nenhum "TBD/TODO"; todo passo tem código/comando completo. ✅

**Consistência de tipos:** `openDB`→`db.*`, `createHub`→`hub.*`, `createRateLimiter`→`allow`, `normalizePayload`/`ValidationError`, `genToken`/`sha256`, `createServer`→`{httpServer, wss, heartbeat, start, stop}` — usados igual entre Tasks 6/7. ✅

**Risco conhecido (validar na execução):** `better-sqlite3@11` precisa compilar na VPS (`build-essential`+`python3`) — Task 8 já instala; se falhar o prebuilt, `npm rebuild better-sqlite3`.
