# Mapeamento de webhook — Relay (Plano A de B) — Implementação

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans para executar task-a-task. Steps usam `- [ ]`.

**Goal:** Estender o relay já no ar pra suportar **perfis** (1 link + 1 mapa cada): capturar o payload cru, aplicar o template `{{dot.path}}` do perfil e empurrar a notificação; API de CRUD de perfis; migração do token único de hoje.

**Architecture:** No relay Node (`relay/`, já em produção). Novo módulo `template.js` (interpolação pura). `db.js` ganha a tabela `profiles` + migração. `server.js` ganha a API `/profiles` e o ingress `/w/<token>` passa a resolver perfil → capturar → mapear (ou captura-only).

**Tech Stack:** Node 18 · `ws`/`better-sqlite3@11` · `node:test`. Sem deps novas.

**Plano A de B.** Entrega o relay pronto e implantado, testável com `curl`. O Plano B (app: lista de perfis + editor AppKit) vem depois, contra este relay.

## Global Constraints

- Node 18 na VPS; dev/test local **Node 23.11.1** (`export PATH="/Users/luccassilveira/.nvm/versions/node/v23.11.1/bin:$PATH"` em cada comando — Homebrew node quebrado). `better-sqlite3@11`, WAL. `node:test`, zero deps de teste.
- Template = interpolação `{{ dot.path }}` (aninhado, índice de array), campo ausente/não-primitivo → **string vazia**. Sem lógica. Texto fora das chaves passa literal.
- Ingress: **mapeamento obrigatório** — perfil sem `mapping` = **captura-only** (grava `last_payload`, responde `202 {delivered:"captured"}`, não empurra). Com `mapping` = renderiza + sanitiza + empurra.
- Saída ainda passa pela **sanitização existente** (`clean` título≤200/corpo≤1000, `safeURL` http/https e https p/ ícone). Título vazio pós-render → usa o **nome do perfil** como fallback.
- Segredos 256 bits, só SHA-256. API de perfis por header `Authorization: Bearer <deviceSecret>`. `publishToken` na URL. Rate limit por **perfil**. `last_payload` capado ~16KB. Máx 50 perfis/device.
- Push ganha `iconEmoji` (opcional) junto de `iconURL`. Ícone do perfil = URL (`http`) → `iconURL`; senão (emoji) → `iconEmoji`. `iconTemplate` do mapping sobrescreve.
- Migração: cada device com `publish_token_h` vira um perfil "Padrão" (mapping NULL) na subida.
- Comentários em pt-BR. Deploy: rsync `relay/` → `/opt/knobler-relay`, `pm2 restart knobler-relay`.

---

## File Structure

- `relay/src/template.js` — **novo**: `render(tpl, payload)` + `resolve(payload, path)`.
- `relay/src/db.js` — **modifica**: tabela `profiles` + ops + `migrateProfiles()` no `openDB`.
- `relay/src/server.js` — **modifica**: API `/profiles`; `register` cria perfil padrão; ingress `/w/` por perfil.
- (test) `relay/test/template.test.js`, `db.test.js` (+casos), `server.test.js` (+casos).

---

### Task 1: `template.js` — motor de interpolação `{{dot.path}}`

**Files:** Create `relay/src/template.js`, `relay/test/template.test.js`.

**Interfaces:** `render(tpl: string, payload: object): string`; `resolve(payload: object, path: string): any` (undefined se ausente).

- [ ] **Step 1: Teste que falha — `relay/test/template.test.js`**

