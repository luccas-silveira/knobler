// Monta o servidor HTTP + WebSocket e fia as peças.
const http = require('http');
const { WebSocketServer } = require('ws');
const { genToken, sha256 } = require('./tokens');
const { ValidationError, clean, safeURL } = require('./normalize');
const { render } = require('./template');

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

/** Autentica o device pelo deviceSecret do header Authorization: Bearer. */
function authDevice(req, db) {
  const auth = req.headers['authorization'] || '';
  const secret = auth.startsWith('Bearer ') ? auth.slice(7) : '';
  return secret ? db.findBySecretHash(sha256(secret)) : undefined;
}

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
        const now = Date.now();
        db.createDevice({
          deviceId,
          deviceSecretHash: sha256(deviceSecret),
          publishTokenHash: sha256(publishToken),
          now,
        });
        // cria o perfil "Padrão" reusando o publishToken do device
        const profileId = genToken();
        db.createProfile({ profileId, deviceId, publishTokenHash: sha256(publishToken), name: 'Padrão', now });
        return json(res, 200, { deviceId, deviceSecret, publishToken });
      }

      if (req.method === 'POST' && path === '/rotate') {
        const auth = req.headers['authorization'] || '';
        const secret = auth.startsWith('Bearer ') ? auth.slice(7) : '';
        const dev = secret && db.findBySecretHash(sha256(secret));
        if (!dev) return json(res, 401, { ok: false, error: 'deviceSecret inválido' });
        const oldHash = dev.publish_token_h;                 // guarda o hash antigo antes de rotacionar
        const publishToken = genToken();
        const newHash = sha256(publishToken);
        db.rotatePublishToken({ deviceId: dev.device_id, publishTokenHash: newHash });
        // o /w/ resolve o perfil por publish_token_h → rotaciona também o perfil Padrão
        // (o que ainda carrega o hash antigo), senão o link novo dá 404 e o antigo não morre.
        const prof = db.findProfileByPublishTokenHash(oldHash);
        if (prof && prof.device_id === dev.device_id) {
          db.rotateProfileToken({ profileId: prof.profile_id, deviceId: dev.device_id, publishTokenHash: newHash });
        }
        return json(res, 200, { ok: true, publishToken });
      }

      if (req.method === 'POST' && path.startsWith('/w/')) {
        const publishToken = decodeURIComponent(path.slice('/w/'.length));
        const prof = db.findProfileByPublishTokenHash(sha256(publishToken));
        if (!prof) return json(res, 404, { ok: false, error: 'token desconhecido' });

        // rate limit chaveado por perfil (1 perfil = 1 link)
        const gate = rateLimiter.allow(prof.profile_id);
        if (!gate.ok) {
          res.setHeader('Retry-After', String(gate.retryAfter));
          return json(res, 429, { ok: false, error: 'rate limit' });
        }

        const rawBody = await readBody(req, 16 * 1024);
        let payload; try { payload = JSON.parse(rawBody || '{}'); } catch { return json(res, 400, { ok: false, error: 'JSON inválido' }); }
        db.storeLastPayload({ profileId: prof.profile_id, payload: rawBody.slice(0, 16 * 1024) });

        // sem mapping = captura-only: guarda o payload e não empurra nada
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

      // ---- API de perfis (auth por deviceSecret) ----
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
        // GET não devolve `link`: o relay só guarda o hash do publishToken.
        // O app monta o link a partir do token recebido no create/rotate.
        if (req.method === 'GET') return json(res, 200, { profileId: prof.profile_id, name: prof.name, mapping: prof.mapping, icon: prof.icon, lastPayload: prof.last_payload, link: null });
        if (req.method === 'PUT') {
          const b = JSON.parse(await readBody(req) || '{}');
          // valida o mapping antes de salvar: mapping malformado no banco = 500 em todo /w/ do perfil
          if (b.mapping !== undefined && b.mapping !== null) {
            try { JSON.parse(b.mapping); } catch { return json(res, 400, { ok: false, error: 'mapping inválido' }); }
          }
          db.updateProfile({ profileId: id, deviceId: dev.device_id, name: b.name, mapping: b.mapping, icon: b.icon });
          return json(res, 200, { ok: true });
        }
        if (req.method === 'DELETE') { db.deleteProfile({ profileId: id, deviceId: dev.device_id }); return json(res, 200, { ok: true }); }
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
