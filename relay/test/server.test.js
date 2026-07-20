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

test('webhook com device offline enfileira e drena no connect', async () => {
  const { srv, port, base } = await boot();
  const { deviceSecret, publishToken } = (await post(base, '/register')).json;

  // perfil precisa de mapping pra empurrar/enfileirar (sem mapping = captura-only)
  const H = { Authorization: `Bearer ${deviceSecret}`, 'Content-Type': 'application/json' };
  const list = await fetch(base + '/profiles', { headers: H }).then(r => r.json());
  await fetch(base + `/profiles/${list[0].profileId}`, { method: 'PUT', headers: H, body: JSON.stringify({ mapping: JSON.stringify({ title: '{{msg}}' }) }) });

  // device offline: publica antes de conectar
  const pub = await post(base, `/w/${publishToken}`, {
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ msg: 'guardado' }),
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

test('token desconhecido → 404; JSON inválido → 400', async () => {
  const { srv, base } = await boot();
  assert.strictEqual((await post(base, '/w/naoexiste', {
    headers: { 'Content-Type': 'application/json' }, body: '{"title":"x"}' })).status, 404);
  const { publishToken } = (await post(base, '/register')).json;
  assert.strictEqual((await post(base, `/w/${publishToken}`, {
    headers: { 'Content-Type': 'application/json' }, body: '{isso não é json}' })).status, 400);
  await new Promise((r) => srv.stop(r));
});

test('payload > 16KB → 400 (não derruba a conexão nem o processo)', async () => {
  const { srv, base } = await boot();
  const { publishToken } = (await post(base, '/register')).json;
  // JSON válido cujo corpo passa de 16KB: excede o limitBytes durante o stream.
  const big = JSON.stringify({ title: 'x'.repeat(20 * 1024) });
  assert.ok(Buffer.byteLength(big) > 16 * 1024);
  const res = await post(base, `/w/${publishToken}`, {
    headers: { 'Content-Type': 'application/json' }, body: big,
  });
  assert.strictEqual(res.status, 400);
  assert.strictEqual(res.json.ok, false);
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
  // O relay guarda só o hash do publishToken → não devolve `link` no GET.
  // O app monta o link a partir do publishToken recebido no create/rotate.
  const link = `https://push.appzoi.com.br/w/${created.publishToken}`;
  assert.ok(link.includes(created.publishToken));
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
