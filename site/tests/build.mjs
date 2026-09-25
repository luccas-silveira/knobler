// Helper de teste: roda o build do site uma vez por processo e devolve a URL do
// diretório de saída. `node --test` roda cada arquivo num processo próprio e em
// paralelo, então cada processo builda numa pasta temporária sua: dois builds no
// mesmo dist/ colidem. A pasta fica dentro de site/ (ignorada no git): fora do cwd
// o Astro volta a usar o .astro/ compartilhado e os builds colidem ali.
import { execFileSync } from 'node:child_process';
import { mkdtempSync } from 'node:fs';
import { mkdirSync } from 'node:fs';
import { join } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const site = new URL('../', import.meta.url);
let dist;

export function build() {
  if (!dist) {
    const base = join(fileURLToPath(site), '.test-dist');
    mkdirSync(base, { recursive: true });
    const out = mkdtempSync(join(base, 'build-'));
    execFileSync('npx', ['astro', 'build', '--outDir', out], { cwd: fileURLToPath(site), stdio: 'pipe' });
    dist = pathToFileURL(out + '/');
  }
  return dist;
}
