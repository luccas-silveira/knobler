const { test } = require('node:test');
const assert = require('node:assert');
const { render, resolve } = require('../src/template');

const p = { title: 'Deploy', repo: { name: 'knobler' }, commits: [{ msg: 'a' }, { msg: 'b' }], ok: true, n: 3 };

test('resolve dot-path + índice de array', () => {
  assert.strictEqual(resolve(p, 'repo.name'), 'knobler');
  assert.strictEqual(resolve(p, 'commits.1.msg'), 'b');
  assert.strictEqual(resolve(p, 'nao.existe'), undefined);
});

test('render mistura texto livre + variáveis', () => {
  assert.strictEqual(render('{{repo.name}}: {{commits.0.msg}}', p), 'knobler: a');
  assert.strictEqual(render('Olá {{title}} ({{n}})', p), 'Olá Deploy (3)');
});

test('campo ausente/objeto/array vira vazio; texto puro passa', () => {
  assert.strictEqual(render('x{{nao.existe}}y', p), 'xy');
  assert.strictEqual(render('{{repo}}', p), '');       // objeto → vazio
  assert.strictEqual(render('{{commits}}', p), '');    // array → vazio
  assert.strictEqual(render('sem variavel', p), 'sem variavel');
});

test('bool e número viram string', () => {
  assert.strictEqual(render('{{ok}}/{{n}}', p), 'true/3');
});

test('espaços dentro das chaves são tolerados', () => {
  assert.strictEqual(render('{{  repo.name  }}', p), 'knobler');
});
