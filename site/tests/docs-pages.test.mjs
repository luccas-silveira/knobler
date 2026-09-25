import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { build } from './build.mjs';
import { DOCS, carregarDocs } from '../src/lib/docs.mjs';
import { raiz } from '../src/lib/changelog.mjs';

const dist = build();
const pagina = (slug) => new URL(`docs/${slug}/index.html`, dist);
const html = (slug) => readFileSync(pagina(slug), 'utf8');
const main = (h) => h.match(/<main\b[^>]*>([\s\S]*?)<\/main>/)?.[1] ?? '';
const hrefs = (h) => [...h.matchAll(/\bhref="([^"]*)"/g)].map(([, v]) => v);
const docs = carregarDocs(new URL('docs/', raiz).pathname);

test('as 4 páginas de docs existem', () => {
  assert.equal(DOCS.length, 4);
  for (const slug of DOCS) assert.ok(existsSync(pagina(slug)), `sem dist/docs/${slug}/index.html`);
});

test('nenhum href aponta para .md relativo', () => {
  for (const slug of DOCS) {
    for (const h of hrefs(html(slug))) {
      if (/^[a-z][a-z0-9+.-]*:/i.test(h)) continue;
      assert.ok(!/\.md(#|$)/.test(h), `${slug}: href para .md relativo: ${h}`);
    }
  }
});

test('toda imagem listada pelo doc está em dist/docs/images/ e aparece na página', () => {
  assert.ok(docs.some((d) => d.imagens.length), 'nenhum doc com imagem');
  for (const { slug, imagens } of docs) {
    const m = main(html(slug));
    for (const img of imagens) {
      assert.ok(existsSync(new URL(`docs/${img}`, dist)), `imagem não copiada: docs/${img}`);
      assert.ok(m.includes(`src="/docs/${img}"`), `${slug}: <img> sem src="/docs/${img}"`);
    }
  }
});

test('toda <img> das páginas resolve dentro de dist', () => {
  for (const slug of DOCS) {
    for (const [, s] of main(html(slug)).matchAll(/<img\b[^>]*\bsrc="([^"]*)"/g)) {
      assert.ok(s.startsWith('/'), `${slug}: src relativo: ${s}`);
      assert.ok(existsSync(new URL(s.slice(1), dist)), `${slug}: imagem ausente: ${s}`);
    }
  }
});

test('cada página tem exatamente um h1', () => {
  for (const slug of DOCS) assert.equal((main(html(slug)).match(/<h1\b/g) ?? []).length, 1, slug);
});

test('Markdown renderizado, não cru', () => {
  for (const slug of DOCS) {
    const m = main(html(slug));
    assert.ok(!m.includes(']('), `${slug}: link Markdown cru`);
    assert.ok(!m.includes('```'), `${slug}: cerca de código crua`);
    assert.ok(!/(^|>)\s*#{1,3} /m.test(m.replace(/<pre[\s\S]*?<\/pre>/g, "")) /* comentário de shell em bloco de código não é título */, `${slug}: título Markdown cru`);
  }
});

test('local-api mostra o conteúdo real do doc', () => {
  const m = main(html('local-api'));
  assert.match(m, /<h1\b[^>]*>\s*API local\s*<\/h1>/);
  assert.match(m, /<h2\b[^>]*>[^<]*Visão geral/);
  assert.ok(m.includes('<code>127.0.0.1:4477</code>'), 'código inline não virou <code>');
  assert.ok(m.includes('O servidor escuta somente loopback'));
  assert.match(m, /<pre\b[^>]*>[\s\S]*<code\b/, 'bloco de código não virou <pre><code>');
});

test('link do rodapé /docs/local-api resolve', () => {
  const h = readFileSync(new URL('index.html', dist), 'utf8');
  const footer = h.match(/<footer\b[\s\S]*?<\/footer>/)?.[0] ?? '';
  assert.ok(hrefs(footer).includes('/docs/local-api'));
  assert.ok(existsSync(pagina('local-api')));
});
