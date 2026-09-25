import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync, existsSync } from 'node:fs';
import { build } from './build.mjs';
import { recursos } from '../src/data/recursos.mjs';
import { RECURSOS_SLUGS } from '../src/data/recursos-slugs.mjs';

const dist = build();
const pagina = (slug) => new URL(`recursos/${slug}/index.html`, dist);
const ler = (u) => readFileSync(u, 'utf8');
const main = (html) => html.match(/<main\b[^>]*>([\s\S]*?)<\/main>/)?.[1] ?? '';
const hrefs = (html) => [...html.matchAll(/<a\b[^>]*\bhref="([^"]*)"/g)].map(([, h]) => h.replace(/\/$/, ''));
const slugs = recursos.map((r) => r.slug);

test('recursos.mjs tem 20 recursos', () => {
  assert.equal(new Set(slugs).size, 20);
});

test('existem 20 páginas em dist/recursos/*/index.html', () => {
  const dirs = readdirSync(new URL('recursos/', dist), { withFileTypes: true })
    .filter((d) => d.isDirectory() && existsSync(pagina(d.name))).map((d) => d.name).sort();
  assert.deepEqual(dirs, [...slugs].sort());
});

test('só conta-gotas e espelho ficam sem imagem', () => {
  assert.deepEqual(recursos.filter((r) => r.imagemPendente).map((r) => r.slug).sort(), ['conta-gotas', 'espelho']);
});

for (const [i, r] of recursos.entries()) {
  test(`dados de ${r.slug} estão completos`, () => {
    for (const k of ['resumo', 'comoFunciona']) assert.ok(r[k]?.trim?.(), `${r.slug} sem ${k}`);
    assert.ok(Array.isArray(r.comoLigar) && r.comoLigar.length > 0, `${r.slug} sem comoLigar[]`);
    if (!r.imagemPendente) {
      assert.ok(r.imagem, `${r.slug} sem imagem`);
      assert.ok(r.alt?.trim(), `${r.slug} sem alt`);
    }
  });

  test(`/recursos/${r.slug} tem h1 com o título`, () => {
    const h1 = ler(pagina(r.slug)).match(/<h1\b[^>]*>([\s\S]*?)<\/h1>/)?.[1];
    assert.ok(h1, 'sem <h1>');
    assert.ok(h1.replace(/<[^>]+>/g, '').includes(r.titulo), `h1 não mostra "${r.titulo}"`);
  });

  if (!r.imagemPendente) {
    test(`/recursos/${r.slug} tem imagem com alt não vazio`, () => {
      const imgs = [...main(ler(pagina(r.slug))).matchAll(/<img\b[^>]*>/g)].map(([t]) => t);
      assert.ok(imgs.some((img) => /\balt="[^"]*\S[^"]*"/.test(img)), 'sem <img> com alt no <main>');
    });
  }

  test(`/recursos/${r.slug} linka anterior e próximo que existem`, () => {
    const links = hrefs(main(ler(pagina(r.slug)))).filter((h) => h.startsWith('/recursos/') && h !== `/recursos/${r.slug}`);
    for (const h of links) assert.ok(slugs.includes(h.slice('/recursos/'.length)), `link para recurso inexistente: ${h}`);
    const vizinhos = [recursos[i - 1], recursos[i + 1]].filter(Boolean);
    for (const v of vizinhos) assert.ok(links.includes(`/recursos/${v.slug}`), `sem link para o vizinho ${v.slug}`);
  });
}

test('/recursos/ lista os 20 recursos', () => {
  const links = hrefs(main(ler(new URL('recursos/index.html', dist))));
  for (const s of slugs) assert.ok(links.includes(`/recursos/${s}`), `sem link para /recursos/${s}`);
});

test('todo slug de recursos-slugs.mjs tem página gerada', () => {
  for (const [doc, s] of Object.entries(RECURSOS_SLUGS)) assert.ok(existsSync(pagina(s)), `${doc} → ${s} sem página`);
});