```js
const { test } = require('node:test');
const assert = require('node:assert');
const { render, resolve } = require('../src/template');

const p = { title: 'Deploy', repo: { name: 'knobler' }, commits: [{ msg: 'a' }, { msg: 'b' }], ok: true, n: 3 };

test('resolve dot-path + índice de array', () => {
  assert.strictEqual(resolve(p, 'repo.name'), 'knobler');
  assert.strictEqual(resolve(p, 'commits.1.msg'), 'b');
  assert.strictEqual(resolve(p, 'nao.existe'), undefined);
});

test('render mistura texto livre + variáveis', () => {
  assert.strictEqual(render('{{repo.name}}: {{commits.0.msg}}', p), 'knobler: a');
  assert.strictEqual(render('Olá {{title}} ({{n}})', p), 'Olá Deploy (3)');
});

test('campo ausente/objeto/array vira vazio; texto puro passa', () => {
  assert.strictEqual(render('x{{nao.existe}}y', p), 'xy');
  assert.strictEqual(render('{{repo}}', p), '');       // objeto → vazio
  assert.strictEqual(render('{{commits}}', p), '');    // array → vazio
  assert.strictEqual(render('sem variavel', p), 'sem variavel');
});

test('bool e número viram string', () => {
  assert.strictEqual(render('{{ok}}/{{n}}', p), 'true/3');
});

test('espaços dentro das chaves são tolerados', () => {
  assert.strictEqual(render('{{  repo.name  }}', p), 'knobler');
});
```

- [ ] **Step 2: Rodar → falha** (`Cannot find module '../src/template'`).

Run: `export PATH="/Users/luccassilveira/.nvm/versions/node/v23.11.1/bin:$PATH"; cd relay && node --test test/template.test.js`

- [ ] **Step 3: Implementar `relay/src/template.js`**

```js
// Interpolação {{ dot.path }} — pura, sem lógica. Ausente/não-primitivo → vazio.
function resolve(payload, path) {
  let cur = payload;
  for (const part of path.split('.')) {
    if (cur == null || typeof cur !== 'object') return undefined;
    cur = Array.isArray(cur) ? cur[Number(part)] : cur[part];
  }
  return cur;
}

function render(tpl, payload) {
  if (typeof tpl !== 'string') return '';
  return tpl.replace(/\{\{\s*([^}]+?)\s*\}\}/g, (_, path) => {
    const v = resolve(payload, path.trim());
    // só primitivos viram texto; objeto/array/undefined/null → vazio
    return (v == null || typeof v === 'object') ? '' : String(v);
  });
}

module.exports = { render, resolve };
```

- [ ] **Step 4: Rodar → passa.** `cd relay && node --test test/template.test.js` → 5/5.
- [ ] **Step 5: Commit** `git add relay/src/template.js relay/test/template.test.js && git commit -m "feat(relay): motor de template {{dot.path}} pro mapeamento"`

---

### Task 2: `db.js` — tabela `profiles` + operações + migração

**Files:** Modify `relay/src/db.js`; `relay/test/db.test.js` (novos casos).

**Interfaces (adicionar ao objeto de `openDB`):**
- `createProfile({profileId, deviceId, publishTokenHash, name, now})`
- `findProfileByPublishTokenHash(hash)` → row `{profile_id, device_id, publish_token_h, name, mapping, icon, last_payload, created_at}`
- `listProfiles(deviceId)` → rows
- `getProfile({profileId, deviceId})` → row | undefined
- `updateProfile({profileId, deviceId, name, mapping, icon})` — só troca os campos passados (não-undefined)
- `deleteProfile({profileId, deviceId})`
- `countProfiles(deviceId)` → number
- `storeLastPayload({profileId, payload, now})` — payload string (já capado por quem chama)
- `rotateProfileToken({profileId, deviceId, publishTokenHash})`
- migração: `openDB` chama `migrateProfiles()` — pra cada `devices.publish_token_h` ainda sem perfil, cria um perfil "Padrão".

- [ ] **Step 1: Testes que falham — adicionar a `relay/test/db.test.js`**

