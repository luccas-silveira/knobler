import { existsSync, readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { pathToFileURL } from 'node:url';

// Raiz do repo, para quem precisar resolver CHANGELOG.md e Knobler/Novidades/.
// Sobe do cwd até achar CHANGELOG.md: o import.meta.url muda depois do bundle do Astro.
function acharRaiz(dir = process.cwd()) {
  if (existsSync(join(dir, 'CHANGELOG.md'))) return pathToFileURL(dir + '/');
  if (dirname(dir) === dir) throw new Error('CHANGELOG.md não encontrado acima do cwd');
  return acharRaiz(dirname(dir));
}
export const raiz = acharRaiz();

export const versaoAtual = () => currentVersion(readFileSync(new URL('CHANGELOG.md', raiz), 'utf8'));

// Versões numeradas em ordem; ignora [Unreleased]. Item multilinha vira um só.
export function parseChangelog(texto) {
  const versoes = [];
  let versao = null;
  let secao = null;
  for (const linha of texto.split('\n')) {
    const cab = linha.match(/^## \[([^\]]+)\](?:\s*-\s*(\S+))?/);
    if (cab) {
      versao = /^\d+\.\d+\.\d+$/.test(cab[1]) ? { version: cab[1], date: cab[2] ?? null, sections: {} } : null;
      if (versao) versoes.push(versao);
      secao = null;
      continue;
    }
    if (!versao) continue;
    const sec = linha.match(/^### (\w+)/);
    if (sec) {
      secao = versao.sections[sec[1]] ??= [];
      continue;
    }
    if (!secao) continue;
    const item = linha.match(/^[-*] (.*)/);
    if (item) secao.push(item[1].trim());
    else if (linha.trim() && secao.length) secao[secao.length - 1] += '\n' + linha.trim();
  }
  return versoes;
}

export function currentVersion(texto) {
  const v = parseChangelog(texto)[0];
  if (!v) throw new Error('CHANGELOG sem nenhuma versão numerada');
  return v.version;
}

export const downloadUrl = (v) =>
  `https://github.com/luccas-silveira/knobler/releases/download/v${v}/Knobler-${v}.zip`;

export function novidadesHtml(version, dir = new URL('Knobler/Novidades/', raiz).pathname) {
  const arq = join(dir, `${version}.html`);
  if (!existsSync(arq)) return null;
  return readFileSync(arq, 'utf8').replace(/(["'(])midia\//g, '$1/novidades/midia/');
}
