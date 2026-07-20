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