```js
test('perfis: create, lookup por token, list, get, update, delete', () => {
  const db = openDB(':memory:');
  db.createDevice({ deviceId: 'd1', deviceSecretHash: 'sh', publishTokenHash: 'ph-dev', now: 1 });
  db.createProfile({ profileId: 'p1', deviceId: 'd1', publishTokenHash: 'ph1', name: 'GitHub', now: 1 });
  assert.strictEqual(db.findProfileByPublishTokenHash('ph1').profile_id, 'p1');
  assert.strictEqual(db.listProfiles('d1').some(p => p.profile_id === 'p1'), true);
  assert.strictEqual(db.getProfile({ profileId: 'p1', deviceId: 'd1' }).name, 'GitHub');
  db.updateProfile({ profileId: 'p1', deviceId: 'd1', mapping: '{"title":"{{x}}"}', icon: '🚀' });
  const g = db.getProfile({ profileId: 'p1', deviceId: 'd1' });
  assert.strictEqual(g.mapping, '{"title":"{{x}}"}');
  assert.strictEqual(g.icon, '🚀');
  assert.strictEqual(g.name, 'GitHub'); // update parcial não apagou o nome
  db.deleteProfile({ profileId: 'p1', deviceId: 'd1' });
  assert.strictEqual(db.getProfile({ profileId: 'p1', deviceId: 'd1' }), undefined);
  db.close();
});

test('update/get/delete são escopados por device (não vaza entre devices)', () => {
  const db = openDB(':memory:');
  db.createDevice({ deviceId: 'd1', deviceSecretHash: 'a', publishTokenHash: 'x', now: 1 });
  db.createProfile({ profileId: 'p1', deviceId: 'd1', publishTokenHash: 'ph1', name: 'N', now: 1 });
  assert.strictEqual(db.getProfile({ profileId: 'p1', deviceId: 'OUTRO' }), undefined);
  db.updateProfile({ profileId: 'p1', deviceId: 'OUTRO', name: 'hack' });
  assert.strictEqual(db.getProfile({ profileId: 'p1', deviceId: 'd1' }).name, 'N');
  db.close();
});

test('storeLastPayload guarda o último', () => {
  const db = openDB(':memory:');
  db.createDevice({ deviceId: 'd1', deviceSecretHash: 'a', publishTokenHash: 'x', now: 1 });
  db.createProfile({ profileId: 'p1', deviceId: 'd1', publishTokenHash: 'ph1', name: 'N', now: 1 });
  db.storeLastPayload({ profileId: 'p1', payload: '{"a":1}', now: 2 });
  db.storeLastPayload({ profileId: 'p1', payload: '{"a":2}', now: 3 });
  assert.strictEqual(db.findProfileByPublishTokenHash('ph1').last_payload, '{"a":2}');
  db.close();
});

test('migração: device com publish_token_h vira perfil Padrão', () => {
  const db = openDB(':memory:');
  db.createDevice({ deviceId: 'd1', deviceSecretHash: 'a', publishTokenHash: 'phX', now: 1 });
  db.migrateProfiles({ now: 5 });
  const prof = db.findProfileByPublishTokenHash('phX');
  assert.ok(prof, 'perfil padrão criado com o token do device');
  assert.strictEqual(prof.mapping, null);       // captura-only
  assert.strictEqual(prof.device_id, 'd1');
  // idempotente: rodar de novo não duplica
  db.migrateProfiles({ now: 6 });
  assert.strictEqual(db.listProfiles('d1').length, 1);
  db.close();
});
```

- [ ] **Step 2: Rodar → falha.** `cd relay && node --test test/db.test.js`

- [ ] **Step 3: Implementar em `relay/src/db.js`** — no `exec` do schema, adicionar a tabela; nos `stmts`, os prepared; no objeto retornado, os métodos; e chamar `migrateProfiles` no fim do `openDB`.

Schema (adicionar ao `db.exec(...)`):
```sql
    CREATE TABLE IF NOT EXISTS profiles (
      profile_id      TEXT PRIMARY KEY,
      device_id       TEXT NOT NULL,
      publish_token_h TEXT NOT NULL,
      name            TEXT NOT NULL,
      mapping         TEXT,
      icon            TEXT,
      last_payload    TEXT,
      created_at      INTEGER NOT NULL
    );
    CREATE INDEX IF NOT EXISTS idx_prof_pub ON profiles(publish_token_h);
    CREATE INDEX IF NOT EXISTS idx_prof_dev ON profiles(device_id);
```

