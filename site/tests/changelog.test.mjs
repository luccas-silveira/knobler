import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, mkdtempSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import {
  parseChangelog,
  currentVersion,
  downloadUrl,
  novidadesHtml,
} from '../src/lib/changelog.mjs';

const raiz = new URL('../../', import.meta.url);

const EXEMPLO = `# Changelog

Formato baseado em Keep a Changelog.

## [Unreleased]

### Added
- Coisa ainda não lançada.

## [0.35.2] - 2026-09-24

### Fixed

- Encerra à força depois de 10 s,
  em vez de ficar parado.

## [0.35.0] - 2026-09-24

### Added
- Ações rápidas.
- Seção Cor: conta-gotas.

### Fixed
- Listas de seções.

### Changed
- Ajustes em grupos.

### Removed
- Aba antiga.

### Documentation
- Guia novo.
`;

test('parseChangelog ignora Unreleased e devolve versões em ordem com data', () => {
  const vs = parseChangelog(EXEMPLO);
  assert.deepEqual(vs.map((v) => [v.version, v.date]), [
    ['0.35.2', '2026-09-24'],
    ['0.35.0', '2026-09-24'],
  ]);
  assert.ok(!JSON.stringify(vs).includes('ainda não lançada'));
});

test('parseChangelog agrupa itens nas cinco seções', () => {
  const s = parseChangelog(EXEMPLO)[1].sections;
  assert.deepEqual(s.Added, ['Ações rápidas.', 'Seção Cor: conta-gotas.']);
  assert.deepEqual(s.Fixed, ['Listas de seções.']);
  assert.deepEqual(s.Changed, ['Ajustes em grupos.']);
  assert.deepEqual(s.Removed, ['Aba antiga.']);
  assert.deepEqual(s.Documentation, ['Guia novo.']);
});

test('parseChangelog junta item de várias linhas num item só', () => {
  const s = parseChangelog(EXEMPLO)[0].sections;
  assert.equal(s.Fixed.length, 1);
  assert.match(s.Fixed[0], /^Encerra à força depois de 10 s,\s+em vez de ficar parado\.$/);
});

test('parseChangelog tolera com e sem linha em branco após ### X', () => {
  const com = parseChangelog('## [1.0.0] - 2026-01-01\n\n### Added\n\n- A\n');
  const sem = parseChangelog('## [1.0.0] - 2026-01-01\n\n### Added\n- A\n');
  assert.deepEqual(com[0].sections.Added, ['A']);
  assert.deepEqual(sem[0].sections.Added, ['A']);
});

test('currentVersion devolve a primeira versão numerada', () => {
  assert.equal(currentVersion(EXEMPLO), '0.35.2');
});

test('currentVersion lança erro claro sem versão numerada', () => {
  assert.throws(
    () => currentVersion('# Changelog\n\n## [Unreleased]\n- x\n'),
    (e) => e instanceof Error && /vers/i.test(e.message),
  );
});

test('downloadUrl monta o link do release no GitHub', () => {
  assert.equal(
    downloadUrl('0.35.2'),
    'https://github.com/luccas-silveira/knobler/releases/download/v0.35.2/Knobler-0.35.2.zip',
  );
});

test('novidadesHtml devolve o fragmento e reescreve midia/', () => {
  const dir = mkdtempSync(join(tmpdir(), 'novidades-'));
  writeFileSync(
    join(dir, '9.9.9.html'),
    '<section class="novidade"><img src="midia/a.png"><video src="midia/b.mp4"></video></section>',
  );
  const html = novidadesHtml('9.9.9', dir);
  assert.match(html, /<section class="novidade">/);
  assert.ok(html.includes('src="/novidades/midia/a.png"'));
  assert.ok(html.includes('src="/novidades/midia/b.mp4"'));
  assert.ok(!/src="midia\//.test(html));
  assert.ok(!html.includes('/novidades/novidades/'));
});

test('novidadesHtml devolve null quando a versão não tem arquivo', () => {
  const dir = mkdtempSync(join(tmpdir(), 'novidades-'));
  assert.equal(novidadesHtml('0.0.1', dir), null);
});

test('novidadesHtml lê o fragmento real da 0.35.0', () => {
  const html = novidadesHtml('0.35.0', new URL('Knobler/Novidades/', raiz).pathname);
  assert.match(html, /Ações rápidas/);
});

test('CHANGELOG.md real tem versão atual X.Y.Z', () => {
  const texto = readFileSync(new URL('CHANGELOG.md', raiz), 'utf8');
  assert.match(currentVersion(texto), /^\d+\.\d+\.\d+$/);
  assert.ok(parseChangelog(texto).length > 10);
});
