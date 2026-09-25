// Etapa 11: deploy do site e ligação com o release. Não toca a rede: lê os
// scripts como texto e confere ordem, destino e tolerância a falha.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, statSync } from 'node:fs';

const raiz = new URL('../../', import.meta.url);
const ler = (p) => readFileSync(new URL(p, raiz), 'utf8');

test('site/deploy.sh existe, é executável e para no primeiro erro', () => {
  assert.ok(statSync(new URL('site/deploy.sh', raiz)).mode & 0o111, 'sem bit de execução');
  assert.match(ler('site/deploy.sh'), /^set -euo pipefail$/m);
});

test('deploy.sh builda e sincroniza dist/ com o servidor', () => {
  const s = ler('site/deploy.sh');
  assert.match(s, /npm ci/);
  assert.match(s, /npm run build/);
  assert.match(s, /rsync [^\n]*--delete[^\n]*dist\/ root@147\.79\.87\.179:\/var\/www\/knobler-site\//);
});

test('deploy.sh --dry-run repassa --dry-run ao rsync', () => {
  const s = ler('site/deploy.sh');
  assert.match(s, /--dry-run/);
  assert.match(s, /rsync [^\n]*\$\{?[A-Za-z_]+/, 'rsync sem variável para o --dry-run');
});

test('release.sh chama site/deploy.sh depois do gh release, sem abortar se falhar', () => {
  const linhas = ler('tools/release.sh').split('\n');
  const gh = linhas.findIndex((l) => /gh release create/.test(l));
  const dep = linhas.findIndex((l) => /site\/deploy\.sh/.test(l) && !/^\s*#/.test(l));
  assert.ok(gh >= 0 && dep > gh, 'deploy do site precisa vir depois do gh release create');
  assert.match(linhas[dep], /\|\|\s*echo/);
});