Statements (adicionar ao objeto `stmts`):
```js
    profCreate: db.prepare(`INSERT INTO profiles (profile_id, device_id, publish_token_h, name, created_at)
                            VALUES (@profileId, @deviceId, @publishTokenHash, @name, @now)`),
    profByPub: db.prepare('SELECT * FROM profiles WHERE publish_token_h = ?'),
    profList: db.prepare('SELECT * FROM profiles WHERE device_id = ? ORDER BY created_at ASC'),
    profGet: db.prepare('SELECT * FROM profiles WHERE profile_id = ? AND device_id = ?'),
    profDelete: db.prepare('DELETE FROM profiles WHERE profile_id = ? AND device_id = ?'),
    profCount: db.prepare('SELECT COUNT(*) n FROM profiles WHERE device_id = ?'),
    profPayload: db.prepare('UPDATE profiles SET last_payload = @payload WHERE profile_id = @profileId'),
    profRotate: db.prepare('UPDATE profiles SET publish_token_h = @publishTokenHash WHERE profile_id = @profileId AND device_id = @deviceId'),
    // migração: devices cujo token ainda não tem perfil
    migSelect: db.prepare(`SELECT device_id, publish_token_h FROM devices d
                           WHERE NOT EXISTS (SELECT 1 FROM profiles p WHERE p.publish_token_h = d.publish_token_h)`),
```

Métodos (adicionar ao objeto retornado):
```js
    createProfile: (a) => stmts.profCreate.run(a),
    findProfileByPublishTokenHash: (h) => stmts.profByPub.get(h),
    listProfiles: (deviceId) => stmts.profList.all(deviceId),
    getProfile: ({ profileId, deviceId }) => stmts.profGet.get(profileId, deviceId),
    deleteProfile: ({ profileId, deviceId }) => stmts.profDelete.run(profileId, deviceId),
    countProfiles: (deviceId) => stmts.profCount.get(deviceId).n,
    storeLastPayload: ({ profileId, payload }) => stmts.profPayload.run({ profileId, payload }),
    rotateProfileToken: (a) => stmts.profRotate.run(a),
    updateProfile: ({ profileId, deviceId, name, mapping, icon }) => {
      // update parcial: monta SET só dos campos passados (não-undefined)
      const sets = [], vals = { profileId, deviceId };
      if (name !== undefined)    { sets.push('name = @name');       vals.name = name; }
      if (mapping !== undefined) { sets.push('mapping = @mapping'); vals.mapping = mapping; }
      if (icon !== undefined)    { sets.push('icon = @icon');       vals.icon = icon; }
      if (!sets.length) return;
      db.prepare(`UPDATE profiles SET ${sets.join(', ')} WHERE profile_id = @profileId AND device_id = @deviceId`).run(vals);
    },
    migrateProfiles: ({ now }) => {
      const tx = db.transaction(() => {
        for (const d of stmts.migSelect.all()) {
          stmts.profCreate.run({ profileId: 'mig-' + d.publish_token_h.slice(0, 16),
            deviceId: d.device_id, publishTokenHash: d.publish_token_h, name: 'Padrão', now });
        }
      });
      tx();
    },
```

E no fim do `openDB`, antes do `return`, rodar a migração uma vez:
```js
  // migra tokens antigos (device→perfil Padrão) na subida; idempotente
  { const migSelect = db.prepare(`SELECT device_id, publish_token_h FROM devices d WHERE NOT EXISTS (SELECT 1 FROM profiles p WHERE p.publish_token_h = d.publish_token_h)`);
    const migIns = stmts.profCreate;
    const tx = db.transaction(() => { for (const d of migSelect.all()) migIns.run({ profileId: 'mig-'+d.publish_token_h.slice(0,16), deviceId: d.device_id, publishTokenHash: d.publish_token_h, name: 'Padrão', now: Date.now() }); });
    tx(); }
```
> ponytail: a migração inline no `openDB` + o método `migrateProfiles` fazem a mesma coisa (o método existe pro teste chamar explícito com `now` fixo). Mantenha os dois; a duplicação é 3 linhas e some se um dia o teste passar a usar o método interno.

