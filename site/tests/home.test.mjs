import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { build } from './build.mjs';
import { currentVersion, downloadUrl } from '../src/lib/changelog.mjs';

const raiz = new URL('../../', import.meta.url);
const html = readFileSync(new URL('index.html', build()), 'utf8');
const versao = currentVersion(readFileSync(new URL('CHANGELOG.md', raiz), 'utf8'));
const esperado = downloadUrl(versao);

// Conteúdo da home: o <main>, fora da barra de menus e do rodapé.
const main = html.match(/<main\b[^>]*>([\s\S]*?)<\/main>/)?.[1] ?? '';
const links = [...main.matchAll(/<a\b([^>]*)>([\s\S]*?)<\/a>/g)].map(([, attrs, texto]) => ({
  href: attrs.match(/\bhref="([^"]*)"/)?.[1],
  texto: texto.replace(/<[^>]+>/g, '').replace(/\s+/g, ' ').trim(),
}));
const hrefs = links.map((l) => l.href);
const temRota = (rota) => hrefs.some((h) => h === rota || h === `${rota}/`);

const slugs = [
  'now-playing', 'huds', 'notificacoes', 'airpods', 'agenda', 'avisos',
  'pomodoro', 'descanso', 'lembretes-apple', 'alertas',
  'ditado', 'prateleira', 'nota-rapida', 'anotacao', 'texto-da-tela', 'conta-gotas', 'preview-de-link', 'espelho',
  'mensagens', 'webhooks',
];

test('a lista de recursos esperados tem 20 slugs distintos', () => {
  assert.equal(new Set(slugs).size, 20);
});

test('a home tem um <main> com conteúdo', () => {
  assert.ok(main.trim(), 'sem <main>');
});

test('a home mostra a versão atual fora da barra de menus', () => {
  assert.match(main.replace(/<[^>]+>/g, ' '), new RegExp(`\\b${versao.replace(/\./g, '\\.')}\\b`));
});

test('o botão "Baixar para Mac" aponta pro zip da versão atual', () => {
  const baixar = links.filter((l) => l.texto.includes('Baixar para Mac'));
  assert.ok(baixar.length >= 1, 'sem link "Baixar para Mac" no <main>');
  for (const b of baixar) assert.equal(b.href, esperado);
});

for (const slug of slugs) {
  test(`a home linka /recursos/${slug}`, () => {
    assert.ok(temRota(`/recursos/${slug}`), `sem link para /recursos/${slug}`);
  });
}

test('o grupo de automação linka /docs/local-api e /docs/plugins', () => {
  assert.ok(temRota('/docs/local-api'), 'sem link para /docs/local-api');
  assert.ok(temRota('/docs/plugins'), 'sem link para /docs/plugins');
});

test('a home mostra os quatro grupos', () => {
  const texto = main.replace(/<[^>]+>/g, ' ').replace(/\s+/g, ' ');
  for (const g of ['O que já acontece no Mac', 'Foco', 'Fale, guarde, anote', 'Para quem automatiza']) {
    assert.ok(texto.includes(g), `sem o grupo "${g}"`);
  }
});

test('a home tem imagens e toda <img> tem alt não vazio', () => {
  const imgs = [...html.matchAll(/<img\b[^>]*>/g)].map(([t]) => t);
  assert.ok(imgs.length > 0, 'a home não tem nenhuma <img>');
  for (const img of imgs) {
    assert.match(img, /\balt="[^"]*\S[^"]*"/, `<img> sem alt: ${img}`);
  }
});
