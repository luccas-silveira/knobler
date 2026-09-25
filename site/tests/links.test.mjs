// Etapa 10: links internos do dist resolvem, e o check.sh/CI rodam os testes do site.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync, existsSync, statSync } from 'node:fs';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { build } from './build.mjs';

const raiz = fileURLToPath(new URL('../../', import.meta.url));

function htmls(dir) {
  return readdirSync(dir, { withFileTypes: true }).flatMap((e) =>
    e.isDirectory() ? htmls(join(dir, e.name)) : e.name.endsWith('.html') ? [join(dir, e.name)] : []);
}

function resolve(dist, url) {
  const p = decodeURIComponent(url.split(/[?#]/)[0]);
  const isFile = (f) => existsSync(f) && statSync(f).isFile();
  if (p === '/' || p.endsWith('/')) return isFile(join(dist, p, 'index.html'));
  return isFile(join(dist, p)) || isFile(join(dist, p, 'index.html')) || isFile(join(dist, p + '.html'));
}

test('todo href/src interno do dist resolve para um arquivo', () => {
  const dist = fileURLToPath(build());
  const paginas = htmls(dist);
  assert.ok(paginas.length > 0, 'build sem nenhum .html');
  const quebrados = [];
  let vistos = 0;
  for (const f of paginas) {
    const html = readFileSync(f, 'utf8');
    for (const [, url] of html.matchAll(/\s(?:href|src)="([^"]*)"/g)) {
      if (!url.startsWith('/') || url.startsWith('//')) continue;
      vistos++;
      if (!resolve(dist, url)) quebrados.push(`${f.slice(dist.length)} -> ${url}`);
    }
  }
  assert.ok(vistos > 0, 'nenhum link interno encontrado: regex ou build errado');
  assert.deepEqual(quebrados, []);
});

test('tools/check.sh tem run site-build rodando node --test site/tests/*.test.mjs', () => {
  const sh = readFileSync(join(raiz, 'tools/check.sh'), 'utf8');
  const linha = sh.split('\n').find((l) => /^\s*run\s+site-build\s/.test(l));
  assert.ok(linha, 'sem entrada `run site-build` ativa (comentada não conta)');
  assert.match(linha, /node --test site\/tests\/\*\.test\.mjs/, 'tem que rodar todos os testes do site, não um só');
  assert.match(linha, /npm ci/, 'sem npm ci as dependências do site não existem na CI');
});

test('ci.yml configura setup-node 22 antes de ./tools/check.sh', () => {
  const yml = readFileSync(join(raiz, '.github/workflows/ci.yml'), 'utf8');
  const setup = yml.search(/uses:\s*actions\/setup-node@v4/);
  const check = yml.search(/run:\s*\.\/tools\/check\.sh/);
  assert.ok(setup >= 0, 'sem actions/setup-node@v4');
  assert.ok(check >= 0, 'sem passo ./tools/check.sh');
  assert.ok(setup < check, 'setup-node vem depois do check');
  const bloco = yml.slice(setup, check);
  assert.match(bloco, /node-version:\s*['"]?22['"]?\s*$/m, 'node-version 22 não está no passo do setup-node');
});
