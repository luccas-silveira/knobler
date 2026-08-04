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

// ---- filtros (014): um por token, sem encadeamento, falha suave ----

const f = {
  id: '1a2b3c4d-5e6f-7788-99aa-bbccddeeff00',
  date: '1754320000000',
  dateNum: 1754320000000,
  after: '{"ops":[{"insert":"linha um\\n"},{"insert":"linha dois"}]}',
  texto: 'nada a ver',
  obj: { a: 1 },
};

test('semHifens remove os hífens', () => {
  assert.strictEqual(render('https://www.notion.so/{{id | semHifens}}', f),
    'https://www.notion.so/1a2b3c4d5e6f778899aabbccddeeff00');
  assert.strictEqual(render('{{texto|semHifens}}', f), 'nada a ver');
});

test('data formata epoch em ms (string ou número) na hora local', () => {
  const d = new Date(1754320000000);
  const pad = (n) => String(n).padStart(2, '0');
  const esperado = `${pad(d.getDate())}/${pad(d.getMonth() + 1)}/${d.getFullYear()} ${pad(d.getHours())}:${pad(d.getMinutes())}`;
  assert.strictEqual(render('{{date | data}}', f), esperado);
  assert.strictEqual(render('{{dateNum | data}}', f), esperado);
});

test('quill junta os ops[].insert', () => {
  assert.strictEqual(render('{{after | quill}}', f), 'linha um\nlinha dois');
});

test('filtro desconhecido devolve o valor cru', () => {
  assert.strictEqual(render('{{texto | jamaisExistiu}}', f), 'nada a ver');
  assert.strictEqual(render('{{id | SEMHIFENS}}', f), f.id);   // lista fechada, sensível a caixa
});

test('filtro inaplicável devolve o valor cru', () => {
  assert.strictEqual(render('{{texto | data}}', f), 'nada a ver');   // não é epoch
  assert.strictEqual(render('{{texto | quill}}', f), 'nada a ver');  // não é JSON Quill
  assert.strictEqual(render('{{id | quill}}', f), f.id);
  assert.strictEqual(render('{{obj | semHifens}}', f), '');          // objeto continua vazio
  assert.strictEqual(render('{{nao.existe | data}}', f), '');
});
