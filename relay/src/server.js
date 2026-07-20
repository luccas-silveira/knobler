// Monta o servidor HTTP + WebSocket e fia as peças.
const http = require('http');
const { WebSocketServer } = require('ws');
const { genToken, sha256 } = require('./tokens');
const { normalizePayload, ValidationError } = require('./normalize');

function readBody(req, limitBytes = 64 * 1024) {
  return new Promise((resolve, reject) => {
    let size = 0; const chunks = []; let done = false;
    req.on('data', (c) => {
      if (done) return;
      size += c.length;
      if (size > limitBytes) {
        done = true;
        reject(new ValidationError('payload grande demais')); // NÃO destruir o request: deixa o catch escrever o 400
        return;
      }
      chunks.push(c);
    });
    req.on('end', () => { if (!done) { done = true; resolve(Buffer.concat(chunks).toString('utf8')); } });
    req.on('error', (e) => { if (!done) { done = true; reject(e); } });
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
