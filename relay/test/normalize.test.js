const { test } = require('node:test');
const assert = require('node:assert');
const { normalizePayload, ValidationError } = require('../src/normalize');

test('JSON completo é normalizado', () => {
  const out = normalizePayload({
    contentType: 'application/json',
    rawBody: JSON.stringify({
      title: 'Deploy ok', body: 'produção', icon: 'https://x/i.png',
      url: 'https://x/deploy/1', sound: true, id: 'dep-1',
    }),
    query: {},
  });
  assert.deepStrictEqual(out, {
    title: 'Deploy ok', body: 'produção', iconURL: 'https://x/i.png',
    url: 'https://x/deploy/1', sound: true, id: 'dep-1',
  });
});

test('form-encoded funciona', () => {
  const out = normalizePayload({
    contentType: 'application/x-www-form-urlencoded',
    rawBody: 'title=Oi&body=Tudo+bem',
    query: {},
  });
  assert.strictEqual(out.title, 'Oi');
  assert.strictEqual(out.body, 'Tudo bem');
});

test('query string funciona quando não há corpo', () => {
  const out = normalizePayload({ contentType: '', rawBody: '',
    query: { title: 'Q', body: 'via query' } });
  assert.strictEqual(out.title, 'Q');
  assert.strictEqual(out.body, 'via query');
});

test('sem title → ValidationError 400', () => {
  assert.throws(
    () => normalizePayload({ contentType: 'application/json', rawBody: '{"body":"x"}', query: {} }),
    (e) => e instanceof ValidationError && e.statusCode === 400,
  );
});

test('icon/url com esquema inválido viram null; title/body são truncados e limpos', () => {
  const out = normalizePayload({
    contentType: 'application/json',
    rawBody: JSON.stringify({
      title: '\x01' + 'a'.repeat(300), body: 'b'.repeat(2000),
      icon: 'ftp://x/i.png', url: 'file:///etc/passwd',
    }),
    query: {},
  });
  assert.strictEqual(out.title.length, 200, 'title truncado a 200');
  assert.ok(!out.title.includes('\x01'), 'caractere de controle removido');
  assert.strictEqual(out.body.length, 1000, 'body truncado a 1000');
  assert.strictEqual(out.iconURL, null, 'icon não-https → null');
  assert.strictEqual(out.url, null, 'url não-http(s) → null');
});

test('sound aceita "true"/"1" de form/query como booleano', () => {
  const out = normalizePayload({ contentType: '', rawBody: '', query: { title: 'x', sound: 'true' } });
  assert.strictEqual(out.sound, true);
});
