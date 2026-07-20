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