- [ ] **Step 4: Rodar → passa.** `cd relay && node --test` (toda a suíte verde).
- [ ] **Step 5: Commit** `git add relay/src/db.js relay/test/db.test.js && git commit -m "feat(relay): tabela profiles + CRUD + migração do token único"`

---

### Task 3: `server.js` — API de perfis + register cria perfil padrão

**Files:** Modify `relay/src/server.js`; `relay/test/server.test.js` (novos casos).

**Interfaces (rotas novas, auth `Authorization: Bearer <deviceSecret>` exceto onde dito):**
- `POST /register` (sem auth) — agora **também cria um perfil "Padrão"** com o publishToken retornado.
- `POST /profiles {name}` → `{profileId, publishToken}` (token só aqui).
- `GET /profiles` → `[{profileId, name, hasMapping, icon}]`.
- `GET /profiles/<id>` → `{profileId, name, mapping, icon, lastPayload, link}`.
- `PUT /profiles/<id> {name?, mapping?, icon?}` → `{ok:true}`.
- `DELETE /profiles/<id>` → `{ok:true}`.
- `POST /profiles/<id>/rotate` → `{publishToken}`.

Helper de auth (device pelo deviceSecret do header):
```js
function authDevice(req, db) {
  const auth = req.headers['authorization'] || '';
  const secret = auth.startsWith('Bearer ') ? auth.slice(7) : '';
  return secret ? db.findBySecretHash(sha256(secret)) : undefined;
}
```

- [ ] **Step 1: Testes que falham — `relay/test/server.test.js` (novos casos)**

```js
test('register cria device + perfil Padrão; /profiles lista ele', async () => {
  const { srv, base } = await boot();
  const reg = (await post(base, '/register')).json;
  const list = await fetch(base + '/profiles', { headers: { Authorization: `Bearer ${reg.deviceSecret}` } }).then(r => r.json());
  assert.strictEqual(list.length, 1);
  assert.strictEqual(list[0].name, 'Padrão');
  assert.strictEqual(list[0].hasMapping, false);
  await new Promise(r => srv.stop(r));
});

test('CRUD de perfil: cria, atualiza mapping, pega, deleta', async () => {
  const { srv, base } = await boot();
  const reg = (await post(base, '/register')).json;
  const H = { Authorization: `Bearer ${reg.deviceSecret}`, 'Content-Type': 'application/json' };
  const created = await fetch(base + '/profiles', { method: 'POST', headers: H, body: JSON.stringify({ name: 'GitHub' }) }).then(r => r.json());
  assert.ok(created.profileId && created.publishToken);
  await fetch(base + `/profiles/${created.profileId}`, { method: 'PUT', headers: H, body: JSON.stringify({ mapping: '{"title":"{{repo.name}}"}', icon: '🚀' }) });
  const got = await fetch(base + `/profiles/${created.profileId}`, { headers: H }).then(r => r.json());
  assert.strictEqual(got.mapping, '{"title":"{{repo.name}}"}');
  assert.strictEqual(got.icon, '🚀');
  assert.ok(got.link.includes(created.publishToken));
  const del = await fetch(base + `/profiles/${created.profileId}`, { method: 'DELETE', headers: H });
  assert.strictEqual(del.status, 200);
  await new Promise(r => srv.stop(r));
});

test('API de perfis exige deviceSecret válido', async () => {
  const { srv, base } = await boot();
  const r = await fetch(base + '/profiles', { headers: { Authorization: 'Bearer errado' } });
  assert.strictEqual(r.status, 401);
  await new Promise(r2 => srv.stop(r2));
});
```

- [ ] **Step 2: Rodar → falha.** `cd relay && node --test test/server.test.js`

- [ ] **Step 3: Implementar em `relay/src/server.js`**

