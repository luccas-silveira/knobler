const { test } = require('node:test');
const assert = require('node:assert');
const { genToken, sha256 } = require('../src/tokens');

test('genToken gera 43 chars base64url e é único', () => {
  const a = genToken();
  const b = genToken();
  assert.match(a, /^[A-Za-z0-9_-]{43}$/, 'formato base64url sem padding');
  assert.notStrictEqual(a, b, 'dois tokens não colidem');
});

test('sha256 é hex de 64 chars e determinístico', () => {
  const h1 = sha256('abc');
  const h2 = sha256('abc');
  assert.match(h1, /^[0-9a-f]{64}$/);
  assert.strictEqual(h1, h2);
  assert.notStrictEqual(sha256('abc'), sha256('abd'));
});
