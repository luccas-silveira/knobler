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
  };

  // migra tokens antigos (device→perfil Padrão) na subida; idempotente
  // ponytail: duplica migrateProfiles de propósito (o método existe pro teste chamar com `now` fixo)
  { const migSelect = db.prepare(`SELECT device_id, publish_token_h FROM devices d WHERE NOT EXISTS (SELECT 1 FROM profiles p WHERE p.publish_token_h = d.publish_token_h)`);
    const migIns = stmts.profCreate;
    const tx = db.transaction(() => { for (const d of migSelect.all()) migIns.run({ profileId: 'mig-'+d.publish_token_h.slice(0,16), deviceId: d.device_id, publishTokenHash: d.publish_token_h, name: 'Padrão', now: Date.now() }); });
    tx(); }

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

    close: () => db.close(),
  };
}

module.exports = { openDB, QUEUE_CAP, QUEUE_TTL_MS };
