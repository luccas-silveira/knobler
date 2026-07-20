const { test } = require('node:test');
const assert = require('node:assert');
const { createHub } = require('../src/hub');

function fakeWs() {
  return {
    OPEN: 1, readyState: 1, sent: [], pinged: 0, terminated: false, closedWith: null,
    send(s) { this.sent.push(s); },
    ping() { this.pinged++; },
    terminate() { this.terminated = true; this.readyState = 3; },
    close(code, reason) { this.closedWith = { code, reason }; this.readyState = 3; },
  };
}

test('add/isOnline/send serializa e entrega', () => {
  const hub = createHub();
  const ws = fakeWs();
  hub.add('d1', ws);
  assert.strictEqual(hub.isOnline('d1'), true);
  assert.strictEqual(hub.send('d1', { type: 'notify', title: 'oi' }), true);
  assert.deepStrictEqual(JSON.parse(ws.sent[0]), { type: 'notify', title: 'oi' });
  assert.strictEqual(hub.isOnline('outro'), false);
  assert.strictEqual(hub.send('outro', {}), false);
});

test('reconexão do mesmo device fecha o socket antigo', () => {
  const hub = createHub();
  const oldWs = fakeWs(); const newWs = fakeWs();
  hub.add('d1', oldWs);
  hub.add('d1', newWs);
  assert.deepStrictEqual(oldWs.closedWith, { code: 1000, reason: 'replaced' });
  assert.strictEqual(hub.size(), 1);
  assert.strictEqual(hub.send('d1', { x: 1 }), true);
  assert.strictEqual(newWs.sent.length, 1, 'só o novo recebe');
});

test('remove só remove o socket atual', () => {
  const hub = createHub();
  const oldWs = fakeWs(); const newWs = fakeWs();
  hub.add('d1', oldWs);
  hub.add('d1', newWs);            // oldWs foi substituído
  hub.remove('d1', oldWs);         // close tardio do antigo não deve derrubar o novo
  assert.strictEqual(hub.isOnline('d1'), true);
  hub.remove('d1', newWs);
  assert.strictEqual(hub.isOnline('d1'), false);
});

test('heartbeat termina quem não respondeu e faz ping em quem respondeu', () => {
  const hub = createHub();
  const ws = fakeWs();
  hub.add('d1', ws);              // isAlive = true
  hub.heartbeat();               // marca isAlive=false, ping
  assert.strictEqual(ws.pinged, 1);
  assert.strictEqual(ws.terminated, false);
  hub.heartbeat();               // não houve pong → termina
  assert.strictEqual(ws.terminated, true);
  assert.strictEqual(hub.isOnline('d1'), false);
});

test('markAlive impede o terminate no próximo heartbeat', () => {
  const hub = createHub();
  const ws = fakeWs();
  hub.add('d1', ws);
  hub.heartbeat();               // isAlive=false, ping
  hub.markAlive('d1');           // chegou pong
  hub.heartbeat();               // deve pingar de novo, não terminar
  assert.strictEqual(ws.terminated, false);
  assert.strictEqual(ws.pinged, 2);
});
