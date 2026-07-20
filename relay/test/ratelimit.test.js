const { test } = require('node:test');
const assert = require('node:assert');
const { createRateLimiter } = require('../src/ratelimit');

test('burst de 5 passa, o 6º é bloqueado', () => {
  let t = 0;
  const rl = createRateLimiter({ ratePerMin: 20, burst: 5, now: () => t });
  for (let i = 0; i < 5; i++) assert.strictEqual(rl.allow('k').ok, true, `req ${i}`);
  const sixth = rl.allow('k');
  assert.strictEqual(sixth.ok, false);
  assert.ok(sixth.retryAfter >= 1, 'retryAfter em segundos');
});

test('reabastece com o tempo (20/min = 1 token a cada 3s)', () => {
  let t = 0;
  const rl = createRateLimiter({ ratePerMin: 20, burst: 5, now: () => t });
  for (let i = 0; i < 5; i++) rl.allow('k');   // esvazia o balde
  assert.strictEqual(rl.allow('k').ok, false);
  t = 3000;                                     // +3s → +1 token
  assert.strictEqual(rl.allow('k').ok, true);
  assert.strictEqual(rl.allow('k').ok, false);
});

test('chaves diferentes têm baldes independentes', () => {
  let t = 0;
  const rl = createRateLimiter({ ratePerMin: 20, burst: 5, now: () => t });
  for (let i = 0; i < 5; i++) rl.allow('a');
  assert.strictEqual(rl.allow('a').ok, false);
  assert.strictEqual(rl.allow('b').ok, true, 'b não é afetado por a');
});
