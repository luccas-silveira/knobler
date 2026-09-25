// API esperada (etapa 2):
//
// site/src/lib/docs.mjs
//   export const DOCS: string[]
//     slugs dos docs técnicos publicados em /docs/<slug>, exatamente
//     ['local-api', 'webhooks', 'plugins', 'troubleshooting'] (arquivo = docs/<slug>.md).
//   export function reescreverLinks(markdown: string): { markdown: string, imagens: string[] }
//     Reescreve os destinos de `](...)` (inclusive quando `]` e `(` estão em linhas diferentes):
//       - <slug>.md[#ancora] com slug em DOCS   -> /docs/<slug>[#ancora]
//       - arquivo.md com entrada em RECURSOS_SLUGS -> /recursos/<slug>[#ancora]
//       - outro caminho relativo                 -> https://github.com/luccas-silveira/knobler/blob/master/docs/<caminho>
//       - images/x.png                           -> /docs/images/x.png, e 'images/x.png' entra em `imagens`
//       - http(s)://… e #ancora local            -> intactos
//   export function carregarDocs(docsDir: string | URL): Array<{ slug: string, markdown: string, imagens: string[] }>
//     Lê docsDir/<slug>.md para cada slug de DOCS, na ordem de DOCS, já reescrito.
//     Lança erro se algum arquivo da lista não existir.
//
// site/src/data/recursos-slugs.mjs
//   export const RECURSOS_SLUGS: Record<string, string>   // 'notifications.md' -> 'notificacoes'
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { DOCS, reescreverLinks, carregarDocs } from '../src/lib/docs.mjs';
import { RECURSOS_SLUGS } from '../src/data/recursos-slugs.mjs';

const docsDir = new URL('../../docs/', import.meta.url);
const GH = 'https://github.com/luccas-silveira/knobler/blob/master/docs/';
const md = (s) => reescreverLinks(s).markdown;

test('DOCS lista exatamente os quatro docs técnicos', () => {
  assert.deepEqual([...DOCS].sort(), ['local-api', 'plugins', 'troubleshooting', 'webhooks']);
});

test('carregarDocs lê os quatro docs reais do repo', () => {
  const docs = carregarDocs(docsDir);
  assert.deepEqual(docs.map((d) => d.slug), DOCS);
  for (const d of docs) assert.ok(d.markdown.length > 100, `${d.slug} vazio`);
});

test('carregarDocs lança erro se um doc da lista falta', () => {
  const dir = mkdtempSync(join(tmpdir(), 'docs-'));
  for (const s of ['local-api', 'webhooks', 'plugins']) writeFileSync(join(dir, `${s}.md`), '# x\n');
  assert.throws(() => carregarDocs(dir), /troubleshooting/);
});

test('link para doc da lista vira /docs/<slug> com âncora', () => {
  assert.equal(md('Ver [API](local-api.md).'), 'Ver [API](/docs/local-api).');
  assert.equal(md('[x](troubleshooting.md#reconceder)'), '[x](/docs/troubleshooting#reconceder)');
});

test('link para doc de recurso vira /recursos/<slug>', () => {
  assert.equal(md('[n](notifications.md)'), '[n](/recursos/notificacoes)');
  assert.equal(md('[t](texto-da-tela.md)'), '[t](/recursos/texto-da-tela)');
  assert.equal(md('[a](avisos.md#topo)'), '[a](/recursos/avisos#topo)');
});

test('RECURSOS_SLUGS não aponta para doc técnico nem para slug fora da etapa 5', () => {
  const previstos = new Set(['now-playing', 'huds', 'notificacoes', 'airpods', 'agenda', 'avisos',
    'pomodoro', 'descanso', 'lembretes-apple', 'alertas', 'ditado', 'prateleira', 'nota-rapida',
    'anotacao', 'texto-da-tela', 'conta-gotas', 'preview-de-link', 'espelho', 'mensagens', 'webhooks']);
  for (const [arq, slug] of Object.entries(RECURSOS_SLUGS)) {
    assert.ok(previstos.has(slug), `${arq} -> ${slug} fora da lista`);
    assert.ok(!DOCS.includes(arq.replace(/\.md$/, '')), `${arq} é doc técnico`);
  }
});

test('link para outro arquivo do repo vai para o GitHub', () => {
  assert.equal(md('[r](relay-operacao.md)'), `[r](${GH}relay-operacao.md)`);
  assert.equal(
    md('[i](development.md#instalação-local-do-build)'),
    `[i](${GH}development.md#instalação-local-do-build)`,
  );
});

test('link com quebra de linha entre ] e ( é reescrito igual', () => {
  const saida = md('Ver [Operação do\nrelay]\n(relay-operacao.md) e [n]\n(notifications.md).');
  assert.ok(saida.includes(`(${GH}relay-operacao.md)`), saida);
  assert.ok(saida.includes('(/recursos/notificacoes)'), saida);
  assert.ok(!/\((relay-operacao|notifications)\.md\)/.test(saida), saida);
});

test('URLs absolutas e âncoras locais ficam intactas', () => {
  const e = 'Veja [site](https://example.com/local-api.md) e [s](http://x.io/a.md) e [aqui](#secao).';
  assert.equal(md(e), e);
});

test('imagem vira /docs/images/ e entra na lista de cópia', () => {
  const r = reescreverLinks('![Painel](images/x.png)\n\n[s](https://a.b/images/y.png)');
  assert.equal(r.markdown, '![Painel](/docs/images/x.png)\n\n[s](https://a.b/images/y.png)');
  assert.deepEqual(r.imagens, ['images/x.png']);
});

test('docs reais: nenhum link .md relativo sobra e as imagens citadas são listadas', () => {
  for (const d of carregarDocs(docsDir)) {
    assert.ok(!/\]\s*\((?!https?:|\/|#)[^)]*\.md/.test(d.markdown), `${d.slug} ainda tem link .md relativo`);
    assert.ok(!/\]\s*\(images\//.test(d.markdown), `${d.slug} tem imagem sem reescrita`);
  }
  const plugins = carregarDocs(docsDir).find((d) => d.slug === 'plugins');
  assert.ok(plugins.imagens.includes('images/settings-plugins.png'));
  assert.ok(plugins.markdown.includes('(/recursos/texto-da-tela)'));
  const tr = carregarDocs(docsDir).find((d) => d.slug === 'troubleshooting');
  assert.ok(tr.markdown.includes(`${GH}development.md#instalação-local-do-build`));
});