No `POST /register`, após `db.createDevice(...)`, criar o perfil padrão:
```js
        const profileId = genToken();
        db.createProfile({ profileId, deviceId, publishTokenHash: sha256(publishToken), name: 'Padrão', now: Date.now() });
```

Adicionar os handlers de `/profiles` (antes do `404` final). Use `authDevice`, JSON helpers e `readBody` já existentes. `link = https://push.appzoi.com.br/w/<publishToken>` (base fixa). Esboço:
```js
      if (path === '/profiles' && req.method === 'POST') {
        const dev = authDevice(req, db); if (!dev) return json(res, 401, { ok: false });
        if (db.countProfiles(dev.device_id) >= 50) return json(res, 429, { ok: false, error: 'limite de perfis' });
        const body = JSON.parse(await readBody(req) || '{}');
        const name = (body.name || 'Sem nome').toString().slice(0, 60);
        const profileId = genToken(), publishToken = genToken();
        db.createProfile({ profileId, deviceId: dev.device_id, publishTokenHash: sha256(publishToken), name, now: Date.now() });
        return json(res, 200, { profileId, publishToken });
      }
      if (path === '/profiles' && req.method === 'GET') {
        const dev = authDevice(req, db); if (!dev) return json(res, 401, { ok: false });
        return json(res, 200, db.listProfiles(dev.device_id).map(p => ({ profileId: p.profile_id, name: p.name, hasMapping: !!p.mapping, icon: p.icon })));
      }
      if (path.startsWith('/profiles/')) {
        const dev = authDevice(req, db); if (!dev) return json(res, 401, { ok: false });
        const rest = path.slice('/profiles/'.length);
        const [id, action] = rest.split('/');
        if (action === 'rotate' && req.method === 'POST') {
          if (!db.getProfile({ profileId: id, deviceId: dev.device_id })) return json(res, 404, { ok: false });
          const publishToken = genToken();
          db.rotateProfileToken({ profileId: id, deviceId: dev.device_id, publishTokenHash: sha256(publishToken) });
          return json(res, 200, { publishToken });
        }
        const prof = db.getProfile({ profileId: id, deviceId: dev.device_id });
        if (!prof) return json(res, 404, { ok: false });
        if (req.method === 'GET') return json(res, 200, { profileId: prof.profile_id, name: prof.name, mapping: prof.mapping, icon: prof.icon, lastPayload: prof.last_payload, link: `https://push.appzoi.com.br/w/${'<oculto>'}` });
        if (req.method === 'PUT') {
          const b = JSON.parse(await readBody(req) || '{}');
          db.updateProfile({ profileId: id, deviceId: dev.device_id, name: b.name, mapping: b.mapping, icon: b.icon });
          return json(res, 200, { ok: true });
        }
        if (req.method === 'DELETE') { db.deleteProfile({ profileId: id, deviceId: dev.device_id }); return json(res, 200, { ok: true }); }
      }
```
> ⚠️ **`link` no GET /profiles/<id>:** o relay guarda só o **hash** do publishToken, então não sabe o token em claro pra montar o link. Decisão: o **app** guarda o publishToken (do POST /profiles / rotate) no Keychain e monta o link localmente; o GET não devolve link (remova o campo `link` do GET, ou devolva `null`). Ajuste o teste `assert(got.link...)` pra checar via o token do create, não via o GET. (Corrija o teste do Step 1 pra não depender de `got.link`.)

- [ ] **Step 4: Rodar → passa** (ajuste o teste do `link` conforme a nota). `cd relay && node --test`
- [ ] **Step 5: Commit** `git add relay/src/server.js relay/test/server.test.js && git commit -m "feat(relay): API de perfis (CRUD+rotate) + register cria perfil Padrão"`

---

### Task 4: `server.js` — ingress `/w/<token>` por perfil (captura + mapa) + push com iconEmoji

**Files:** Modify `relay/src/server.js`; `relay/test/server.test.js` (novos casos).

**Comportamento:** `/w/<publishToken>` resolve o **perfil** (não mais o device direto); grava `last_payload` (cap 16KB); se `mapping` NULL → `202 {delivered:"captured"}`; senão renderiza os campos, sanitiza, resolve ícone, e push/queue pro device do perfil.

- [ ] **Step 1: Testes que falham — `relay/test/server.test.js`**

```js
const { render } = require('../src/template'); // usado indiretamente pelo server

