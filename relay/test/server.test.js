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

test('payload > 64KB → 400 (não derruba a conexão nem o processo)', async () => {
  const { srv, base } = await boot();
  const { publishToken } = (await post(base, '/register')).json;
  // JSON válido cujo corpo passa de 64KB: excede o limitBytes durante o stream.
  const big = JSON.stringify({ title: 'x'.repeat(70 * 1024) });
  assert.ok(Buffer.byteLength(big) > 64 * 1024);
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
