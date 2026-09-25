import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';

const site = new URL('../', import.meta.url);
const ler = (nome) => readFileSync(new URL(nome, site), 'utf8');

test('site/package.json existe e declara o script build', () => {
  assert.ok(existsSync(new URL('package.json', site)), 'site/package.json não existe');
  const pkg = JSON.parse(ler('package.json'));
  assert.equal(typeof pkg.scripts?.build, 'string');
  assert.match(pkg.scripts.build, /astro build/);
});

test('site/package.json depende de astro', () => {
  const pkg = JSON.parse(ler('package.json'));
  assert.ok(pkg.dependencies?.astro, 'astro fora de dependencies');
});

test('astro.config.mjs declara o site knobler.appzoi.com.br', () => {
  assert.match(ler('astro.config.mjs'), /site:\s*['"]https:\/\/knobler\.appzoi\.com\.br\/?['"]/);
});

test('site/.gitignore ignora node_modules e dist', () => {
  const linhas = ler('.gitignore').split('\n').map((l) => l.trim());
  assert.ok(linhas.some((l) => /^\/?node_modules\/?$/.test(l)), 'node_modules não ignorado');
  assert.ok(linhas.some((l) => /^\/?dist\/?$/.test(l)), 'dist não ignorado');
});