test('perfil sem mapping: captura-only (não empurra), guarda payload', async () => {
  const { srv, base } = await boot();
  const reg = (await post(base, '/register')).json;   // perfil Padrão sem mapping, token = reg.publishToken
  const r = await post(base, `/w/${reg.publishToken}`, { headers: { 'Content-Type': 'application/json' }, body: '{"repo":{"name":"knobler"}}' });
  assert.strictEqual(r.json.delivered, 'captured');
  // o payload ficou guardado (via API de perfis)
  const list = await fetch(base + '/profiles', { headers: { Authorization: `Bearer ${reg.deviceSecret}` } }).then(r => r.json());
  const got = await fetch(base + `/profiles/${list[0].profileId}`, { headers: { Authorization: `Bearer ${reg.deviceSecret}` } }).then(r => r.json());
  assert.strictEqual(JSON.parse(got.lastPayload).repo.name, 'knobler');
  await new Promise(r => srv.stop(r));
});

test('perfil com mapping: renderiza e entrega ao vivo', async () => {
  const { srv, port, base } = await boot();
  const reg = (await post(base, '/register')).json;
  const H = { Authorization: `Bearer ${reg.deviceSecret}`, 'Content-Type': 'application/json' };
  const list = await fetch(base + '/profiles', { headers: H }).then(r => r.json());
  const pid = list[0].profileId;
  await fetch(base + `/profiles/${pid}`, { method: 'PUT', headers: H, body: JSON.stringify({ mapping: JSON.stringify({ title: 'Push em {{repo.name}}', body: '{{commits.0.msg}}', sound: true }), icon: '🚀' }) });

  const ws = new WebSocket(`ws://127.0.0.1:${port}/ws`, { headers: { Authorization: `Bearer ${reg.deviceSecret}` } });
  const msg = new Promise(r => ws.on('message', d => r(JSON.parse(d.toString()))));
  await new Promise((r, e) => { ws.on('open', r); ws.on('error', e); });
  const pub = await post(base, `/w/${reg.publishToken}`, { headers: { 'Content-Type': 'application/json' }, body: '{"repo":{"name":"knobler"},"commits":[{"msg":"fix bug"}]}' });
  assert.strictEqual(pub.json.delivered, 'push');
  const m = await msg;
  assert.strictEqual(m.title, 'Push em knobler');
  assert.strictEqual(m.body, 'fix bug');
  assert.strictEqual(m.sound, true);
  assert.strictEqual(m.iconEmoji, '🚀');   // emoji vira iconEmoji, não iconURL
  ws.close();
  await new Promise(r => srv.stop(r));
});
```

- [ ] **Step 2: Rodar → falha.** `cd relay && node --test test/server.test.js`

- [ ] **Step 3: Implementar** — no topo do server, `const { render } = require('./template');`. Reescrever o handler `POST /w/`:
```js
      if (req.method === 'POST' && path.startsWith('/w/')) {
        const publishToken = decodeURIComponent(path.slice('/w/'.length));
        const prof = db.findProfileByPublishTokenHash(sha256(publishToken));
        if (!prof) return json(res, 404, { ok: false, error: 'token desconhecido' });
        const gate = rateLimiter.allow(prof.profile_id);
        if (!gate.ok) { res.setHeader('Retry-After', String(gate.retryAfter)); return json(res, 429, { ok: false, error: 'rate limit' }); }

        const rawBody = await readBody(req, 16 * 1024);
        let payload; try { payload = JSON.parse(rawBody || '{}'); } catch { return json(res, 400, { ok: false, error: 'JSON inválido' }); }
        db.storeLastPayload({ profileId: prof.profile_id, payload: rawBody.slice(0, 16 * 1024) });

        if (!prof.mapping) return json(res, 202, { ok: true, delivered: 'captured' });

        const m = JSON.parse(prof.mapping);
        const title = clean(render(m.title || '', payload), 200) || prof.name;   // fallback: nome do perfil
        const iconRendered = m.iconTemplate ? render(m.iconTemplate, payload) : (prof.icon || '');
        const isURL = /^https?:\/\//i.test(iconRendered);
        const msg = { type: 'notify', title,
          body: clean(render(m.body || '', payload), 1000),
          iconURL: isURL ? safeURL(iconRendered, ['https:']) : null,
          iconEmoji: !isURL && iconRendered ? iconRendered.slice(0, 8) : null,
          url: safeURL(render(m.url || '', payload), ['http:', 'https:']),
          sound: !!m.sound,
          id: render(m.id || '', payload) || null,
          ts: Date.now() };

        if (hub.send(prof.device_id, msg)) return json(res, 202, { ok: true, delivered: 'push' });
        db.enqueue({ deviceId: prof.device_id, payload: msg, dedupeId: msg.id, now: Date.now() });
        return json(res, 202, { ok: true, delivered: 'queued' });
      }
