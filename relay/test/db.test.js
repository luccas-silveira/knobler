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
