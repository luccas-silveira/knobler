import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { build } from './build.mjs';
import { parseChangelog, currentVersion, raiz } from '../src/lib/changelog.mjs';

const dist = build();
const changelog = readFileSync(new URL('CHANGELOG.md', raiz), 'utf8');
const versoes = parseChangelog(changelog).map((v) => v.version);
const arquivo = new URL('novidades/index.html', dist);
const html = () => readFileSync(arquivo, 'utf8');
const main = (h) => h.match(/<main\b[^>]*>([\s\S]*?)<\/main>/)?.[1] ?? '';
const texto = (h) => h.replace(/<[^>]+>/g, ' ').replace(/\s+/g, ' ');

// Contrato: cada versão é um <h2> com o número; a entrada vai até o próximo <h2>.
function entradas() {
  const partes = main(html()).split(/(?=<h2\b)/).filter((p) => p.startsWith('<h2'));
  return partes.map((p) => ({ versao: texto(p.match(/<h2\b[^>]*>([\s\S]*?)<\/h2>/)[1]).match(/\d+\.\d+\.\d+/)?.[0], corpo: p }));
}
const entrada = (v) => entradas().find((e) => e.versao === v)?.corpo ?? assert.fail(`sem entrada para ${v}`);

test('dist/novidades/index.html existe', () => {
  assert.ok(existsSync(arquivo));
});

test('uma entrada por versão do CHANGELOG, na mesma ordem', () => {
  assert.deepEqual(entradas().map((e) => e.versao), versoes);
});

test('a primeira entrada é a versão atual', () => {
  assert.equal(entradas()[0]?.versao, currentVersion(changelog));
});

test('a entrada 0.35.0 mostra o texto de Knobler/Novidades/0.35.0.html', () => {
  const corpo = texto(entrada('0.35.0'));
  assert.ok(corpo.includes('Ações rápidas: atalhos pra qualquer seção'));
  assert.ok(corpo.includes('Um conta-gotas pra pegar a cor'));
});

test('a entrada 0.35.2 mostra o item do CHANGELOG sob "Corrigido"', () => {
  const corpo = texto(entrada('0.35.2'));
  assert.ok(corpo.includes('ele é encerrado à força e reaberto na versão nova'));
  assert.ok(corpo.includes('Corrigido'));
});

test('rótulos de seção em pt-BR, nunca os do CHANGELOG', () => {
  const t = texto(main(html()));
  for (const r of ['Novo', 'Corrigido', 'Mudou', 'Removido', 'Documentação']) assert.ok(t.includes(r), `sem rótulo ${r}`);
  for (const en of ['Added', 'Fixed', 'Changed', 'Removed', 'Documentation']) assert.ok(!new RegExp(`\\b${en}\\b`).test(t), `rótulo em inglês: ${en}`);
});

test('toda imagem referenciada existe em dist (inclui as de midia/)', () => {
  const srcs = [...main(html()).matchAll(/<img\b[^>]*\bsrc="([^"]*)"/g)].map(([, s]) => s);
  assert.ok(srcs.some((s) => s.includes('midia/')), 'nenhuma imagem de midia/ na página (0.25.0 e 0.26.0 têm)');
  for (const s of srcs) {
    assert.ok(s.startsWith('/'), `src relativo quebra fora da raiz: ${s}`);
    assert.ok(existsSync(new URL(s.slice(1), dist)), `imagem ausente no build: ${s}`);
  }
});
