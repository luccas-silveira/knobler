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

// Banco realmente legado: a tabela de perfis ainda não existe.
test('migração legado roda na abertura, uma vez, mesmo após rotação e exclusão', () => {
  const { mkdtempSync, rmSync } = require('node:fs');
  const { tmpdir } = require('node:os');
  const { join } = require('node:path');
  const Database = require('better-sqlite3');
  const dir = mkdtempSync(join(tmpdir(), 'knobler-db-'));
  let db;
  try {
    const path = join(dir, 'relay.db');
    const legacy = new Database(path);
    legacy.exec(`CREATE TABLE devices (device_id TEXT PRIMARY KEY, device_secret_h TEXT NOT NULL,
      publish_token_h TEXT NOT NULL, created_at INTEGER NOT NULL, last_seen_at INTEGER);
      INSERT INTO devices VALUES ('d1', 'sh', 'ph', 1, NULL)`);
    legacy.close();
    db = openDB(path);
    const profile = db.findProfileByPublishTokenHash('ph');
    assert.strictEqual(profile.name, 'Padrão');
    assert.strictEqual(profile.mapping, null);
    db.rotateProfileToken({ profileId: profile.profile_id, deviceId: 'd1', publishTokenHash: 'new' });
    db.close(); db = openDB(path);
    assert.strictEqual(db.findProfileByPublishTokenHash('ph'), undefined, 'token revogado ressuscitou');
    assert.strictEqual(db.listProfiles('d1').length, 1);
    db.deleteProfile({ profileId: profile.profile_id, deviceId: 'd1' });
    for (let i = 0; i < 2; i++) {
      db.close(); db = openDB(path);
      assert.deepStrictEqual(db.listProfiles('d1'), [], 'perfil excluído ressuscitou');
    }
  } finally {
    db?.close();
    rmSync(dir, { recursive: true, force: true });
  }
});