```
Precisa importar `clean`/`safeURL` do `normalize.js` (exporte-os lá se ainda não forem exportados). Remova o uso antigo de `normalizePayload` no ingress.

> ponytail: `iconEmoji` capado em 8 chars (1 emoji ZWJ cabe). Rate limit agora chaveado por `profile_id` (era device) — coerente com "1 perfil = 1 link".

- [ ] **Step 4: Rodar → passa.** `cd relay && node --test` (suíte inteira verde).
- [ ] **Step 5: Commit** `git add relay/src/server.js relay/src/normalize.js relay/test/server.test.js && git commit -m "feat(relay): ingress por perfil (captura-only / mapeia) + iconEmoji no push"`

---

### Task 5: Deploy na VPS + fumaça

- [ ] **Step 1: rsync + restart**
```bash
cd /Users/luccassilveira/Desktop/knobler
rsync -az --delete --exclude node_modules --exclude '*.db' --exclude '*.db-wal' --exclude '*.db-shm' relay/ root@147.79.87.179:/opt/knobler-relay/
ssh root@147.79.87.179 'cd /opt/knobler-relay && node --test 2>&1 | grep -E "# (tests|pass|fail)"; pm2 restart knobler-relay && sleep 1 && curl -s 127.0.0.1:8477/health'
```
Expected: suíte verde no Node 18 da VPS; `/health` `{"ok":true,...}`. A migração roda no `openDB` (o relay.db existente ganha os perfis Padrão dos devices atuais).

- [ ] **Step 2: fumaça E2E remota** — registrar, criar perfil, mapear via `curl`, publicar payload cru, ver o card renderizado (do Mac, contra `https://push.appzoi.com.br`). Reusar o script de E2E do Plano 1 adaptado: create profile → PUT mapping → POST payload nativo → WS recebe `{title renderizado, iconEmoji}`.

- [ ] **Step 3: Commit** (nada novo de código; se ajustar README, commitar).

---

## Self-Review

- Cobertura da spec: template `{{}}` (T1), profiles+migração (T2), API CRUD+register (T3), ingress captura/mapa+iconEmoji (T4), deploy (T5). ✅
- Placeholders: nenhum; a nota do `link` no GET (T3) é decisão explícita (app monta o link).
- Consistência: rate limit passa de device→profile (coerente); `clean`/`safeURL` reusados; `iconURL`/`iconEmoji` batem com o render do card (Plano B).
- Risco: a migração no `openDB` roda em produção sobre o `relay.db` real — idempotente (só cria perfil pra token sem perfil), testada. Fora disso, o app antigo (que espera `/w/` no schema direto) **para de entregar** até ter um mapping — é a decisão "mapeamento obrigatório"; o perfil Padrão fica captura-only. Aceito.
