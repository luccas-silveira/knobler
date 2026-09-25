// Etapa 8: página /instalar.
// Estrutura esperada (a do mockup, seção /instalar): dentro de <main>, três
// elementos com a classe `install-step`, na ordem 1, 2, 3; o bloco Homebrew é um
// <pre> com os três comandos, um por linha.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { build } from './build.mjs';
import { raiz, currentVersion, downloadUrl } from '../src/lib/changelog.mjs';

const dist = build();
const arquivo = new URL('instalar/index.html', dist);
const html = () => readFileSync(arquivo, 'utf8');
const main = (h) => h.match(/<main\b[^>]*>([\s\S]*?)<\/main>/)?.[1] ?? '';
const versao = currentVersion(readFileSync(new URL('CHANGELOG.md', raiz), 'utf8'));
const texto = (s) => s.replace(/<[^>]+>/g, ' ').replace(/&quot;|&#34;/g, '"').replace(/\s+/g, ' ');
// Fatia do main a partir de cada install-step até o próximo (ou até o fim).
const passos = (m) => m.split(/<[a-z]+\b[^>]*\bclass="[^"]*\binstall-step\b[^"]*"/).slice(1);

test('a página /instalar existe', () => {
  assert.ok(existsSync(arquivo), 'sem dist/instalar/index.html');
});

test('botão de download aponta para o zip da versão atual do CHANGELOG', () => {
  const m = main(html());
  assert.ok(m.includes(`href="${downloadUrl(versao)}"`), `sem link para ${downloadUrl(versao)}`);
});

test('nome do zip da versão atual aparece na página', () => {
  assert.ok(texto(main(html())).includes(`Knobler-${versao}.zip`), `sem Knobler-${versao}.zip`);
});

test('tem exatamente três passos', () => {
  assert.equal(passos(main(html())).length, 3);
});

test('bloco Homebrew tem os três comandos exatos, em linhas próprias e na ordem', () => {
  const pres = [...main(html()).matchAll(/<pre\b[^>]*>([\s\S]*?)<\/pre>/g)].map(([, p]) => texto(p.replace(/\n/g, '\u0000')));
  const cmds = ['brew tap luccas-silveira/knobler', 'brew trust luccas-silveira/knobler', 'brew install knobler'];
  const ok = pres.some((p) => {
    const linhas = p.split('\u0000').map((l) => l.trim()).filter(Boolean);
    return cmds.every((c, i) => linhas.indexOf(c) === linhas.indexOf(cmds[0]) + i && linhas.includes(c));
  });
  assert.ok(ok, `nenhum <pre> com:\n${cmds.join('\n')}\nachados: ${JSON.stringify(pres)}`);
});

test('passo 2 cita "Privacidade e Segurança" e "Abrir Mesmo Assim"', () => {
  const p2 = texto(passos(main(html()))[1] ?? '');
  assert.ok(p2.includes('Privacidade e Segurança'), 'passo 2 sem "Privacidade e Segurança"');
  assert.ok(p2.includes('Abrir Mesmo Assim'), 'passo 2 sem "Abrir Mesmo Assim"');
});

test('nenhuma menção a Control-clique na página inteira', () => {
  const t = html();
  for (const proibido of [/control-clique/i, /control-clic/i, /ctrl-clique/i]) {
    assert.ok(!proibido.test(t), `página cita ${proibido}`);
  }
});

// Etapa 9: capturas reais no lugar dos placeholders.
const imgs = (h) => [...h.matchAll(/<img\b[^>]*>/g)].map(([t]) => t);
const comAlt = (t) => /\balt="[^"]*\S[^"]*"/.test(t);

test('instalar.astro não usa mais imagemPendente', () => {
  const fonte = readFileSync(new URL('../src/pages/instalar.astro', import.meta.url), 'utf8');
  assert.ok(!fonte.includes('imagemPendente'), 'instalar.astro ainda cita imagemPendente');
});

test('cada passo tem <img> com alt; passo 2 tem duas (alerta e Privacidade)', () => {
  const ps = passos(main(html()));
  assert.equal(ps.length, 3);
  const n = ps.map((p) => imgs(p).filter(comAlt).length);
  assert.ok(n[0] >= 1 && n[1] >= 2 && n[2] >= 1, `imgs com alt por passo: ${JSON.stringify(n)}`);
});

test('nenhum placeholder shot-ph sobra na página', () => {
  assert.ok(!/\bshot-ph\b/.test(main(html())), 'ainda há .shot-ph');
});

test('todo src de <img> em /instalar existe no build', () => {
  const srcs = imgs(main(html())).map((t) => t.match(/\bsrc="([^"]+)"/)?.[1]);
  assert.ok(srcs.length >= 4, `só ${srcs.length} <img>`);
  for (const s of srcs) {
    assert.ok(s && s.startsWith('/'), `src inválido: ${s}`);
    assert.ok(existsSync(new URL('.' + s.split('?')[0], dist)), `${s} não existe em dist`);
  }
});
