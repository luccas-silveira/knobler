import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { build } from './build.mjs';
import { currentVersion, downloadUrl } from '../src/lib/changelog.mjs';

const raiz = new URL('../../', import.meta.url);
const html = readFileSync(new URL('index.html', build()), 'utf8');
const esperado = downloadUrl(currentVersion(readFileSync(new URL('CHANGELOG.md', raiz), 'utf8')));

// <header class="menubar ..."> … </header> (tolera classes extras do Astro)
const menubar = html.match(/<header\b[^>]*class="[^"]*\bmenubar\b[^"]*"[^>]*>([\s\S]*?)<\/header>/)?.[1];
const footer = html.match(/<footer\b[^>]*>([\s\S]*?)<\/footer>/)?.[1];

const links = (trecho) =>
  [...trecho.matchAll(/<a\b([^>]*)>([\s\S]*?)<\/a>/g)].map(([, attrs, texto]) => ({
    href: attrs.match(/\bhref="([^"]*)"/)?.[1],
    texto: texto.replace(/<[^>]+>/g, '').trim(),
  }));
const hrefs = (trecho) => links(trecho).map((l) => l.href);

test('index.html declara lang="pt-BR" no <html>', () => {
  assert.match(html, /<html\b[^>]*\blang="pt-BR"/);
});

test('a página tem a barra de menus com o notch no meio', () => {
  assert.ok(menubar, 'sem <header class="menubar">');
  assert.match(menubar, /class="[^"]*\bnotch\b/);
});

test('o link "Baixar" da barra de menus aponta pro zip da versão atual', () => {
  assert.ok(menubar, 'sem <header class="menubar">');
  const baixar = links(menubar).filter((l) => l.texto === 'Baixar');
  assert.equal(baixar.length, 1, 'esperava exatamente um link "Baixar" na barra de menus');
  assert.equal(baixar[0].href, esperado);
});

test('o rodapé linka recursos, novidades, docs da API local e o GitHub', () => {
  assert.ok(footer, 'sem <footer>');
  const h = hrefs(footer);
  for (const rota of ['/recursos', '/novidades', '/docs/local-api']) {
    assert.ok(h.some((x) => x === rota || x === `${rota}/`), `rodapé sem link para ${rota}`);
  }
  assert.ok(
    h.some((x) => /^https:\/\/github\.com\/luccas-silveira\/knobler\/?$/.test(x)),
    'rodapé sem link para o repositório no GitHub',
  );
});
